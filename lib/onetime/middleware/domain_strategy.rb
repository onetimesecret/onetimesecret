# lib/onetime/middleware/domain_strategy.rb

require 'simpleidn'

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

    class << self
      attr_accessor :canonical_domain
      attr_accessor :domains_enabled
    end

    # Domain constants to live by
    unless defined?(MAX_DOMAIN_LENGTH)
      MAX_DOMAIN_LENGTH = 253
      MAX_LABEL_LENGTH = 63
    end

    # Initializes the DomainStrategy middleware.
    #
    # @param app [Object] The Rack application.
    def initialize(app)
      @app = app
      config = OT.conf.fetch(:site, {})
      self.class.canonical_domain = Chooserator.determine_canonical_domain(config)
      self.class.domains_enabled = config.dig(:domains, :enabled) || false
      OT.info "[DomainStrategy]: canonical_domain=#{canonical_domain} enabled=#{domains_enabled}"
    end

    # @return [String, nil] The canonical domain or nil if not configured.
    def canonical_domain
      self.class.canonical_domain
    end

    # @return [Boolean] True if domains are enabled, false otherwise.
    def domains_enabled?
      self.class.domains_enabled
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
        domain_strategy = Chooserator.choose_strategy(display_domain)
      end

      env['onetime.display_domain'] = display_domain
      env['onetime.domain_strategy'] = domain_strategy

      OT.ld "[DomainStrategy]: host=#{display_domain.inspect} strategy=#{domain_strategy}"

      @app.call(env)
    end

    # Methods for choosing a strategy based on the request domain
    module Chooserator
      module ClassMethods
        def choose_strategy(host)
          normalized = Normalizer.normalize(host)
          case normalized
          when ->(h) { invalid_format?(h) }                then :invalid
          when ->(h) { equal_to?(h, canonical_domain) }    then :canonical
          when ->(h) { peer_of?(h, canonical_domain) }     then :canonical
          when ->(h) { subdomain_of?(h, canonical_domain)} then :subdomain
          else :custom
          end
        end

        def subdomain_of?(potential_sub, potential_parent)
          return false if potential_sub.nil? || potential_parent.nil?

          sub = potential_sub.split('.').reverse
          parent = potential_parent.split('.').reverse

          return false if parent.length > sub.length

          parent.each_with_index.all? do |part, i|
            sub[i] == part
          end
        end
        # subdomain_of?('sub.example.com', 'example.com')     # => true
        # subdomain_of?('other.com', 'example.com')           # => false
        # subdomain_of?('deep.sub.example.com', 'example.com') # => true
        # subdomain_of?('example.com', 'example.com')         # => true

        def peer_of?(left, right)
          return false if left.nil? || right.nil?

          lparts = left.split('.')
          rparts = right.split('.')

          # Different lengths can't be peers
          return false if lparts.length != rparts.length

          # Same domain isn't a peer
          return false if left == right

          # Compare all parts except the first
          lparts[1..-1] == rparts[1..-1]
        end
        # peer_domain?('blog.example.com', 'shop.example.com') # => true
        # peer_domain?('sub.blog.example.com', 'sub.shop.example.com') # => true
        # peer_domain?('blog.example.com', 'example.com') # => false
        # peer_domain?('blog.example.com', 'blog.other.com') # => false
        # peer_domain?('example.com', 'example.com') # => false

        def equal_to?(left, right)
          return false if left.nil? || right.nil?

          left.eql?(right)
        end
        # domain_eql?('Example.com', 'example.com')     # => true
        # domain_eql?('EXAMPLE.COM', 'example.com')     # => true
        # domain_eql?('example.com', 'different.com')   # => false
        # domain_eql?('', nil)                          # => false


        def valid?(host)
          OT::CustomDomain.valid?(host)
        end

        # Normalizes the canonical domain from the configuration.
        #
        # @return [String, nil] The normalized canonical domain or nil if not configured.
        def determine_canonical_domain(config)
          site_host = config.fetch(:host, nil)
          return site_host unless domains_enabled?

          default_domain = config.dig(:domains, :default)

          Normalizer.normalize(default_domain || site_host)
        end
      end

      extend ClassMethods
    end

    # Methods for normalizing domain names.
    module Normalizer
      class ClassMethods
        # Normalizes the given host.
        #
        # @param host [String] The host to normalize.
        # @return [String, nil] The normalized host or nil if invalid.
        def normalize(host)
          return if host.to_s.empty?

          normalized = host.strip
                           .downcase
                           .split(':').first # remove port (e.g. localhost:3000)

          begin
            SimpleIDN.to_ascii(normalized)
          rescue SimpleIDN::ConversionError => e
            OT.ld "[DomainStrategy::Normalizer] Invalid domain: #{normalized} (#{e.message})"
          end
        end
      end

      extend ClassMethods
    end
  end
end
