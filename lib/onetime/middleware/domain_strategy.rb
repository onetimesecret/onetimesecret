# lib/onetime/middleware/domain_strategy.rb

require 'public_suffix'

module Onetime
  # Middleware for handling and validating domain types in incoming requests.
  #
  # This class normalizes the incoming host, determines its state (canonical, subdomain,
  # custom, or invalid), and updates the Rack environment with the domain strategy.
  #
  #        :canonical    # Matches configured domain exactly
  #        :subdomain    # Valid subdomain of canonical domain
  #        :custom       # Different valid domain
  #        :invalid      # Invalid/malformed domain
  #
  class DomainStrategy
    @canonical_domain = nil
    @domains_enabled = nil
    @canonical_domain_parsed = nil

    # Initializes the DomainStrategy middleware.
    #
    # @param app [Object] The Rack application.
    def initialize(app)
      @app = app
      site_config = OT.conf.fetch(:site, {})
      self.class.parse_config(site_config)
      OT.info "[DomainStrategy]: canonical_domain=#{canonical_domain} enabled=#{domains_enabled?}"
    end

    # Processes the incoming request and updates the Rack environment with the domain strategy.
    #
    # @param env [Hash] The Rack environment.
    # @return [Array] The Rack response.
    def call(env)
      display_domain = canonical_domain
      domain_strategy = :canonical

      if domains_enabled?
        display_domain = env[Rack::DetectHost.result_field_name]
        domain_strategy = Chooserator.choose_strategy(display_domain, canonical_domain_parsed)
      end

      env['onetime.display_domain'] = display_domain
      env['onetime.domain_strategy'] = domain_strategy

      OT.ld "[DomainStrategy]: host=#{display_domain.inspect} strategy=#{domain_strategy}"

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
        def choose_strategy(input, canonical_domain)
          if canonical_domain.is_a?(PublicSuffix::Domain)
            canonical_domain_parsed = canonical_domain
          else
            canonical_domain_parsed = Parser.parse(canonical_domain)
          end

          normalized = Parser.normalize(input)
          domain = Parser.parse(normalized)
          case domain
          when ->(d) { invalid?(d) }                       then :invalid
          when ->(d) { equal_to?(d, canonical_domain_parsed) }    then :canonical
          when ->(d) { peer_of?(d, canonical_domain_parsed) }     then :canonical
          when ->(d) { subdomain_of?(d, canonical_domain_parsed)} then :subdomain
          else
            :custom
          end

        rescue PublicSuffix::DomainInvalid => e
          OT.ld "[DomainStrategy]: Invalid domain: #{input.inspect} error=#{e.message}"
          :invalid
        rescue => e
          OT.le "[DomainStrategy]: Unhandled error: #{e.message} (backtrace: " \
                "#{e.backtrace[0..2].join("\n")}) (args: #{input.inspect}, " \
                "#{canonical_domain_parsed.inspect})"
          :invalid
        end

        def invalid?(domain)
          raise ArgumentError, "Domain object required (not #{domain.inspect})" unless domain.is_a?(PublicSuffix::Domain)

          !Parser.valid?(domain)
        end

        def equal_to?(left, right)

          return false unless left.domain? && right.domain?
          left.name.eql?(right.name)
        end
        # equal_to?('Example.com', 'example.com') # => true
        # equal_to?('sub.EXAMPLE.COM', 'sub.example.com') # => true
        # equal_to?('example.com', 'different.com') # => false
        # equal_to?('', 'example.com') # => false
        # equal_to?(nil, 'example.com') # => false

        def peer_of?(left, right)
          return false unless left.subdomain? && right.subdomain?
          # NOTE: We do not re-check if the domains are the same
          equal_to?(left.domain, right.domain)
        end
        # peer_of?('blog.example.com', 'shop.example.com') # => true
        # peer_of?('sub.blog.example.com', 'sub.shop.example.com') # => true
        # peer_of?('blog.example.com', 'example.com') # => false
        # peer_of?('blog.example.com', 'blog.other.com') # => false
        # peer_of?('example.com', 'example.com') # => false

        def subdomain_of?(left, right)
          return false unless left.subdomain? && !right.subdomain?
          return false if left.subdomain.nil?
          equal_to?(left.domain, right.name)
        end
        # subdomain_of?('sub.example.com', 'example.com') # => true
        # subdomain_of?('other.com', 'example.com') # => false
        # subdomain_of?('deep.sub.example.com', 'example.com') # => true
        # subdomain_of?('example.com', 'example.com') # => false

      end
    end

    module Parser
      class << self
        # @raises [PublicSuffix::DomainInvalid]
        # @return [PublicSuffix::Domain]
        def parse(host)
          raise PublicSuffix::DomainInvalid.new("Host is nil") if host.nil?
          host = host.split(':').first # remove port (e.g. localhost:3000)
          PublicSuffix.parse(host, default_rule: nil, ignore_private: false)
        end

        # @raises [PublicSuffix::DomainInvalid]
        # @return [String] The normalized domain
        def normalize(input)
          raise PublicSuffix::DomainInvalid.new("Host is not valid") unless valid?(input)
          output = PublicSuffix.normalize(input)
          raise output if output.is_a?(PublicSuffix::DomainInvalid)
          output
        end

        def valid_format?(input)
          return false if input.nil?
          !input.include?('..') && !input.start_with?('.') && !input.end_with?('.')
        end

        def valid?(input)
          valid_format?(input) &&
            PublicSuffix.valid?(input, default_rule: nil, ignore_private: false)
        end

        def invalid?(input)
          !valid?(input)
        end
      end
    end

    module ClassMethods
      attr_reader :canonical_domain
      attr_reader :domains_enabled
      attr_reader :canonical_domain_parsed

      alias :domains_enabled? :domains_enabled

      # Sets class instance variables based on the site configuration.
      def parse_config(config)
        raise ArgumentError, "Configuration cannot be nil" if config.nil?

        @canonical_domain = get_canonical_domain(config)
        @domains_enabled = config.dig(:domains, :enabled) || false

        if domains_enabled? && canonical_domain.to_s.empty?
          OT.le "[DomainStrategy]: No canonical domain configured"
          @domains_enabled = false
          return
        end

        return unless domains_enabled?

        @canonical_domain_parsed = Parser.parse(canonical_domain)
      rescue PublicSuffix::DomainInvalid => e
        OT.le "[DomainStrategy]: Invalid canonical domain: #{canonical_domain.inspect} error=#{e.message}"
        @domains_enabled = false
      end

      # Normalizes the canonical domain from the configuration.
      #
      # @return [String, nil] The normalized canonical domain or nil if not configured.
      def get_canonical_domain(config)
        site_host = config.fetch(:host, nil)
        return site_host unless domains_enabled?
        default_domain = config.dig(:domains, :default)

        Parser.normalize(default_domain || site_host)
      end

      def reset!
        @canonical_domain = nil
        @domains_enabled = nil
        @canonical_domain_parsed = nil
      end
    end

    extend ClassMethods
  end
end
