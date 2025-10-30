# lib/onetime/middleware/domain_strategy.rb

require 'public_suffix'
require_relative '../logging'

module Onetime
  module Middleware
    # DomainStrategy Middleware
    #
    # Classifies incoming request domains and determines the appropriate routing strategy.
    #
    # @example Domain Classification
    #   example.com        #=> :canonical (configured primary domain)
    #   www.example.com    #=> :canonical (www variant of primary)
    #   api.example.com    #=> :subdomain (subdomain of primary)
    #   partner.com        #=> :custom (partner domain from database)
    #   invalid.tld        #=> :invalid (malformed or unrecognized)
    #
    # @note This middleware adds the following to the Rack environment:
    #   - env['onetime.display_domain']  : Normalized domain for display
    #   - env['onetime.domain_strategy'] : Classification symbol
    #
    # @note Errors are logged but do not halt request processing.
    class DomainStrategy
      include Onetime::Logging

      @canonical_domain        = nil
      @domains_enabled         = nil
      @canonical_domain_parsed = nil

      unless defined?(MAX_SUBDOMAIN_DEPTH)
        MAX_SUBDOMAIN_DEPTH = 10 # e.g., a.b.c.d.e.f.g.h.i.j.example.com
        MAX_TOTAL_LENGTH    = 253   # RFC 1034 section 3.1
      end

      # Initializes the DomainStrategy middleware.
      #
      # @param app [Object] The Rack application.
      # @param application_context [Hash] Optional context about the application
      def initialize(app, application_context: nil)
        @app                 = app
        @application_context = application_context
        site_config          = OT.conf&.dig('site') || {}
        self.class.initialize_from_config(site_config)
        boot_logger.info 'DomainStrategy initialized',
          app_context: @application_context,
          canonical_domain: canonical_domain
      end

      # Processes the incoming request and classifies the domain.
      #
      # @param env [Hash] The Rack environment hash
      # @return [Array] Standard Rack response array [status, headers, body]
      def call(env)
        display_domain  = canonical_domain
        domain_strategy = :canonical

        if domains_enabled?
          display_domain  = env[Rack::DetectHost.result_field_name]
          # OT.ld "[middleware] DomainStrategy: detected_host=#{display_domain.inspect} result_field_name=#{Rack::DetectHost.result_field_name}"
          domain_strategy = Chooserator.choose_strategy(display_domain, canonical_domain_parsed)
        end

        env['onetime.display_domain']  = display_domain
        env['onetime.domain_strategy'] = domain_strategy || :invalid # make sure never nil

        app_logger.debug 'Domain strategy determined',
          host: display_domain,
          strategy: domain_strategy

        @app.call(env)
      end

      def canonical_domain
        self.class.canonical_domain # string or nil if not configured
      end

      def domains_enabled?
        self.class.domains_enabled # boolean
      end

      def canonical_domain_parsed
        self.class.canonical_domain_parsed
      end

      module Chooserator
        class << self
          # Determines the domain strategy for a request domain.
          #
          # @param request_domain [String] The domain from the current request
          # @param canonical_domain [PublicSuffix::Domain, String] The configured primary domain
          # @return [Symbol, nil] Domain strategy (:canonical, :subdomain, :custom) or nil if invalid
          def choose_strategy(request_domain, canonical_domain)
            canonical_domain = Parser.parse(canonical_domain) unless canonical_domain.is_a?(PublicSuffix::Domain)
            request_domain   = Parser.parse(request_domain)

            case request_domain
            when ->(d) { canonical?(d, canonical_domain) }    then :canonical
            when ->(d) { subdomain_of?(d, canonical_domain) } then :subdomain
            when ->(d) { known_custom_domain?(d.name) }       then :custom
            end
          rescue PublicSuffix::DomainInvalid => ex
            Onetime.app_logger.debug 'Invalid domain in strategy selection',
              exception: ex,
              request_domain: request_domain
            nil
          rescue StandardError => ex
            Onetime.app_logger.error 'Unhandled error in domain strategy',
              exception: ex,
              request_domain: request_domain,
              canonical_domain: canonical_domain
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
      module Parser
        class << self
          # Parses and validates a host string into a domain object.
          #
          # @param host [String] The host to parse (port will be stripped)
          # @return [PublicSuffix::Domain] Parsed domain object
          # @raise [PublicSuffix::DomainInvalid] When domain is invalid or malformed
          def parse(host)
            host = host.to_s.split(':').first # remove port (e.g. localhost:3000)
            raise PublicSuffix::DomainInvalid.new('Cannot parse host') unless basically_valid?(host)

            PublicSuffix.parse(host, default_rule: nil, ignore_private: false) # calls normalize
          end

          # Performs basic validation checks before parsing.
          #
          # @param input [String] The input string to validate
          # @return [Boolean] true if input passes basic validation
          def basically_valid?(input)
            return false if input.to_s.empty?
            return false if input.length > MAX_TOTAL_LENGTH

            # Only alphanumeric, dots, and hyphens are valid in domain names
            return false unless input.to_s.match?(/\A[a-zA-Z0-9.-]+\z/)

            segments = input.to_s.split('.').reject(&:empty?)
            return false if segments.length > MAX_SUBDOMAIN_DEPTH

            true
          end
        end
      end

      module ClassMethods
        attr_reader :canonical_domain, :domains_enabled, :canonical_domain_parsed

        alias domains_enabled? domains_enabled

        # Sets class instance variables based on the site configuration.
        def initialize_from_config(config)
          raise ArgumentError, 'Configuration cannot be nil' if config.nil?

          Onetime.app_logger.debug 'DomainStrategy initializing from config',
            domains_enabled_before: @domains_enabled

          @domains_enabled  = config.dig('domains', 'enabled') || false
          @canonical_domain = get_canonical_domain(config)

          Onetime.app_logger.debug 'DomainStrategy config loaded',
            domains_enabled: @domains_enabled,
            canonical_domain: @canonical_domain

          # We don't need to get into any domain parsing if domains are disabled
          return unless domains_enabled?

          @canonical_domain_parsed = Parser.parse(canonical_domain)
        rescue PublicSuffix::DomainInvalid => ex
          OT.le "[middleware] DomainStrategy: Invalid canonical domain: #{@canonical_domain.inspect} error=#{ex.message}"
          @domains_enabled = false
        end

        # The canonical domain is the configured default domain or the site host.
        # @return [String, nil] The canonical domain or nil
        def get_canonical_domain(config)
          default_domain = @domains_enabled ? config.dig('domains', 'default') : nil
          site_host      = config.fetch('host', nil)
          default_domain || site_host
        end

        def reset!
          @canonical_domain        = nil
          @domains_enabled         = nil
          @canonical_domain_parsed = nil
        end
      end

      extend ClassMethods
    end
  end
end
