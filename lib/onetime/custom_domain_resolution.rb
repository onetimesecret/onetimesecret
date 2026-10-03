# lib/onetime/custom_domain_resolution.rb
#
# frozen_string_literal: true

module Onetime
  # The outcome of looking up the CustomDomain for one host, shared by the
  # code that handles a single request (#4220).
  #
  # Three states, so a nil record is never ambiguous:
  #
  #   found       - the host names a CustomDomain; #record is that record
  #   absent      - the read succeeded and there is no record for the host
  #   read_failed - the read raised; #error is the exception
  #
  # DomainStrategy publishes the resolution it made while classifying the
  # host under ENV_KEY. Request-path code asks {.for} (or {.for_host} when it
  # reads a host other than env['onetime.display_domain']) instead of calling
  # CustomDomain.from_display_domain again, so every consumer in the request
  # sees the same record, the same absence, or the same failure.
  #
  # The middleware does not read for every request: an exact canonical-set
  # host classifies :canonical before any lookup, and with the domains
  # feature off nothing is classified at all. In those cases nothing is
  # published, and the first {.for} call performs the read and stores its
  # result in the env for the consumers that follow.
  #
  # What each consumer DOES with a state is its own decision and is not
  # defined here. #record! re-raises the original exception, so a consumer
  # that rescued Redis::BaseError around its own read keeps that rescue;
  # #record answers nil for both absent and read_failed, which is what the
  # consumers that read through CustomDomain.load_by_display_domain saw.
  #
  # Instances are frozen. Out of scope: ACME / on-demand TLS lookups, CLI and
  # background code, and any lookup of a host that is not the request's own.
  class CustomDomainResolution
    ENV_KEY = 'onetime.custom_domain_resolution'

    STATES = [:found, :absent, :read_failed].freeze

    class << self
      # @param host [String]
      # @param record [Onetime::CustomDomain]
      # @return [CustomDomainResolution]
      def found(host, record)
        new(state: :found, host: host, record: record)
      end

      # @param host [String]
      # @return [CustomDomainResolution]
      def absent(host)
        new(state: :absent, host: host)
      end

      # @param host [String]
      # @param error [StandardError] the exception the read raised
      # @return [CustomDomainResolution]
      def read_failed(host, error)
        new(state: :read_failed, host: host, error: error)
      end

      # Runs the block (the read) and records its outcome. The block returns
      # a CustomDomain or nil; a StandardError it raises is kept, not
      # re-raised.
      #
      # @param host [String] the host the block looks up
      # @yieldreturn [Onetime::CustomDomain, nil]
      # @return [CustomDomainResolution]
      def capture(host)
        record = yield
        record.nil? ? absent(host) : found(host, record)
      rescue StandardError => ex
        read_failed(host, ex)
      end

      # One read through CustomDomain.from_display_domain, the raising
      # loader. Nothing is published.
      #
      # @param host [String, nil]
      # @return [CustomDomainResolution]
      def lookup(host)
        capture(host.to_s) { Onetime::CustomDomain.from_display_domain(host) }
      end

      # The resolution for the request's display domain.
      #
      # Returns what DomainStrategy published when it is for
      # env['onetime.display_domain']. Otherwise performs the read once and
      # stores the result under ENV_KEY for the rest of the request.
      #
      # @param env [Hash, nil] Rack env
      # @return [CustomDomainResolution]
      def for(env)
        return lookup(nil) unless env.is_a?(Hash)

        host      = env['onetime.display_domain'].to_s
        published = env[ENV_KEY]
        return published if published.is_a?(self) && published.host == host

        resolution   = lookup(host)
        env[ENV_KEY] = resolution unless env.frozen?
        resolution
      end

      # The resolution for a host the caller derived itself (a raw Host
      # header, DetectHost's result). Uses the request's resolution when it
      # is for the same host, and otherwise reads without publishing, so a
      # different host can never replace the request's own resolution.
      #
      # @param env [Hash, nil] Rack env
      # @param host [String, nil]
      # @return [CustomDomainResolution]
      def for_host(env, host)
        return lookup(host) unless env.is_a?(Hash)

        wanted = normalize(host)
        return lookup(host) if wanted.nil?
        return self.for(env) if wanted == normalize(env['onetime.display_domain'])

        lookup(host)
      end

      private

      def normalize(host)
        value = host.to_s.strip.downcase
        value.empty? ? nil : value
      end
    end

    attr_reader :state, :host, :error

    # Reserved for a future authorization verdict on the resolved domain
    # (whether the host may be served as this tenant). Nothing sets or reads
    # it today; it is always nil.
    attr_reader :authorization

    # @return [Onetime::CustomDomain, nil] nil when absent or read_failed
    attr_reader :record

    def initialize(state:, host:, record: nil, error: nil)
      raise ArgumentError, "unknown state: #{state.inspect}" unless STATES.include?(state)

      @state         = state
      @host          = host.to_s.dup.freeze
      @record        = record
      @error         = error
      @authorization = nil
      freeze
    end

    def found?
      state == :found
    end

    def absent?
      state == :absent
    end

    def read_failed?
      state == :read_failed
    end

    # @return [String, nil] CustomDomain#identifier when found
    def identifier
      record&.identifier
    end

    # The record, raising what the read raised when it failed. For consumers
    # that handle the failure themselves.
    #
    # @return [Onetime::CustomDomain, nil] nil when absent
    # @raise [StandardError] the original exception when read_failed
    def record!
      raise error if read_failed?

      record
    end

    # The same resolution labelled with another spelling of the host.
    # DomainStrategy uses it to key the published value on
    # env['onetime.display_domain'] exactly.
    #
    # @param host [String]
    # @return [CustomDomainResolution]
    def with_host(host)
      self.class.new(state: state, host: host, record: record, error: error)
    end
  end
end
