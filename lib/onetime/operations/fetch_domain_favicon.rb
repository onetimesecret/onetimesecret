# lib/onetime/operations/fetch_domain_favicon.rb
#
# frozen_string_literal: true

require 'base64'
require 'stringio'
require 'uri'
require 'nokogiri'
require 'fastimage'

require_relative '../http/safe_fetch'
require_relative '../jobs/workers/job_lifecycle'

module Onetime
  module Operations
    #
    # Fetches a custom domain's favicon from the live domain and stores it in
    # the CustomDomain's `icon` hashkey (#3780). This is the unit of work shared
    # by the FaviconFetchWorker (Sneakers) AND the Publisher's jobs-disabled
    # inline fallback, so it owns the full lifecycle: it loads the model, applies
    # the overwrite guard, discovers + fetches the image through the SSRF-guarded
    # SafeFetch, writes the icon in the same shape UpdateDomainImage produces, and
    # stamps the favicon_fetch_* lifecycle/outcome fields.
    #
    # Discovery order (every hop SSRF-guarded inside SafeFetch):
    #   1. GET https://<domain>/favicon.ico
    #   2. GET https://<domain>/ and parse <link rel~=icon> hrefs, then fetch the
    #      best raster candidate (SVG dropped).
    #
    # Signalling contract for the worker (see #call):
    #   - Handled outcomes (icon written, none found, guard skip, domain missing)
    #     RETURN a Result and never raise — the worker acks.
    #   - A transient SafeFetch::FetchTimeout is RE-RAISED (lifecycle left at
    #     PROCESSING) so the worker can requeue for a RabbitMQ retry.
    #   - Any other unexpected error stamps status=FAILED + favicon_fetch_error
    #     and is RE-RAISED so the worker can reject to the DLQ.
    #
    # Usage:
    #   result = FetchDomainFavicon.new(domain_id: 'abc123').call
    #   result.favicon_fetched      # => true/false
    #   result.status               # => 'completed' / 'failed' / nil (missing)
    #   result.success?             # => true unless .error is set
    #
    # Manual refresh (Phase 2) forces past the skip-existing-auto guard:
    #   FetchDomainFavicon.new(domain_id: 'abc123', force: true).call
    #
    class FetchDomainFavicon
      include Onetime::LoggerMethods

      JobLifecycle = Onetime::Jobs::Workers::JobLifecycle

      # Fallbacks mirror blueprint §5 — the jobs tree is absent from the in-code
      # DEFAULTS hash, so runtime reads must dig-with-fallback.
      DEFAULT_TIMEOUT         = 5
      DEFAULT_MAX_BYTES       = 102_400
      DEFAULT_MAX_REDIRECTS   = 3
      DEFAULT_CONTENT_TYPES   = %w[image/x-icon image/vnd.microsoft.icon image/png].freeze

      # ICO carries no reliable single dimension; passthrough uses a nominal
      # square when FastImage can't report one.
      ICO_NOMINAL_SIZE = [32, 32].freeze

      # Cap HTML-discovered candidates so a hostile page can't fan out into many
      # SSRF-guarded fetches.
      MAX_CANDIDATES = 5

      # Immutable result. `error` nil means the run reached a handled outcome.
      Result = Data.define(
        :domain_id,       # String
        :status,          # JobLifecycle string, or nil when the domain was missing
        :favicon_fetched, # Boolean outcome (nil when the domain was missing)
        :favicon_source,  # 'auto_fetch' when this run wrote the icon, else nil
        :content_type,    # stored MIME on a write, else nil
        :final_url,       # provenance URL of the written icon, else nil
        :skipped,         # true when the overwrite guard blocked the write
        :not_found,       # true when the CustomDomain did not load (permanent miss)
        :error,           # String or nil
      ) do
        def success?
          error.nil?
        end

        # A write actually landed on this run.
        def written?
          !content_type.nil?
        end

        def to_h
          {
            domain_id: domain_id,
            status: status,
            favicon_fetched: favicon_fetched,
            favicon_source: favicon_source,
            content_type: content_type,
            final_url: final_url,
            skipped: skipped,
            not_found: not_found,
            error: error,
          }.compact
        end
      end

      # @param domain_id [String] CustomDomain identifier (objid == domainid)
      # @param force [Boolean] re-fetch even when an auto_fetch icon already exists
      # @param fetcher [Onetime::Http::SafeFetch, nil] injectable override (tests)
      # @param custom_domain [Onetime::CustomDomain, nil] injectable override (tests)
      def initialize(domain_id:, force: false, fetcher: nil, custom_domain: nil)
        @domain_id     = domain_id
        @force         = force
        @fetcher       = fetcher
        @custom_domain = custom_domain
      end

      # Executes the fetch. See the class comment for the raise-vs-return contract.
      #
      # @return [Result]
      # @raise [Onetime::Http::SafeFetch::FetchTimeout] transient — worker requeues
      # @raise [StandardError] unexpected — worker rejects to DLQ (status=FAILED)
      def call
        custom_domain = resolve_domain
        if custom_domain.nil?
          logger.warn 'Favicon fetch skipped: CustomDomain not found', domain_id: @domain_id
          return not_found_result
        end

        # Overwrite guard runs BEFORE marking PROCESSING so a skip leaves the
        # persisted lifecycle untouched (no churn, no race with verify_domain).
        guard_result = overwrite_guard(custom_domain)
        return guard_result if guard_result

        mark_processing(custom_domain)

        image = discover_and_fetch(custom_domain.display_domain)

        if image
          write_icon(custom_domain, image)
          record_success(custom_domain)
          logger.info 'Favicon fetched and stored',
            domain_id: @domain_id,
            domain: custom_domain.display_domain,
            content_type: image.content_type,
            final_url: image.final_url,
            bytes: image.body.bytesize
          success_result(image)
        else
          record_none_found(custom_domain)
          logger.info 'Favicon fetch found no usable icon',
            domain_id: @domain_id,
            domain: custom_domain.display_domain
          none_found_result
        end
      rescue Onetime::Http::SafeFetch::FetchTimeout => ex
        # Transient — leave the lifecycle at PROCESSING and re-raise so the worker
        # requeues for a RabbitMQ retry (do NOT stamp a terminal status).
        logger.warn 'Favicon fetch timed out (retriable)',
          domain_id: @domain_id,
          domain: custom_domain&.display_domain,
          error: ex.message
        raise
      rescue StandardError => ex
        # Unexpected/terminal — record FAILED and re-raise so the worker DLQs.
        record_failure(custom_domain, ex) if custom_domain
        logger.error 'Favicon fetch failed',
          domain_id: @domain_id,
          domain: custom_domain&.display_domain,
          error: ex.message,
          error_class: ex.class.name
        raise
      end

      private

      # Injected model wins; otherwise load by identifier (nil when absent).
      def resolve_domain
        @custom_domain || Onetime::CustomDomain.load(@domain_id)
      end

      # Reads the icon hashkey fresh and decides whether a fetch is permitted.
      # Returns a Result to short-circuit, or nil to proceed.
      def overwrite_guard(custom_domain)
        existing_filename = custom_domain.icon['filename'].to_s
        existing_source   = custom_domain.icon['favicon_source'].to_s

        return nil if existing_filename.empty? # no icon at all → fetch

        if existing_source != 'auto_fetch'
          # A user upload (tagged 'user_upload') OR a legacy untagged upload —
          # never clobbered by a fetch, even with force.
          logger.info 'Favicon fetch skipped: user-managed icon present',
            domain_id: @domain_id,
            favicon_source: existing_source
          return skipped_result(custom_domain)
        end

        unless @force
          # Already auto-fetched; default skip policy leaves it in place.
          logger.info 'Favicon fetch skipped: auto-fetched icon already present',
            domain_id: @domain_id
          return skipped_result(custom_domain)
        end

        nil # force → re-fetch over the existing auto_fetch icon
      end

      # Discovery + fetch. Returns a SafeFetch::Result or nil (no usable icon).
      # FetchTimeout propagates (retriable); terminal SafeFetch errors are treated
      # as "this candidate didn't yield an icon" and discovery continues.
      def discover_and_fetch(display_domain)
        direct = try_fetch("https://#{display_domain}/favicon.ico")
        return direct if direct

        discover_link_candidates(display_domain).each do |candidate_url|
          image = try_fetch(candidate_url)
          return image if image
        end

        nil
      end

      # Fetch one image candidate. Terminal SafeFetch errors (bad target,
      # disallowed type, too large, too many redirects, 404/500 base Error) mean
      # "no icon here" and return nil; FetchTimeout is re-raised as retriable.
      def try_fetch(url)
        fetcher.get_image(url)
      rescue Onetime::Http::SafeFetch::FetchTimeout
        raise
      rescue Onetime::Http::SafeFetch::Error => ex
        logger.debug 'Favicon candidate not usable',
          domain_id: @domain_id,
          url: url,
          error: ex.message,
          error_class: ex.class.name
        nil
      end

      # Fetch the domain root HTML and extract <link rel~=icon> hrefs, absolutized
      # to https and de-duplicated. FetchTimeout propagates; other SafeFetch
      # errors yield no candidates.
      def discover_link_candidates(display_domain)
        base = "https://#{display_domain}/"
        html = fetcher.get_html(base)
        parse_icon_links(html, base).take(MAX_CANDIDATES)
      rescue Onetime::Http::SafeFetch::FetchTimeout
        raise
      rescue Onetime::Http::SafeFetch::Error => ex
        logger.debug 'Favicon HTML discovery failed',
          domain_id: @domain_id,
          domain: display_domain,
          error: ex.message
        []
      end

      # Parse icon <link> hrefs from HTML. Matches any rel token containing
      # 'icon' (icon, shortcut icon, apple-touch-icon, mask-icon, ...). SVG hrefs
      # are dropped early (SafeFetch also rejects SVG). Returns absolute https URLs.
      def parse_icon_links(html, base)
        doc = Nokogiri::HTML(html.to_s)
        doc.css('link[rel]').filter_map do |node|
          rel = node['rel'].to_s.downcase
          next unless rel.split(/\s+/).any? { |token| token.include?('icon') }

          href = node['href'].to_s.strip
          next if href.empty?
          next if href.downcase.split(/[?#]/).first.to_s.end_with?('.svg')

          absolutize_https(base, href)
        end.uniq
      end

      # Resolve a possibly-relative href against the domain root. Protocol-relative
      # (//host/path) and relative hrefs inherit the https base scheme. Non-https
      # absolute hrefs are dropped (SafeFetch would reject them anyway).
      def absolutize_https(base, href)
        resolved = URI.join(base, href)
        resolved.scheme == 'https' ? resolved.to_s : nil
      rescue URI::InvalidURIError
        nil
      end

      # Writes the icon hashkey in the SAME shape UpdateDomainImage produces, plus
      # favicon_source='auto_fetch'; drops the derived encoded_favicon cache so
      # GetFavicon regenerates (PNG) or passes through (ICO) on the next request.
      def write_icon(custom_domain, image)
        dimensions = measure_image(image)

        custom_domain.icon.update(
          'encoded' => Base64.strict_encode64(image.body),
          'filename' => favicon_filename(image.content_type),
          'content_type' => image.content_type,
          'height' => dimensions[:height],
          'width' => dimensions[:width],
          'ratio' => dimensions[:ratio],
          'bytes' => image.body.bytesize,
          'favicon_source' => 'auto_fetch',
        )
        custom_domain.icon.remove_field('encoded_favicon')
      end

      # Dimensions for the stored metadata. PNG uses FastImage; ICO passthrough
      # uses FastImage when it reports a size, else a nominal 32x32.
      def measure_image(image)
        size  = FastImage.size(StringIO.new(image.body))
        if size.nil? || size.any? { |dim| dim.nil? || dim.to_i <= 0 }
          width, height = ICO_NOMINAL_SIZE
        else
          width, height = size
        end
        ratio = height.to_i.zero? ? 1.0 : (width.to_f / height)
        { width: width, height: height, ratio: ratio }
      end

      def favicon_filename(content_type)
        content_type == 'image/png' ? 'favicon.png' : 'favicon.ico'
      end

      def mark_processing(custom_domain)
        # Stamp a start time so the nightly backfill can tell a genuinely
        # in-flight run (fresh) from an abandoned one (a DLQ'd FetchTimeout leaves
        # status=PROCESSING with no terminal stamp). Without this the freshness
        # window has nothing to measure against and every PROCESSING domain looks
        # stale, so in-flight jobs get re-enqueued as duplicates (#3780).
        custom_domain.favicon_fetch_status     = JobLifecycle::PROCESSING
        custom_domain.favicon_fetch_started_at = Familia.now.to_i
        custom_domain.save_fields(:favicon_fetch_status, :favicon_fetch_started_at)
      end

      def record_success(custom_domain)
        # Success clears the backoff so a later re-probe (e.g. force) starts fresh.
        custom_domain.favicon_fetch_status       = JobLifecycle::COMPLETED
        custom_domain.favicon_fetched            = true
        custom_domain.favicon_fetch_error        = nil
        custom_domain.favicon_fetch_completed_at = Familia.now.to_i
        custom_domain.favicon_fetch_attempts     = 0
        custom_domain.favicon_fetch_next_at      = nil
        custom_domain.save_fields(
          :favicon_fetch_status,
          :favicon_fetched,
          :favicon_fetch_error,
          :favicon_fetch_completed_at,
          :favicon_fetch_attempts,
          :favicon_fetch_next_at,
        )
      end

      def record_none_found(custom_domain)
        # None-found is a terminal non-success: advance the backoff so the nightly
        # scan re-probes later (a site may add a favicon), stopping at the cap.
        attempts                                 = custom_domain.favicon_fetch_attempts.to_i + 1
        custom_domain.favicon_fetch_status       = JobLifecycle::COMPLETED
        custom_domain.favicon_fetched            = false
        custom_domain.favicon_fetch_error        = nil
        custom_domain.favicon_fetch_completed_at = Familia.now.to_i
        custom_domain.favicon_fetch_attempts     = attempts
        schedule_next_favicon_fetch(custom_domain, attempts)
        custom_domain.save_fields(
          :favicon_fetch_status,
          :favicon_fetched,
          :favicon_fetch_error,
          :favicon_fetch_completed_at,
          :favicon_fetch_attempts,
          :favicon_fetch_next_at,
        )
      end

      def record_failure(custom_domain, ex)
        attempts                                 = custom_domain.favicon_fetch_attempts.to_i + 1
        custom_domain.favicon_fetch_status       = JobLifecycle::FAILED
        custom_domain.favicon_fetch_error        = ex.message
        custom_domain.favicon_fetch_completed_at = Familia.now.to_i
        custom_domain.favicon_fetch_attempts     = attempts
        schedule_next_favicon_fetch(custom_domain, attempts)
        custom_domain.save_fields(
          :favicon_fetch_status,
          :favicon_fetch_error,
          :favicon_fetch_completed_at,
          :favicon_fetch_attempts,
          :favicon_fetch_next_at,
        )
      rescue StandardError => ex
        # Never let a status-write failure mask the original error.
        logger.error 'Failed to persist favicon FAILED status',
          domain_id: @domain_id,
          error: ex.message
      end

      # Set favicon_fetch_next_at to the backoff time for this attempt, UNLESS the
      # attempt cap is reached — at the cap we leave next_at untouched (permanent
      # stop; the nightly scan gates on attempts, so the stale value is inert and
      # only a manual force re-probes past here).
      def schedule_next_favicon_fetch(custom_domain, attempts)
        return if attempts >= favicon_backfill_max_attempts

        custom_domain.favicon_fetch_next_at = compute_next_favicon_fetch_at(attempts)
      end

      # Backoff curve (#3780): base_days doubled per attempt, capped at cap_days,
      # measured forward from now. Config lives in jobs.favicon_backfill, which is
      # absent from the in-code DEFAULTS hash, so every read digs with a fallback.
      def compute_next_favicon_fetch_at(attempts)
        base_days = OT.conf.dig('jobs', 'favicon_backfill', 'base_days') || 1
        cap_days  = OT.conf.dig('jobs', 'favicon_backfill', 'cap_days') || 30
        Familia.now.to_i + ([base_days * (2**(attempts - 1)), cap_days].min * 86_400)
      end

      def favicon_backfill_max_attempts
        OT.conf.dig('jobs', 'favicon_backfill', 'max_attempts') || 6
      end

      def fetcher
        @fetcher ||= Onetime::Http::SafeFetch.new(
          timeout: OT.conf.dig('jobs', 'favicon_fetch', 'timeout') || DEFAULT_TIMEOUT,
          max_bytes: OT.conf.dig('jobs', 'favicon_fetch', 'max_response_bytes') || DEFAULT_MAX_BYTES,
          max_redirects: OT.conf.dig('jobs', 'favicon_fetch', 'max_redirects') || DEFAULT_MAX_REDIRECTS,
          allowed_content_types: OT.conf.dig('jobs', 'favicon_fetch', 'allowed_content_types') || DEFAULT_CONTENT_TYPES,
        )
      end

      def success_result(image)
        Result.new(
          domain_id: @domain_id,
          status: JobLifecycle::COMPLETED,
          favicon_fetched: true,
          favicon_source: 'auto_fetch',
          content_type: image.content_type,
          final_url: image.final_url,
          skipped: false,
          not_found: false,
          error: nil,
        )
      end

      def none_found_result
        Result.new(
          domain_id: @domain_id,
          status: JobLifecycle::COMPLETED,
          favicon_fetched: false,
          favicon_source: nil,
          content_type: nil,
          final_url: nil,
          skipped: false,
          not_found: false,
          error: nil,
        )
      end

      # Guard skip: no write, no persisted status change; outcome unchanged.
      # Report the ACTUAL persisted status (whatever a prior run left, or nil for
      # an untouched domain) rather than a fabricated COMPLETED — the guard wrote
      # nothing, so claiming COMPLETED would mislead the worker log and metrics.
      def skipped_result(custom_domain)
        Result.new(
          domain_id: @domain_id,
          status: custom_domain.favicon_fetch_status,
          favicon_fetched: custom_domain.favicon_fetched,
          favicon_source: custom_domain.icon['favicon_source'],
          content_type: nil,
          final_url: nil,
          skipped: true,
          not_found: false,
          error: nil,
        )
      end

      # Permanent miss: the domain was deleted between enqueue and processing.
      # Signalled by not_found:true (the worker acks, does NOT DLQ). error stays
      # nil so the "returned ⇒ success?" invariant holds — a missing domain is a
      # handled outcome, not a failure to retry.
      def not_found_result
        Result.new(
          domain_id: @domain_id,
          status: nil,
          favicon_fetched: nil,
          favicon_source: nil,
          content_type: nil,
          final_url: nil,
          skipped: false,
          not_found: true,
          error: nil,
        )
      end

      def logger
        @logger ||= Onetime.get_logger('Operations')
      end
    end
  end
end
