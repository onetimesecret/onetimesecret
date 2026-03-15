# lib/middleware/locale_fallback.rb
#
# frozen_string_literal: true

module Middleware
  # LocaleFallback middleware
  #
  # Applies application-level fallback chains after Otto::Locale::Middleware
  # has done its initial locale detection. Otto handles the standard priority
  # chain (URL param -> session -> Accept-Language -> default), but it does
  # not consult the application's configured fallback chains.
  #
  # This middleware re-examines the Accept-Language header and checks the
  # fallback_locale config (from OT.conf['internationalization']['fallback_locale'])
  # to find a better locale match when the user's preferred regional variant
  # is not directly available.
  #
  # Example: Accept-Language "fr-CA" with available locales [fr_FR, en]
  #   Otto resolves: "fr" (primary code, mapped to fr_FR)
  #   Fallback chain for fr-CA: [fr_CA, fr_FR, en]
  #   Result: "fr_FR" (first available entry in the chain)
  #
  # Middleware order:
  #   1. Otto::Locale::Middleware sets env['otto.locale']
  #   2. This middleware may override env['otto.locale'] via fallback chains
  #   3. Middleware::I18nLocale reads env['otto.locale'] for I18n.with_locale
  #
  class LocaleFallback
    def initialize(app, fallback_chains: {}, available_locales: {}, default_locale: 'en')
      @app = app
      @available_locales = available_locales
      @default_locale = default_locale

      # Build a normalized lookup table from the fallback config.
      # Config keys use BCP 47 hyphens (fr-CA) and POSIX underscores (fr_CA)
      # interchangeably. We index by both forms so lookups always succeed.
      @chains = build_chain_lookup(fallback_chains)
    end

    def call(env)
      # Only intervene when Otto resolved to the default locale or a
      # primary-code fallback — the user may deserve a better regional match.
      # Skip when a URL param or session explicitly set the locale (those are
      # intentional user choices that Otto already respected).
      unless explicit_locale?(env)
        improved = resolve_from_header(env['HTTP_ACCEPT_LANGUAGE'])
        env['otto.locale'] = improved if improved
      end

      @app.call(env)
    end

    private

    # Check whether the locale was set by an explicit user action
    # (URL parameter or session) rather than Accept-Language detection.
    def explicit_locale?(env)
      # URL param takes highest priority in Otto
      req_params = Rack::Utils.parse_query(env['QUERY_STRING'] || '')
      return true if req_params['locale'] && !req_params['locale'].empty?

      # Session preference is also an explicit choice
      session = env['rack.session']
      return true if session && session['locale'] && !session['locale'].empty?

      false
    end

    # Parse Accept-Language and resolve through fallback chains.
    #
    # @param header [String, nil] Accept-Language header value
    # @return [String, nil] Resolved locale or nil if no improvement found
    def resolve_from_header(header)
      return nil unless header

      # Parse language tags with q-values, sorted by preference
      tags = parse_language_tags(header)

      tags.each do |lang_tag|
        result = resolve_tag(lang_tag)
        return result if result
      end

      nil
    rescue StandardError
      nil
    end

    # Parse Accept-Language header into sorted language tags.
    #
    # @param header [String] Raw Accept-Language value
    # @return [Array<String>] Language tags sorted by q-value (descending)
    def parse_language_tags(header)
      header.split(',').map { |entry|
        parts = entry.strip.split(/\s*;\s*q\s*=\s*/)
        tag = parts[0]&.strip
        q = parts[1] ? parts[1].to_f : 1.0
        [tag, q]
      }.sort_by { |_, q| -q }.map(&:first).compact
    end

    # Try to resolve a single Accept-Language tag through fallback chains.
    #
    # @param lang_tag [String] BCP 47 language tag (e.g. "fr-CA", "de", "pt-BR")
    # @return [String, nil] Available locale from the chain, or nil
    def resolve_tag(lang_tag)
      # Normalize: BCP 47 uses hyphens, our keys use both forms
      normalized = lang_tag.strip.downcase

      # Try the full tag first (e.g. "fr-ca"), then the underscore form ("fr_ca")
      chain = @chains[normalized] ||
              @chains[normalized.tr('-', '_')]

      if chain
        # Walk the chain, return first available locale
        chain.each do |candidate|
          return candidate if @available_locales.key?(candidate)
        end
      end

      # No chain found for this tag — try the primary code as a chain key
      primary = normalized.split(/[-_]/).first
      if primary != normalized
        chain = @chains[primary]
        if chain
          chain.each do |candidate|
            return candidate if @available_locales.key?(candidate)
          end
        end
      end

      nil
    end

    # Build a normalized chain lookup from the config hash.
    #
    # The config has keys like "fr-CA", "pt-BR", "de-AT", "default"
    # with values like ["fr_CA", "fr_FR", "en"].
    #
    # We store chains keyed by both hyphen and underscore lowercase forms
    # so that lookups from either format succeed.
    #
    # @param raw_chains [Hash] The fallback_locale config hash
    # @return [Hash<String, Array<String>>] Normalized lookup table
    def build_chain_lookup(raw_chains)
      return {} unless raw_chains.is_a?(Hash)

      lookup = {}

      raw_chains.each do |key, chain|
        next unless chain.is_a?(Array)
        next if key.to_s == 'default'

        key_str = key.to_s
        values = chain.map(&:to_s)

        # Store under the original key (lowercased)
        lower = key_str.downcase
        lookup[lower] = values

        # Also store under the alternate separator form
        alt = lower.include?('-') ? lower.tr('-', '_') : lower.tr('_', '-')
        lookup[alt] = values unless alt == lower
      end

      # Store the default chain under a known key
      if raw_chains.key?('default')
        lookup['default'] = raw_chains['default'].map(&:to_s)
      end

      lookup
    end
  end
end
