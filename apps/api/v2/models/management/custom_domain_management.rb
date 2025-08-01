# apps/api/v2/models/management/custom_domain_management.rb

module V2
  class CustomDomain < Familia::Horreum

    module Management
      attr_reader :db, :values, :owners, :txt_validation_prefix

      # Creates a new custom domain record
      #
      # This method:
      # 1. Validates and parses the input domain
      # 2. Checks for duplicates
      # 3. Saves the domain and updates related records atomically
      #
      # @param input [String] The domain name to create
      # @param custid [String] The customer ID to associate with
      # @return [V2::CustomDomain] The created custom domain
      # @raise [Onetime::Problem] If domain is invalid or already exists
      #
      # More Info:
      # We need a minimum of a domain and customer id to create a custom
      # domain -- or more specifically, a custom domain indentifier. We
      # allow instantiating a custom domain without a customer id, but
      # instead raise a fuss if we try to save it later without one.
      #
      # See CustomDomain.base_domain and display_domain for details on
      # the difference between display domain and base domain.
      #
      # NOTE: Interally within this class, we try not to use the
      # unqualified term "domain" on its own since there's so much
      # room for confusion.
      #
      def create(input, custid)
        obj = parse(input, custid)

        redis.watch(obj.rediskey) do
          if obj.exists?
            redis.unwatch
            raise Onetime::Problem, "Duplicate domain for customer"
          end

          redis.multi do |multi|
            obj.generate_txt_validation_record
            obj.save
            # Create minimal customer instance for Redis key
            cust = V2::Customer.new(custid: custid)
            cust.add_custom_domain(obj)
            # Add to global values set
            self.add(obj)
          end
        end

        obj  # Return the created object
      rescue Redis::BaseError => e
        OT.le "[CustomDomain.create] Redis error: #{e.message}"
        raise Onetime::Problem, "Unable to create custom domain"
      end

      # Returns a new V2::CustomDomain object (without saving it).
      #
      # @param input [String] The domain name to parse
      # @param custid [String] Customer ID associated with the domain
      #
      # @return [V2::CustomDomain]
      #
      # @raise [PublicSuffix::DomainInvalid] If domain is invalid
      # @raise [PublicSuffix::DomainNotAllowed] If domain is not allowed
      # @raise [PublicSuffix::Error] For other PublicSuffix errors
      # @raise [Onetime::Problem] If domain exceeds MAX_SUBDOMAIN_DEPTH or MAX_TOTAL_LENGTH
      #
      def parse(input, custid)
        raise Onetime::Problem, "Customer ID required" if custid.to_s.empty?

        segments = input.to_s.split('.').reject(&:empty?)
        raise Onetime::Problem, "Invalid domain format" if segments.empty?

        if segments.length > MAX_SUBDOMAIN_DEPTH
          raise Onetime::Problem, "Domain too deep (max: #{MAX_SUBDOMAIN_DEPTH})"
        end

        if input.length > MAX_TOTAL_LENGTH
          raise Onetime::Problem, "Domain too long (max: #{MAX_TOTAL_LENGTH})"
        end

        display_domain = self.display_domain(input)
        obj = new(display_domain, custid)
        obj._original_value = input
        obj
      end

      # Takes the given input domain and returns the base domain,
      # the one that the zone record would be created for. So
      # froogle.com, www.froogle.com, subdir.www.froogle.com would
      # all return froogle.com here.
      #
      # Another way to think about it, the TXT record we ask the user
      # to create will be created on the base domain. So if we have
      # www.froogle.com, we'll create the TXT record on froogle.com,
      # like this: `_onetime-challenge-domainid.froogle.com`. This is
      # distinct from the domain we ask the user to create an A
      # record for, which is www.froogle.com. We also call this the
      # display domain.
      #
      # Returns either a string or nil if invalid
      def base_domain input
        # We don't need to fuss with empty stripping spaces, prefixes,
        # etc because PublicSuffix does that for us.
        PublicSuffix.domain(input, default_rule: nil)
      rescue PublicSuffix::DomainInvalid => e
        OT.le "[CustomDomain.base_domain] #{e.message} for `#{input}`"
        nil
      end

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
        raise Onetime::Problem, e.message
      end

      # Returns boolean, whether the domain is a valid public suffix
      # which checks without actually parsing it.
      def valid? input
        PublicSuffix.valid?(input, default_rule: nil)
      end

      def default_domain? input
        display_domain = V2::CustomDomain.display_domain(input)
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

      rescue Onetime::Problem => e
        OT.le "[CustomDomain.exists?] #{e.message}"
        false
      end

      def add fobj
        self.values.add OT.now.to_i, fobj.to_s # created time, identifier
        self.display_domains.put fobj.display_domain, fobj.identifier
        self.owners.put fobj.to_s, fobj.custid  # domainid => customer id
      end

      def rem fobj
        self.values.remove fobj.to_s
        self.display_domains.remove fobj.display_domain
        self.owners.remove fobj.to_s
      end

      def all
        # Load all instances from the sorted set. No need
        # to involve the owners HashKey here.
        self.values.revrangeraw(0, -1).collect { |identifier| from_identifier(identifier) }
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
          raise Onetime::RecordNotFound, "Domain not found #{obj.display_domain}" unless obj.exists?
        end

        # Continue with the built-in `load` from Familia.
        super(custom_domain.identifier)
      end

      # Load a custom domain by display domain only. Used during requests
      # after determining the domain strategy is :custom.
      #
      # @param display_domain [String] The display domain to load
      # @return [V2::CustomDomain, nil] The custom domain record or nil if not found
      def from_display_domain display_domain
        # Get the domain ID from the display_domains hash
        domain_id = self.display_domains.get(display_domain)
        return nil unless domain_id

        # Load the record using the domain ID
        begin
          from_identifier(domain_id)
        rescue Onetime::RecordNotFound
          nil
        end
      end

      # Generate a cryptographically secure short identifier using
      # 256-bit random value truncated to 64 bits for shorter length.
      # @return [String] A secure short identifier in base-36 encoding
      def generate_id
        OT::Utils.generate_short_id
      end
    end

    extend Management
  end
end
