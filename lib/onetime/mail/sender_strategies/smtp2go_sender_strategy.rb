# lib/onetime/mail/sender_strategies/smtp2go_sender_strategy.rb
#
# frozen_string_literal: true

require_relative 'base_sender_strategy'
require_relative '../smtp2go_client'

module Onetime
  module Mail
    module SenderStrategies
      # Smtp2goSenderStrategy - SMTP2GO sender domain provisioning and provider checks.
      #
      # This class handles PROVISIONING (add domain, get DNS records) and
      # PROVIDER-LEVEL verification (ask SMTP2GO API if domain is verified).
      #
      # For DNS-LEVEL verification (lookup DNS records, compare expected vs actual),
      # see DomainValidation::SenderStrategies::Smtp2goValidation instead.
      #
      # Used by:
      #   - ProvisionSenderDomain operation (provisioning)
      #   - DomainValidationWorker (provider check only, via check_provider_verification_status)
      #   - DnsRecordCheckWorker (fact-finding, via inherited check_dns_records)
      #
      # Provisions sender authentication through SMTP2GO's Sender Domain API.
      #
      # SMTP2GO authenticates via three CNAME records: one for DKIM
      # alignment, one for SPF/Return-Path alignment (the envelope sender
      # subdomain, SMTP2GO's equivalent of SES's custom MAIL FROM), and one
      # for tracking (opens, clicks, unsubscribes). The tracking CNAME
      # affects link rewriting only — not sender authentication — so it is
      # advisory ('optional' => true) and never gates verification.
      #
      # Example DNS records for domain "example.com":
      #   s123456._domainkey.example.com CNAME dkim.smtp2go.net
      #   bounce.example.com             CNAME return.smtp2go.net
      #   track.example.com              CNAME track.smtp2go.net
      #
      # Domains are keyed by NAME (not an opaque ID), so identity_id is the
      # domain name itself. The relevant endpoints (all POST, JSON):
      #   - POST /domain/add     Add domain, returns DKIM/RPath/tracker data
      #   - POST /domain/view    List domains (filterable by domain name)
      #   - POST /domain/verify  Trigger immediate re-verification (SMTP2GO
      #                          otherwise polls DNS every ~7 minutes)
      #   - POST /domain/remove  Remove a sender domain
      #
      # Configuration (credentials hash, string keys):
      #   api_key:              SMTP2GO API key (format: api-<32 chars>)
      #   base_url:             Custom API base URL (optional)
      #   returnpath_subdomain: Return-path subdomain (default 'bounce')
      #   tracking_subdomain:   Tracking subdomain (default 'track')
      #   timeout:              Read timeout in seconds (optional)
      #
      class Smtp2goSenderStrategy < BaseSenderStrategy
        # Default API base URL. Can be overridden via credentials['base_url']
        # or SMTP2GO_BASE_URL env var (loaded via ProviderConfig).
        DEFAULT_BASE_URL = Smtp2goClient::DEFAULT_BASE_URL

        # Default subdomains for the return-path and tracking CNAME records
        # when the credentials hash carries none (contract with
        # CUSTOM_MAIL_SMTP2GO_RETURNPATH_SUBDOMAIN / _TRACKING_SUBDOMAIN).
        DEFAULT_RETURNPATH_SUBDOMAIN = 'bounce'
        DEFAULT_TRACKING_SUBDOMAIN   = 'track'

        # Provisions sender DNS records through SMTP2GO's Sender Domain API.
        #
        # Adds the domain and returns the three CNAME records that must be
        # configured for DKIM, SPF/Return-Path, and tracking. Idempotent:
        # when the domain already exists at SMTP2GO, the existing entry is
        # fetched from /domain/view instead.
        #
        # @param mailer_config [CustomDomain::MailerConfig] Mailer configuration
        # @param credentials [Hash] Must include 'api_key'; optionally 'base_url',
        #   'returnpath_subdomain', 'tracking_subdomain', 'timeout'
        # @return [Hash] Provisioning result:
        #   - :success [Boolean]
        #   - :message [String]
        #   - :dns_records [Array<Hash>] Formatted DNS records
        #   - :identity_id [String] The domain name (SMTP2GO keys domains by name)
        #   - :provider_data [Hash] SMTP2GO-specific data (selectors, verified flags)
        #   - :error [String, nil] Error message if failed
        #
        def provision_dns_records(mailer_config, credentials:)
          domain = extract_domain(mailer_config.from_address)

          unless domain
            return {
              success: false,
              message: 'Invalid from_address: cannot extract domain',
              dns_records: [],
              error: 'invalid_from_address',
            }
          end

          api_key = credentials['api_key']
          unless api_key && !api_key.empty?
            return {
              success: false,
              message: 'SMTP2GO API key is required for domain provisioning',
              dns_records: [],
              error: 'missing_api_key',
            }
          end

          log_info "[smtp2go-sender] Provisioning sender domain for #{domain}"

          client = build_client(credentials)
          entry  = create_or_get_domain(client, domain, credentials)

          unless entry
            return {
              success: false,
              message: "SMTP2GO returned no domain entry for #{domain}",
              dns_records: [],
              error: 'missing_domain_entry',
            }
          end

          dns_records = build_dns_records(entry)

          if dns_records.empty?
            log_warn '[smtp2go-sender] Domain entry returned but no DNS records normalized. ' \
                     "Entry keys: #{entry.keys.inspect}"
            return {
              success: false,
              message: "SMTP2GO returned a domain entry for #{domain} but no DNS records could be " \
                       "normalized (entry keys: #{entry.keys.inspect})",
              dns_records: [],
              error: 'no_dns_records',
            }
          end

          {
            success: true,
            message: "Domain #{domain} provisioned with SMTP2GO",
            dns_records: dns_records,
            identity_id: entry_domain_name(entry) || domain,
            provider_data: provider_data_for(entry),
          }
        rescue Smtp2goClient::APIError => ex
          log_error "[smtp2go-sender] Provisioning failed for #{domain}: HTTP #{ex.status_code} - #{ex.message}"
          {
            success: false,
            message: "SMTP2GO API error: #{ex.message}",
            dns_records: [],
            error: "http_#{ex.status_code}: #{ex.error_code || ex.message}",
          }
        rescue StandardError => ex
          log_error "[smtp2go-sender] Provisioning failed: #{ex.message}"
          {
            success: false,
            message: "Provisioning failed: #{ex.message}",
            dns_records: [],
            error: ex.message,
          }
        end

        # Checks verification status of a sender domain.
        #
        # Triggers an immediate re-verification via /domain/verify (SMTP2GO
        # otherwise re-checks DNS every ~7 minutes), then reads the current
        # state from /domain/view. SMTP2GO exposes no domain-level verified
        # boolean; the domain is verified when dkim_verified and
        # rpath_verified are both true. Tracker CNAMEs affect link
        # rewriting, not sender authentication, so their state is surfaced
        # in details but never gates verification.
        #
        # @param mailer_config [CustomDomain::MailerConfig] Mailer configuration
        # @param credentials [Hash] Must include 'api_key'
        # @return [Hash] Verification status:
        #   - :verified [Boolean]
        #   - :status [String] 'verified', 'pending', 'not_found', 'error'
        #   - :message [String]
        #   - :details [Hash, nil] Additional verification details
        #
        def check_provider_verification_status(mailer_config, credentials:)
          domain = extract_domain(mailer_config.from_address)

          unless domain
            return {
              verified: false,
              status: 'invalid',
              message: 'Invalid from_address: cannot extract domain',
            }
          end

          api_key = credentials['api_key']
          unless api_key && !api_key.empty?
            return {
              verified: false,
              status: 'error',
              message: 'SMTP2GO API key is required',
            }
          end

          log_info "[smtp2go-sender] Checking verification status for #{domain}"

          client = build_client(credentials)

          # Trigger SMTP2GO to re-check DNS records before reading status.
          # Without this, SMTP2GO's ~7-minute polling cadence means the
          # cached status may not reflect recent DNS changes.
          begin
            client.post('/domain/verify', { 'domain' => domain })
            log_info "[smtp2go-sender] Triggered provider verification for #{domain}"
          rescue StandardError => ex
            # Non-fatal: continue and read whatever status SMTP2GO has
            log_warn "[smtp2go-sender] Provider trigger failed for #{domain}: #{ex.message}"
          end

          entry = find_domain(client, domain)

          unless entry
            return {
              verified: false,
              status: 'not_found',
              message: "Domain #{domain} not found in SMTP2GO",
            }
          end

          domain_obj    = domain_object(entry)
          dkim_ok       = truthy?(domain_obj['dkim_verified'])
          rpath_ok      = truthy?(domain_obj['rpath_verified'])
          trackers      = Array(entry['trackers']).grep(Hash)
          tracking_ok   = trackers.empty? || trackers.all? { |t| truthy?(t['cname_verified']) }
          verified      = dkim_ok && rpath_ok

          {
            verified: verified,
            status: verified ? 'verified' : 'pending',
            message: verification_message(domain, verified, dkim: dkim_ok, rpath: rpath_ok),
            details: {
              dns_records: build_dns_records(entry),
              domain: entry_domain_name(entry) || domain,
              dkim_verified: dkim_ok,
              rpath_verified: rpath_ok,
              tracking_verified: tracking_ok,
            },
          }
        rescue Smtp2goClient::APIError => ex
          log_error "[smtp2go-sender] Verification check failed for #{domain}: HTTP #{ex.status_code} - #{ex.message}"
          {
            verified: false,
            status: 'error',
            message: "Verification check failed: #{ex.message}",
          }
        rescue StandardError => ex
          log_error "[smtp2go-sender] Verification check failed: #{ex.message}"
          {
            verified: false,
            status: 'error',
            message: "Verification check failed: #{ex.message}",
          }
        end

        # Deletes a sender domain from SMTP2GO.
        #
        # @param mailer_config [CustomDomain::MailerConfig] Mailer configuration
        # @param credentials [Hash] Must include 'api_key'
        # @return [Hash] Deletion result:
        #   - :deleted [Boolean]
        #   - :message [String]
        #
        def delete_sender_identity(mailer_config, credentials:)
          domain = extract_domain(mailer_config.from_address)

          unless domain
            return {
              deleted: false,
              message: 'Invalid from_address: cannot extract domain',
            }
          end

          api_key = credentials['api_key']
          unless api_key && !api_key.empty?
            return {
              deleted: false,
              message: 'SMTP2GO API key is required',
            }
          end

          log_info "[smtp2go-sender] Deleting sender domain for #{domain}"

          client = build_client(credentials)

          # Domains are keyed by name; check existence first so a domain
          # that was already removed reads as a successful deletion.
          entry = find_domain(client, domain)

          unless entry
            return {
              deleted: true,
              message: "Domain #{domain} was already deleted or never existed",
            }
          end

          client.post('/domain/remove', { 'domain' => domain })

          {
            deleted: true,
            message: "Domain #{domain} removed from SMTP2GO",
          }
        rescue Smtp2goClient::APIError => ex
          if not_found_error?(ex)
            # Domain doesn't exist - treat as successful deletion
            {
              deleted: true,
              message: "Domain #{domain} was already deleted or never existed",
            }
          else
            log_error "[smtp2go-sender] Deletion failed for #{domain}: HTTP #{ex.status_code} - #{ex.message}"
            {
              deleted: false,
              message: "Deletion failed: #{ex.message}",
            }
          end
        rescue StandardError => ex
          log_error "[smtp2go-sender] Deletion failed: #{ex.message}"
          {
            deleted: false,
            message: "Deletion failed: #{ex.message}",
          }
        end

        protected

        def validate_config!
          # Validation happens at call time with provided credentials
        end

        private

        # Build API client from credentials.
        #
        # @param credentials [Hash] Must include 'api_key'; optionally
        #   'base_url' and 'timeout'
        # @return [Smtp2goClient] Shared HTTP client instance
        #
        def build_client(credentials)
          Smtp2goClient.new(
            api_key: credentials['api_key'],
            base_url: credentials['base_url'] || DEFAULT_BASE_URL,
            read_timeout: credentials['timeout'] || 30,
          )
        end

        # Adds the domain, falling back to the existing entry on failure.
        #
        # SMTP2GO does not document a dedicated "domain already exists"
        # error_code, so this is made idempotent by probing /domain/view
        # when the add error plausibly means the domain already exists
        # (see #plausibly_exists_error?): if the domain exists there,
        # provisioning already succeeded at some point and the existing
        # entry is authoritative; otherwise the original add error is
        # re-raised. Auth, quota/payment, and server errors re-raise
        # immediately — they never mean "already exists", and probing on
        # them risks masking the real failure.
        #
        # @param client [Smtp2goClient] API client instance
        # @param domain [String] Domain name (e.g., "example.com")
        # @param credentials [Hash] Credentials with optional subdomain overrides
        # @return [Hash, nil] Domain entry ({'domain' => {...}, 'trackers' => [...]})
        #
        def create_or_get_domain(client, domain, credentials)
          data = client.post(
            '/domain/add',
            {
              'domain' => domain,
              'tracking_subdomain' => subdomain_or_default(credentials['tracking_subdomain'], DEFAULT_TRACKING_SUBDOMAIN),
              'returnpath_subdomain' => subdomain_or_default(credentials['returnpath_subdomain'], DEFAULT_RETURNPATH_SUBDOMAIN),
            },
          )
          extract_domain_entry(data, domain)
        rescue Smtp2goClient::APIError => ex
          raise ex unless plausibly_exists_error?(ex)

          existing = begin
            find_domain(client, domain)
          rescue StandardError
            nil
          end
          raise ex unless existing

          log_info "[smtp2go-sender] Domain #{domain} already exists, using existing entry " \
                   "(add returned HTTP #{ex.status_code}: #{ex.message})"
          existing
        end

        # Whether a /domain/add failure plausibly means the domain already
        # exists at SMTP2GO (gating the recovery probe above). Kept for
        # HTTP 409 and 400 plus exist/already/duplicate wording; auth
        # (401/403), quota/payment (402), and 5xx never qualify.
        #
        # @param error [Smtp2goClient::APIError]
        # @return [Boolean]
        #
        def plausibly_exists_error?(error)
          status = error.status_code.to_i
          return false if [401, 402, 403].include?(status) || status >= 500
          return true if [400, 409].include?(status)

          "#{error.error_code} #{error.message}".match?(/exist|already|duplicate/i)
        end

        # Returns the configured subdomain only when it is a plausible DNS
        # label; blank values (e.g. a set-but-empty
        # CUSTOM_MAIL_SMTP2GO_RETURNPATH_SUBDOMAIN) are treated as absent
        # and malformed values are logged and replaced, so a bad credential
        # never reaches /domain/add verbatim.
        #
        # @param value [String, nil] Configured subdomain from credentials
        # @param default [String] Fallback ('bounce'/'track')
        # @return [String]
        #
        def subdomain_or_default(value, default)
          candidate = value.to_s.strip
          return default if candidate.empty?
          return candidate if candidate.match?(/\A[a-z0-9-]+\z/i)

          log_warn "[smtp2go-sender] Ignoring invalid subdomain #{candidate.inspect}, using #{default.inspect}"
          default
        end

        # Find a domain entry by name via /domain/view.
        #
        # The view endpoint accepts a domain filter, so the response should
        # contain zero or one entries; the name comparison is kept as a
        # belt-and-braces guard against filterless responses.
        #
        # @param client [Smtp2goClient] API client instance
        # @param domain [String] Domain name to find (e.g., "example.com")
        # @return [Hash, nil] Domain entry hash, or nil if not found
        #
        def find_domain(client, domain)
          data = client.post('/domain/view', { 'domain' => domain })
          extract_domain_entry(data, domain)
        rescue Smtp2goClient::APIError => ex
          return nil if not_found_error?(ex)

          raise
        end

        # Selects the matching domain entry from a response data hash.
        #
        # SMTP2GO responses carry `data.domains`, an array of entries shaped
        # as {'domain' => {...}, 'trackers' => [...]}. Matches strictly by
        # name (case-insensitively) — a response listing only OTHER domains
        # (e.g. a filterless list after a failed add) must never be
        # adopted, or another customer's DKIM records would be persisted
        # for this domain.
        #
        # @param data [Hash] Parsed `data` hash from the API response
        # @param domain [String] Domain name to match
        # @return [Hash, nil] Matching entry or nil
        #
        def extract_domain_entry(data, domain)
          entries = data.is_a?(Hash) ? Array(data['domains']) : []
          target  = domain.to_s.downcase

          entries.find { |e| e.is_a?(Hash) && entry_domain_name(e).to_s.downcase == target }
        end

        # Extracts the domain name from an entry, tolerating both the
        # documented nested shape ({'domain' => {'fulldomain' => ...}}) and
        # a flat string ({'domain' => 'example.com'}).
        #
        # @param entry [Hash] Domain entry from the API
        # @return [String, nil]
        #
        def entry_domain_name(entry)
          return nil unless entry.is_a?(Hash)

          dom = entry['domain']
          return dom if dom.is_a?(String)

          domain_object(entry)['fulldomain'] || domain_object(entry)['domain']
        end

        # Returns the nested domain object of an entry (empty hash when the
        # entry carries none, so callers can index safely).
        #
        # @param entry [Hash] Domain entry from the API
        # @return [Hash]
        #
        def domain_object(entry)
          dom = entry.is_a?(Hash) ? entry['domain'] : nil
          dom.is_a?(Hash) ? dom : {}
        end

        # Normalize an SMTP2GO domain entry to standard DNS record format.
        #
        # SMTP2GO returns selector/value pairs rather than ready-made
        # hostnames:
        #   { "domain": { "fulldomain": "example.com",
        #                 "dkim_selector": "s123456", "dkim_value": "dkim.smtp2go.net",
        #                 "dkim_verified": true,
        #                 "rpath_selector": "bounce", "rpath_value": "return.smtp2go.net",
        #                 "rpath_verified": false, ... },
        #     "trackers": [{ "fulldomain": "track.example.com",
        #                    "cname_value": "track.smtp2go.net",
        #                    "cname_verified": false, ... }] }
        #
        # Hostname construction: <dkim_selector>._domainkey.<fulldomain> for
        # DKIM, <rpath_selector>.<fulldomain> for the return-path, and the
        # tracker's own fulldomain for tracking.
        #
        # Normalized to consistent shape matching SES/SendGrid/Lettermint:
        #   [{ 'type' => 'CNAME', 'name' => ..., 'value' => ..., 'status' => ... }]
        # with 'status' mapped from the per-record verified booleans.
        # Tracker records additionally carry 'optional' => true (the same
        # advisory marker SES uses for its DMARC record): tracking affects
        # link rewriting, not sender authentication, so
        # BaseSenderStrategy#check_dns_records skips them and they never
        # gate verification.
        #
        # @param entry [Hash] Domain entry from the SMTP2GO API
        # @return [Array<Hash>] Normalized records with string keys
        #
        def build_dns_records(entry)
          return [] unless entry.is_a?(Hash)

          domain_obj = domain_object(entry)
          fulldomain = domain_obj['fulldomain'] || domain_obj['domain']
          records    = []

          dkim_selector = domain_obj['dkim_selector'].to_s
          dkim_value    = domain_obj['dkim_value'].to_s
          if !dkim_selector.empty? && !dkim_value.empty?
            host = dkim_selector.include?('_domainkey') ? dkim_selector : "#{dkim_selector}._domainkey"
            records << normalized_record(fqdn_for(host, fulldomain), dkim_value, domain_obj['dkim_verified'])
          end

          rpath_selector = domain_obj['rpath_selector'].to_s
          rpath_value    = domain_obj['rpath_value'].to_s
          if !rpath_selector.empty? && !rpath_value.empty?
            records << normalized_record(fqdn_for(rpath_selector, fulldomain), rpath_value, domain_obj['rpath_verified'])
          end

          Array(entry['trackers']).each do |tracker|
            next unless tracker.is_a?(Hash)

            name  = tracker['fulldomain'] || fqdn_for(tracker['subdomain'].to_s, fulldomain)
            value = tracker['cname_value'].to_s
            next if name.to_s.empty? || value.empty?

            records << normalized_record(name, value, tracker['cname_verified'], optional: true)
          end

          records
        end

        # Builds a single normalized CNAME record hash. Only includes
        # 'status' when the API exposed a verified boolean for the record,
        # and 'optional' only for advisory records.
        #
        # @param name [String] DNS hostname
        # @param value [String] CNAME target
        # @param verified [Boolean, nil] Per-record verified flag from the API
        # @param optional [Boolean] Whether the record is advisory only
        # @return [Hash] String-keyed record hash
        #
        def normalized_record(name, value, verified, optional: false)
          record             = {
            'type' => 'CNAME',
            'name' => name,
            'value' => value,
          }
          record['status']   = (truthy?(verified) ? 'verified' : 'pending') unless verified.nil?
          record['optional'] = true if optional
          record
        end

        # Joins a host part with the domain, tolerating parts that are
        # already fully qualified (defensive against API field drift).
        #
        # @param host [String] Host part (e.g. "s123456._domainkey", "bounce")
        # @param fulldomain [String, nil] The sender domain
        # @return [String] Fully qualified hostname
        #
        def fqdn_for(host, fulldomain)
          host       = host.to_s
          fulldomain = fulldomain.to_s
          return host if fulldomain.empty? || host == fulldomain || host.end_with?(".#{fulldomain}")

          "#{host}.#{fulldomain}"
        end

        # Raw provider status fields worth persisting alongside the records.
        #
        # @param entry [Hash] Domain entry from the SMTP2GO API
        # @return [Hash] String-keyed provider metadata
        #
        def provider_data_for(entry)
          domain_obj = domain_object(entry)
          trackers   = Array(entry['trackers']).grep(Hash)

          {
            'domain' => entry_domain_name(entry),
            'dkim_selector' => domain_obj['dkim_selector'],
            'dkim_verified' => domain_obj['dkim_verified'],
            'rpath_selector' => domain_obj['rpath_selector'],
            'rpath_verified' => domain_obj['rpath_verified'],
            'trackers' => trackers.map do |t|
              {
                'fulldomain' => t['fulldomain'],
                'cname_verified' => t['cname_verified'],
                'enabled' => t['enabled'],
              }
            end,
          }.compact
        end

        # Interprets the API's verified flags, which arrive as JSON booleans
        # but are matched tolerantly against string encodings.
        #
        # @param value [Object] Raw flag value
        # @return [Boolean]
        #
        def truthy?(value)
          value == true || value.to_s == 'true'
        end

        # Detects not-found API errors for name-keyed domain operations.
        #
        # SMTP2GO does not document a dedicated not-found error_code for
        # /domain/remove or /domain/view, so this matches the generic 404
        # status plus plausible code spellings. The free-text fallback
        # requires domain/sender context so unrelated messages (e.g.
        # 'API key not found') never read as a missing domain.
        #
        # @param error [Smtp2goClient::APIError]
        # @return [Boolean]
        #
        def not_found_error?(error)
          return true if error.status_code.to_i == 404
          return true if error.error_code.to_s.match?(/NOT_?FOUND|NONEXISTENT/i)

          error.message.to_s.match?(
            /\b(?:domain|sender)\b.{0,40}\b(?:not found|does not exist|unknown)\b|\b(?:no such|unknown) (?:domain|sender)\b/i,
          )
        end

        # Maps verification state to human-readable message. Tracking is
        # deliberately absent from the pending list: it is advisory only
        # (see details[:tracking_verified] for its state).
        #
        # @param domain [String] Domain name
        # @param verified [Boolean] Overall verification state
        # @param dkim [Boolean] DKIM CNAME verified
        # @param rpath [Boolean] Return-path CNAME verified
        # @return [String]
        #
        def verification_message(domain, verified, dkim:, rpath:)
          return "Domain #{domain} is verified and ready for sending" if verified

          pending = []
          pending << 'DKIM' unless dkim
          pending << 'Return-Path' unless rpath

          if pending.empty?
            "Domain #{domain} pending verification"
          else
            "Domain #{domain} pending verification - awaiting CNAME record(s): #{pending.join(', ')}"
          end
        end
      end
    end
  end
end
