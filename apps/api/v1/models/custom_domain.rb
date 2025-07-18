# apps/api/v1/models/custom_domain.rb

require 'public_suffix'

# Tryouts:
# - tests/unit/ruby/try/20_models/27_domains_try.rb
# - tests/unit/ruby/try/20_models/27_domains_publicsuffix_try.rb

# Custom Domain
#
# Every customer can have one or more custom domains.
#
# The list of custom domains that are associated to a customer is
# distinct from a customer's subdomain.
#
# CustomDomain records can only be created via the V2 model. This V1
# model is purely for maintaining the v1 API regardless of advancements.
#
module V1
  class CustomDomain < Familia::Horreum
    include Gibbler::Complex

    prefix :customdomain

    feature :safe_dump

    # CustomDomain records can only be created via V2 so we use the existing
    # domainid field as the identifier.
    identifier :domainid

    field :display_domain
    field :custid
    field :domainid
    field :base_domain
    field :subdomain
    field :trd
    field :tld
    field :sld
    field :txt_validation_host
    field :txt_validation_value
    field :status
    field :vhost
    field :verified # the txt record matches?
    field :resolving # there's a valid A or CNAME record?
    field :created
    field :updated
    field :_original_value

    hashkey :brand
    hashkey :logo # image fields need a corresponding v2 route and logic class
    hashkey :icon

    @safe_dump_fields = [
      { :identifier => ->(obj) { obj.domainid } },
      :domainid,
      :display_domain,
      :custid,
      :base_domain,
      :subdomain,
      :trd,
      :tld,
      :sld,
      { :is_apex => ->(obj) { obj.apex? } },
      :_original_value,
      :txt_validation_host,
      :txt_validation_value,
      { :brand => ->(obj) { obj.brand.hgetall } },
      # NOTE: We don't serialize images here
      :status,
      { :vhost => ->(obj) { obj.parse_vhost } },
      :verified,
      :created,
      :updated,
    ]

    def init
      # Display domain and cust should already be set and accessible
      # via accessor methods so we should see a valid identifier logged.
      OT.ld "[CustomDomain.init] #{display_domain} id:#{domainid}"

      # Will raise PublicSuffix::DomainInvalid if invalid domain
      ps_domain = PublicSuffix.parse(display_domain, default_rule: nil)

      # Store the individual domain parts that PublicSuffix parsed out
      @base_domain = ps_domain.domain.to_s
      @subdomain = ps_domain.subdomain.to_s
      @trd = ps_domain.trd.to_s
      @tld = ps_domain.tld.to_s
      @sld = ps_domain.sld.to_s

      # Don't call generate_txt_validation_record here otherwise we'll
      # create a new validation record every time we instantiate a
      # custom domain object. Instead, we'll call it when we're ready
      # to verify the domain.
    end

    def to_s
      # If we can treat familia objects as strings, then passing them as method
      # arguments we don't need to check whether it is_a? RedisObject or not;
      # we can simply call `fobj.to_s`. In both cases the result is the unqiue
      # ID of the familia object. Usually that is all we need to maintain the
      # relation records -- we don't actually need the instance of the familia
      # object itself.
      #
      # As a pilot to trial this out, Customer has the equivalent method and
      # comment. See the ClassMethods below for usage details.
      identifier.to_s
    end

    # Checks if the domain is an apex domain.
    # An apex domain is a domain without any subdomains.
    #
    # Note: A subdomain can include nested subdomains (e.g., b.a.example.com),
    # whereas TRD (Transit Routing Domain) refers to the part directly before
    # the SLD.
    #
    # @return [Boolean] true if the domain is an apex domain, false otherwise
    def apex?
      subdomain.empty?
    end

    # Overrides Familia::Horreum#exists? to handle connection pool issues
    #
    # The original implementation may return false for existing keys
    # when the connection is returned to the pool before checking.
    # This implementation uses a fresh connection for the check.
    #
    # @return [Boolean] true if the domain exists in Redis
    def exists?
      redis.exists?(rediskey)
    end

    # Returns the current verification state of the custom domain
    #
    # States:
    # - :unverified  Initial state, no verification attempted
    # - :pending     TXT record generated but DNS not resolving
    # - :resolving    TXT record and CNAME are resolving but not yet matching
    # - :verified    TXT and CNAME are resolving and TXT record matches
    #
    # @return [Symbol] The current verification state
    def verification_state
      return :unverified unless txt_validation_value
      if resolving.to_s == 'true'
        verified.to_s == 'true' ? :verified : :resolving
      else
        :pending
      end
    end

    # Checks if this domain is ready to serve traffic
    #
    # A domain is considered ready when:
    # 1. The ownership is verified via TXT record
    # 2. The domain is resolving to our servers
    #
    # @return [Boolean] true if domain is verified and resolving
    def ready?
      verification_state == :verified
    end

    module ClassMethods
      attr_reader :db, :values, :owners, :txt_validation_prefix

      # Takes the given input domain and returns the display domain,
      # the one that we ask the user to create an A record for. So
      # subdir.www.froogle.com would return subdir.www.froogle.com here;
      # www.froogle.com would return www.froogle.com; and froogle.com
      # would return froogle.com.
      #
      def display_domain input
        ps_domain = PublicSuffix.parse(input, default_rule: nil)
        ps_domain.subdomain || ps_domain.domain

      rescue PublicSuffix::Error => e
        OT.le "[CustomDomain.parse] #{e.message} for `#{input}`"
        raise OT::Problem, e.message
      end

      def default_domain? input
        display_domain = V1::CustomDomain.display_domain(input)
        site_host = OT.conf.dig('site', 'host')
        OT.ld "[CustomDomain.default_domain?] #{display_domain} == #{site_host}"
        display_domain.eql?(site_host)
      rescue PublicSuffix::Error => e
        OT.le "[CustomDomain.default_domain?] #{e.message} for `#{input}"
        false
      end

      # Simply instatiates a new CustomDomain object and checks if it exists.
      def exists? input, custid
        # The `parse`` method instantiates a new CustomDomain object but does
        # not save it to Redis. We do that here to piggyback on the inital
        # validation and parsing. We use the derived identifier to load
        # the object from Redis using
        obj = parse(input, custid)
        OT.ld "[CustomDomain.exists?] Got #{obj.identifier} #{obj.display_domain} #{obj.custid}"
        obj.exists?

      rescue OT::Problem => e
        OT.le "[CustomDomain.exists?] #{e.message}"
        false
      end

      def recent duration=48.hours
        spoint, epoint = OT.now.to_i-duration, OT.now.to_i
        self.values.rangebyscoreraw(spoint, epoint).collect { |identifier| load(identifier) }
      end

      # Implement a load method for CustomDomain to make sure the
      # correct derived ID is used as the key.
      def load display_domain, custid

        custom_domain = parse(display_domain, custid).tap do |obj|
          OT.ld "[CustomDomain.load] Got #{obj.identifier} #{obj.display_domain} #{obj.custid}"
          raise OT::RecordNotFound, "Domain not found #{obj.display_domain}" unless obj.exists?
        end

        # Continue with the built-in `load` from Familia.
        super(custom_domain.identifier)
      end

      # Load a custom domain by display domain only. Used during requests
      # after determining the domain strategy is :custom.
      #
      # @param display_domain [String] The display domain to load
      # @return [V1::CustomDomain, nil] The custom domain record or nil if not found
      def from_display_domain display_domain
        # Get the domain ID from the display_domains hash
        domain_id = self.display_domains.get(display_domain)
        return nil unless domain_id

        # Load the record using the domain ID
        begin
          from_identifier(domain_id)
        rescue OT::RecordNotFound
          nil
        end
      end
    end

    extend ClassMethods
  end
end
