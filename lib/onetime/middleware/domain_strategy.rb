# lib/onetime/middleware/domain_strategy.rb
#
# frozen_string_literal: true

require 'public_suffix'
require_relative '../logger_methods'

module Onetime
  module Middleware
    # DomainStrategy Middleware
    #
    # Classifies incoming request domains and determines the appropriate routing strategy.
    #
    # Instantiated once per Rack application in the modular monolith. Multiple instances
    # share class-level configuration while maintaining isolated request processing.
    #
    # @example Domain Classification
    #   example.com        #=> :canonical (configured primary domain)
    #   www.example.com    #=> :canonical (www variant of primary)
    #   api.example.com    #=> :subdomain (subdomain of primary)
    #   partner.com        #=> :custom (partner domain from database)
    #   invalid.tld        #=> :invalid (malformed or unrecognized)
    #
    # @note Adds to Rack environment:
    #   - env['onetime.display_domain']  : Normalized domain for display
    #   - env['onetime.domain_strategy'] : Classification symbol (:canonical, :subdomain, :custom, :invalid)
    class DomainStrategy
      include Onetime::LoggerMethods

      @canonical_domain         = nil
      @domains_enabled          = nil
      @canonical_domains        = nil
      @canonical_domains_parsed = nil

      # Domain Context Override state (set at boot from config/env)
      @domain_context_enabled  = nil
      @domain_context_override = nil

      unless defined?(MAX_SUBDOMAIN_DEPTH)
        MAX_SUBDOMAIN_DEPTH = 10 # e.g., a.b.c.d.e.f.g.h.i.j.example.com
        MAX_TOTAL_LENGTH    = 253 # RFC 1034 section 3.1

        # Domain Context Override constants
        DOMAIN_CONTEXT_HEADER  = 'HTTP_O_DOMAIN_CONTEXT'
        DOMAIN_CONTEXT_ENV_VAR = 'DOMAIN_CONTEXT'
      end

      # Initializes the DomainStrategy middleware instance.
      #
      # Each Rack application in the monolith gets its own DomainStrategy instance.
      # Multiple instances share CLASS-LEVEL state for efficiency (see ClassMethods below).
      #
      # ## Instance vs. Class State
      #
      # Instance-level state (per app):
      #   - @app: The next Rack application in the middleware chain
      #   - @application_context: Metadata about which app this middleware serves
      #
      # Class-level state (shared by all instances):
      #   - @canonical_domain: The primary display host (default || site.host)
      #   - @domains_enabled: Whether custom domain feature is active
      #   - @canonical_domains / @canonical_domains_parsed: Full canonical set
      #     (site.host AND features.domains.default) used for classification
      #
      # The initialize call to `initialize_from_config()` is idempotent across instances.
      # Subsequent calls overwrite class variables, but this is safe because configuration
      # is static at boot time and identical for all instances.
      #
      # @param app [Object] The Rack application to wrap
      # @param application_context [Hash] Optional context about the application
      #   (e.g., { name: 'Core::Application', prefix: '/' })
      def initialize(app, application_context: nil)
        @app                 = app
        @application_context = application_context

        domains_config      = OT.conf&.dig('features', 'domains') || {}
        self.class.initialize_from_config(domains_config)

        boot_logger.debug 'DomainStrategy initialized',
          {
            app_context: @application_context,
            canonical_domain: canonical_domain,
          }
      end

      # Processes the incoming request and classifies the domain.
      #
      # This method is called for EVERY REQUEST routed to this middleware instance.
      # In a modular monolith with multiple apps, different instances handle different
      # URL prefixes, but all share the same domain classification logic via class state.
      #
      # ## Request Flow
      #
      # 1. Reads detected host from env (set by Rack::DetectHost middleware)
      # 2. Uses class-level state (@canonical_domain) to classify the domain
      # 3. Stores classification results in env (request-specific)
      # 4. Passes env to next middleware via @app.call(env)
      #
      # ## Rack Environment Variables
      #
      # - env['onetime.display_domain']: Normalized domain for rendering/logging
      # - env['onetime.domain_strategy']: Classification (:canonical, :subdomain, :custom, :invalid)
      #
      # @param env [Hash] The Rack environment hash
      # @return [Array] Standard Rack response array [status, headers, body]
      def call(env)
        display_domain  = canonical_domain
        domain_strategy = :canonical

        if domains_enabled?
          # Check for domain context override first (development feature)
          override_domain, override_source = detect_domain_override(env)
          if override_domain
            display_domain  = override_domain
            domain_strategy = :custom

            http_logger.info '[DomainStrategy] override active',
              {
                domain: override_domain,
                source: override_source,
                strategy: domain_strategy,
              }
          else
            display_domain  = env[Rack::DetectHost.result_field_name]
            # OT.ld "[middleware] DomainStrategy: detected_host=#{display_domain.inspect} result_field_name=#{Rack::DetectHost.result_field_name}"
            domain_strategy = Chooserator.choose_strategy(display_domain, canonical_domains_parsed)
          end
        end

        resolved_domain_strategy = domain_strategy || :invalid # make sure never nil

        # Sanitize display_domain for use in response headers (defense in depth).
        # Both code paths (DetectHost result and override header) should produce
        # valid hostnames, but we guard here to prevent header injection.
        unless Onetime::Utils::DomainParser.basically_valid?(display_domain)
          display_domain = canonical_domain
        end

        env['onetime.display_domain']  = display_domain
        env['onetime.domain_strategy'] = resolved_domain_strategy

        http_logger.debug '[DomainStrategy] determined',
          {
            host: display_domain,
            strategy: resolved_domain_strategy,
          }

        status, headers, body        = @app.call(env)
        headers['O-Domain-Strategy'] = resolved_domain_strategy.to_s
        headers['O-Display-Domain']  = display_domain.to_s
        [status, headers, body]
      end

      # Detects domain context override from environment or request header.
      #
      # Override priority (first match wins):
      # 1. DOMAIN_CONTEXT env var (set at process startup)
      # 2. O-Domain-Context request header (per-request override)
      #
      # @param env [Hash] The Rack environment hash
      # @return [Array<String, Symbol>, Array<nil, nil>] [domain, source] or [nil, nil]
      def detect_domain_override(env)
        detected_host = env[Rack::DetectHost.result_field_name]

        http_logger.debug '[DomainStrategy] detect_domain_override check',
          {
            domain_context_enabled: domain_context_enabled?,
            detected_host: detected_host,
            env_var: ENV.fetch(DOMAIN_CONTEXT_ENV_VAR, nil),
            header: env[DOMAIN_CONTEXT_HEADER],
          }

        return unless domain_context_enabled?

        # Check env var first (process-level override)
        env_override = ENV.fetch(DOMAIN_CONTEXT_ENV_VAR, nil)
        return [env_override, :env_var] unless env_override.to_s.empty?

        # Check request header (per-request override)
        header_override = env[DOMAIN_CONTEXT_HEADER]
        return [header_override, :header] unless header_override.to_s.empty?

        # Implicit override: browser navigated to a host outside the canonical
        # set. A request to site.host is NOT an implicit override even when
        # features.domains.default names a different host.
        return [detected_host, :detected_host] if detected_host && !canonical_host?(detected_host)

        [nil, nil]
      end

      # True when host matches one of the configured canonical hosts
      # (features.domains.default or site.host), normalized comparison.
      def canonical_host?(host)
        self.class.canonical_host?(host)
      end

      def domain_context_enabled?
        self.class.domain_context_enabled
      end

      def canonical_domain
        self.class.canonical_domain # string or nil if not configured
      end

      def domains_enabled?
        Onetime::Runtime.features.domains?
      end

      # Full canonical set for classification. Empty when domains are
      # disabled or the configured hosts could not be parsed.
      def canonical_domains_parsed
        self.class.canonical_domains_parsed || []
      end

      module Chooserator
        class << self
          # Determines the domain strategy for a request domain.
          #
          # Accepts one or more canonical hosts. In a split deployment,
          # site.host and features.domains.default are BOTH canonical anchors:
          # an exact match against ANY host is :canonical.
          #
          # Precedence (#3841): an exact canonical-set match always wins,
          # then a REGISTERED custom domain, then the subdomain/peer sweeps
          # across the set. The registration lookup must run before the
          # sweeps: a registered custom domain under a canonical host's base
          # domain (e.g. secrets.acme.io when site.host=acme.io) must keep
          # :custom — per-domain brand/signin config is gated on that
          # classification — while an exact canonical match still beats a
          # (misconfigured) identical registration.
          #
          # @param request_domain [String] The domain from the current request
          # @param canonical_domains [PublicSuffix::Domain, String, Array] The
          #   configured canonical host(s)
          # @return [Symbol, nil] Domain strategy (:canonical, :subdomain, :custom) or nil if invalid
          def choose_strategy(request_domain, canonical_domains)
            canonical_domains = [canonical_domains] unless canonical_domains.is_a?(Array)
            canonical_domains = canonical_domains.compact
            # Guard against empty canonical set (can happen if class init ran before Runtime.features was set)
            return nil if canonical_domains.empty?
            return nil if request_domain.nil? || request_domain.to_s.strip.empty?

            # Parse per-element, skipping unparseable hosts (e.g. an IP
            # literal site.host in dev) so one bad entry cannot poison the
            # whole set — mirrors ClassMethods#parse_canonical_set.
            canonical_domains = canonical_domains.filter_map do |host|
              host.is_a?(PublicSuffix::Domain) ? host : Parser.parse(host)
            rescue PublicSuffix::DomainInvalid => ex
              Onetime.http_logger.debug 'Skipping unparseable canonical host in strategy selection',
                {
                  host: host,
                  error: ex.message,
                }
              nil
            end
            return nil if canonical_domains.empty?

            request_domain = Parser.parse(request_domain)

            if canonical_domains.any? { |host| equal_to?(request_domain, host) }
              :canonical
            elsif known_custom_domain?(request_domain.name)
              :custom
            elsif canonical_domains.any? { |host| canonical?(request_domain, host) } # rubocop:disable Lint/DuplicateBranch
              :canonical
            elsif canonical_domains.any? { |host| subdomain_of?(request_domain, host) }
              :subdomain
            end
          rescue PublicSuffix::DomainInvalid => ex
            Onetime.http_logger.debug 'Invalid domain in strategy selection',
              {
                exception: ex,
                request_domain: request_domain,
              }
            nil
          rescue StandardError => ex
            Onetime.http_logger.error 'Unhandled error in domain strategy',
              {
                exception: ex,
                request_domain: request_domain,
                canonical_domains: canonical_domains,
              }
            nil
          end

          # Checks if domain matches canonical domain or its standard variants.
          #
          # @param d [PublicSuffix::Domain] Domain to check
          # @param canonical_domain [PublicSuffix::Domain] Canonical domain
          # @return [Boolean] true if domain is canonical or a canonical variant
          def canonical?(d, canonical_domain)
            (
              equal_to?(d, canonical_domain) ||
              peer_of?(d, canonical_domain) ||
              parent_of?(d, canonical_domain)
            )
          end

          def equal_to?(left, right)
            return false unless left.domain? && right.domain?

            left.name.eql?(right.name) || (left.domain.eql?(right.domain) && left.trd.eql?('www'))
          end
          # equal_to?('Example.com', 'example.com') # => true
          # equal_to?('sub.EXAMPLE.COM', 'sub.example.com') # => true
          # equal_to?('example.com', 'different.com') # => false
          # equal_to?('', 'example.com') # => false
          # equal_to?(nil, 'example.com') # => false

          def peer_of?(left, right)
            return false unless left.subdomain? && right.subdomain?

            # NOTE: We do not re-check if the domains are the same
            left.domain.eql?(right.domain)
          end
          # peer_of?('blog.example.com', 'shop.example.com') # => true
          # peer_of?('sub.blog.example.com', 'sub.shop.example.com') # => true
          # peer_of?('blog.example.com', 'example.com') # => false
          # peer_of?('blog.example.com', 'blog.other.com') # => false
          # peer_of?('example.com', 'example.com') # => false

          def parent_of?(left, right)
            return false unless !left.subdomain? && right.subdomain?

            left.name.eql?(right.domain)
          end
          # subdomain_of?('sub.example.com', 'example.com') # => true
          # subdomain_of?('other.com', 'example.com') # => false
          # subdomain_of?('deep.sub.example.com', 'example.com') # => true
          # subdomain_of?('eu.onetimesecret.com', 'onetimesecret.com') # => false
          # subdomain_of?('.onetimesecret.com', 'eu.onetimesecret.com') # => false

          def subdomain_of?(left, right)
            return false unless left.subdomain? && !right.subdomain?

            left.domain.eql?(right.name)
          end
          # subdomain_of?('sub.example.com', 'example.com') # => true
          # subdomain_of?('other.com', 'example.com') # => false
          # subdomain_of?('deep.sub.example.com', 'example.com') # => true
          # subdomain_of?('example.com', 'example.com') # => false

          # Checks if domain is registered as a custom domain in the database.
          #
          # @param potential_custom_domain [String] Domain to check
          # @return [Boolean] true if domain exists in CustomDomain table
          def known_custom_domain?(potential_custom_domain)
            # This will load the model if it hasn't been loaded yet
            # and avoid circular references between lib and v2.
            !Onetime::CustomDomain.from_display_domain(potential_custom_domain).nil?
          end
        end
      end

      # Domain parsing utilities with validation.
      #
      # Delegates to Onetime::Utils::DomainParser for hostname extraction and
      # validation to maintain a single source of truth for domain parsing logic.
      module Parser
        class << self
          # Parses and validates a host string into a domain object.
          #
          # @param host [String] The host to parse (port will be stripped)
          # @return [PublicSuffix::Domain] Parsed domain object
          # @raise [PublicSuffix::DomainInvalid] When domain is invalid or malformed
          def parse(host)
            # Delegate hostname extraction (port stripping, normalization) to DomainParser
            host = Onetime::Utils::DomainParser.extract_hostname(host)
            raise PublicSuffix::DomainInvalid.new('Cannot parse host') unless basically_valid?(host)

            PublicSuffix.parse(host, default_rule: nil, ignore_private: false) # calls normalize
          end

          # Performs basic validation checks before parsing.
          #
          # @param input [String] The input string to validate
          # @return [Boolean] true if input passes basic validation
          #
          # Delegates to Onetime::Utils::DomainParser.basically_valid? for
          # consistent validation logic across the codebase.
          def basically_valid?(input)
            Onetime::Utils::DomainParser.basically_valid?(input)
          end
        end
      end

      # Shared Configuration State
      #
      # This module extends the DomainStrategy class to provide shared configuration
      # across all middleware instances.
      #
      # ## Why Class-Level State?
      #
      # DomainStrategy instances are created multiple times (once per Rack app), but
      # the configuration (canonical domain, feature flags) is the same for all instances.
      # Class variables avoid redundant parsing and initialization.
      #
      #
      # @note If dynamic reconfiguration is needed, consider using a thread-safe
      #   configuration store (e.g., monitor pattern) instead of class variables.
      module ClassMethods
        attr_reader :canonical_domain,
          :domains_enabled,
          :canonical_domains,
          :canonical_domains_parsed,
          :domain_context_enabled

        alias domains_enabled? domains_enabled
        alias domain_context_enabled? domain_context_enabled

        # Sets class instance variables based on the site configuration.
        def initialize_from_config(domains_config)
          raise ArgumentError, 'Configuration cannot be nil' if domains_config.nil?

          Onetime.http_logger.debug 'DomainStrategy initializing from config',
            {
              domains_enabled_before: domains_enabled,
            }

          @domains_enabled = domains_config.fetch('enabled', false)

          default_host = domains_enabled ? domains_config['default'] : nil
          site_host    = OT.conf.dig('site', 'host') || nil

          # Canonical SET, derived through Utils::CanonicalHosts (the single
          # derivation point shared with CustomDomain). Primary host first:
          # features.domains.default when the feature is enabled, else
          # site.host. In a split deployment (site.host serves the app,
          # default anchors generated links) a request to either host must
          # classify :canonical, never :invalid.
          @canonical_domains        = Onetime::Utils::CanonicalHosts.hosts(
            default_host: default_host, site_host: site_host,
          )
          @canonical_domain         = @canonical_domains.first
          @canonical_domains_parsed = []

          # Load domain context override setting from development config
          dev_config              = OT.conf&.dig('development') || {}
          @domain_context_enabled = dev_config['domain_context_enabled'] == true

          Onetime.http_logger.debug 'DomainStrategy config loaded',
            {
              domains_enabled: domains_enabled,
              canonical_domain: canonical_domain,
              canonical_domains: canonical_domains,
              domain_context_enabled: domain_context_enabled,
            }

          # We don't need to get into any domain parsing if domains are disabled
          return unless domains_enabled?

          # The primary host must parse: failure lands in the DomainInvalid
          # rescue below, which disables the domains feature.
          Parser.parse(canonical_domain)
          @canonical_domains_parsed = parse_canonical_set(canonical_domains)
        rescue PublicSuffix::DomainInvalid => ex
          OT.le "[middleware] DomainStrategy: Invalid canonical domain: #{canonical_domain.inspect} error=#{ex.message}"
          @domains_enabled = false
        end

        # Set-backed membership test for the canonical host set, normalized
        # on both sides (case, port). Public API for callers outside the
        # middleware (auth hooks, logic classes) so they agree with request
        # classification about which hosts are canonical.
        #
        # @param host [String, nil] Host to test (port/case-insensitive)
        # @return [Boolean] true when host is one of the canonical hosts
        def canonical_host?(host)
          normalized = Onetime::Utils::DomainParser.extract_hostname(host)
          return false if normalized.nil?

          hosts = canonical_domains
          hosts = [canonical_domain].compact if hosts.nil? || hosts.empty?
          hosts.any? { |candidate| Onetime::Utils::DomainParser.extract_hostname(candidate) == normalized }
        end

        # Parses each canonical host, skipping unparseable entries (e.g. an IP
        # literal site.host in dev). The primary host is parsed separately and
        # still disables domains on failure.
        def parse_canonical_set(hosts)
          hosts.filter_map do |host|
            Parser.parse(host)
          rescue PublicSuffix::DomainInvalid => ex
            Onetime.http_logger.debug 'DomainStrategy skipping unparseable canonical host',
              {
                host: host,
                error: ex.message,
              }
            nil
          end
        end

        def reset!
          @canonical_domain         = nil
          @domains_enabled          = nil
          @canonical_domains        = nil
          @canonical_domains_parsed = nil
          @domain_context_enabled   = nil
        end
      end

      extend ClassMethods
    end
  end
end
