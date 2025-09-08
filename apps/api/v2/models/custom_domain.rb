# apps/api/v2/models/custom_domain.rb

require 'public_suffix'

module V2

  # Tryouts:
  # - tests/unit/ruby/try/20_models/27_domains_try.rb
  # - tests/unit/ruby/try/20_models/27_domains_publicsuffix_try.rb

  # Custom Domain
  #
  # NOTE: CustomDomain records can only be created via V2 API
  #
  # Every customer can have one or more custom domains.
  #
  # The list of custom domains that are associated to a customer is
  # distinct from a customer's subdomain.
  #
  # General techical terminology:
  #
  # `tld`` = Top level domain, this is in reference to the last segment of a
  # domain, sometimes the part that is directly after the "dot" symbol. For
  # example, mozilla.org, the .org portion is the tld.
  #
  # `sld` = Second lev'el domain, a domain that is directly below a top-level
  # domain. For example, in https://www.mozilla.org/en-US/, mozilla is the
  # second-level domain of the .org tld.
  #
  # `trd` = Transit routing domain, or known as a subdomain. This is the part of
  # the domain that is before the sld or root domain. For example, in
  # https://www.mozilla.org/en-US/, www is the trd.
  #
  # `FQDN` = Fully Qualified Domain Names, are domain names that are written with
  # the hostname and the domain name, and include the top-level domain, the
  # format looks like [hostname].[domain].[tld]. for ex. [www].[mozilla].[org].
  #
  class CustomDomain < Familia::Horreum
    unless defined?(MAX_SUBDOMAIN_DEPTH)
      MAX_SUBDOMAIN_DEPTH = 10 # e.g., a.b.c.d.e.f.g.h.i.j.example.com
      MAX_TOTAL_LENGTH    = 253   # RFC 1034 section 3.1
    end

    prefix :customdomain

    feature :safe_dump

    # NOTE: The dbkey used by older models for values is simply
    # "onetime:customdomain". We'll want to rename those at some point.
    class_sorted_set :values
    class_hashkey :display_domains
    class_hashkey :owners

    identifier_field :domainid

    field :domainid
    field :display_domain
    field :custid
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

    @txt_validation_prefix = '_onetime-challenge'

    # TODO: SafeDump feature could look in modelname/, modelname/features/,
    # and modelname/features/safe_dump for safe_dump_fields.rb.
    safe_dump_field :identifier, ->(obj) { obj.identifier }
    safe_dump_field :domainid
    safe_dump_field :display_domain
    safe_dump_field :custid
    safe_dump_field :base_domain
    safe_dump_field :subdomain
    safe_dump_field :trd
    safe_dump_field :tld
    safe_dump_field :sld
    safe_dump_field :is_apex, ->(obj) { obj.apex? }
    safe_dump_field :_original_value
    safe_dump_field :txt_validation_host
    safe_dump_field :txt_validation_value
    safe_dump_field :brand, ->(obj) { obj.brand.hgetall }
    # NOTE: We don't include brand images here b/c they create huge payloads
    # that we want to avoid unless we are actually going to use it.
    safe_dump_field :status
    safe_dump_field :vhost, ->(obj) { obj.parse_vhost }
    safe_dump_field :verified
    safe_dump_field :created
    safe_dump_field :updated

    def init
      @domainid = identifier

      # Display domain and cust should already be set and accessible
      # via accessor methods so we should see a valid identifier logged.
      OT.ld "[CustomDomain.init] #{display_domain} id:#{domainid}"

      # Will raise PublicSuffix::DomainInvalid if invalid domain
      ps_domain = PublicSuffix.parse(display_domain, default_rule: nil)

      # Store the individual domain parts that PublicSuffix parsed out
      @base_domain = ps_domain.domain.to_s
      @subdomain   = ps_domain.subdomain.to_s
      @trd         = ps_domain.trd.to_s
      @tld         = ps_domain.tld.to_s
      @sld         = ps_domain.sld.to_s

      # Don't call generate_txt_validation_record here otherwise we'll
      # create a new validation record every time we instantiate a
      # custom domain object. Instead, we'll call it when we're ready
      # to verify the domain.
    end

    # Generate a unique identifier for this customer's custom domain.
    #
    # From a customer's perspective, the display_domain is what they see
    # in their browser's address bar. We use display_domain in the identifier,
    # b/c it's totally reasonable for a user to have multiple custom domains,
    # like secrets.example.com and linx.example.com, and they want to be able
    # to distinguish them from each other.
    #
    # The fact that we rely on this generating the same identifier for a
    # given domain + customer is important b/c it's a means of making
    # sure that the same domain can only be added once per customer.
    #
    # @return [String] A shortened hash of the domain name and custid.
    def generate_id
      self.class.generate_id
    end

    # Check if the given customer is the owner of this domain
    #
    # @param cust [V2::Customer, String] The customer object or customer ID to check
    # @return [Boolean] true if the customer is the owner, false otherwise
    def owner?(cust)
      matching_class = cust.is_a?(V2::Customer)
      (matching_class ? cust.email : cust).eql?(custid)
    end

    # Destroy the custom domain record
    #
    # Removes the domain identifier from the CustomDomain values
    # and then calls the superclass destroy method
    #
    # @param args [Array] Additional arguments to pass to the superclass destroy method
    # @return [Object] The result of the superclass destroy method
    def delete!(*args)
      V2::CustomDomain.rem self
      super # we may prefer to call self.clear here instead
    end

    # Parses the vhost JSON string into a Ruby hash
    #
    # @return [Hash] The parsed vhost configuration, or empty hash if parsing fails
    # @note Returns empty hash in two cases:
    #   1. When vhost is nil or empty string
    #   2. When JSON parsing fails (invalid JSON)
    # @example
    #   custom_domain.vhost = '{"ssl": true, "redirect": "https"}'
    #   custom_domain.parse_vhost #=> {"ssl"=>true, "redirect"=>"https"}
    def parse_vhost
      return {} if vhost.to_s.empty?

      JSON.parse(vhost)
    rescue JSON::ParserError => ex
      OT.le "[CustomDomain.parse_vhost] Error parsing JSON: #{vhost.inspect} - #{ex}"
      {}
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

    def check_identifier!
      return unless identifier.to_s.empty?

      raise "Identifier cannot be empty for #{self.class}"
    end

    # Removes all database keys associated with this custom domain.
    #
    # This includes:
    # - The main database key for the custom domain (`self.dbkey`)
    # - database keys of all related objects specified in `self.class.data_types`
    #
    # @param customer [V2::Customer, nil] The customer to remove the domain from
    # @return [void]
    def destroy!(customer = nil)
      keys_to_delete = [dbkey]

      # This produces a list of dbkeys for each of the DataType
      # relations defined for this model.
      # See Familia::Features::Expiration for references implementation.
      if self.class.has_relations?
        related_names = self.class.data_types.keys
        OT.ld "[destroy!] #{self.class} has relations: #{related_names}"

        related_keys = related_names.filter_map do |name|
          relation = send(name) # e.g. self.brand
          relation.dbkey
        end

        # Append related database keys to the deletion list.
        keys_to_delete.concat(related_keys)
      end

      dbclient.multi do |multi|
        # Delete all keys associated with this domain instance
        multi.del(*keys_to_delete)

        # Also remove from the class-level collections
        multi.zrem(V2::CustomDomain.values.dbkey, identifier)
        multi.hdel(V2::CustomDomain.display_domains.dbkey, display_domain)
        multi.hdel(V2::CustomDomain.owners.dbkey, display_domain)

        # Remove from customer's custom domains collection if customer provided
        unless customer.nil?
          multi.zrem(customer.custom_domains.dbkey, display_domain)
        end
      end
    rescue Redis::BaseError => ex
      OT.le "[CustomDomain.destroy!] Redis error: #{ex.message}"
      raise Onetime::Problem, 'Unable to delete custom domain'
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
      dbclient.exists?(dbkey)
    end

    def allow_public_homepage?
      brand.get('allow_public_homepage').to_s == 'true'
    end

    def allow_public_api?
      brand.get('allow_public_api').to_s == 'true'
    end

    # Validates the format of TXT record host and value used for domain verification.
    # The host must be alphanumeric with dots, underscores, or hyphens only.
    # The value must be a 32-character hexadecimal string.
    #
    # @raise [Onetime::Problem] If the TXT record host or value format is invalid
    # @return [void]
    def validate_txt_record!
      unless txt_validation_host.to_s.match?(/\A[a-zA-Z0-9._-]+\z/)
        raise Onetime::Problem, 'TXT record hostname can only contain letters, numbers, dots, underscores, and hyphens'
      end

      return if txt_validation_value.to_s.match?(/\A[a-f0-9]{32}\z/)

      raise Onetime::Problem, 'TXT record value must be a 32-character hexadecimal string'
    end

    # Generates a TXT record for domain ownership verification.
    # Format: _onetime-challenge-<short_id>[.subdomain]
    #
    # The record consists of:
    # - A prefix (_onetime-challenge-)
    # - First 7 chars of the domain identifier
    # - Subdomain parts if present (e.g. .www or .status.www)
    # - A 32-char random hex value
    #
    # @return [Array<String, String>] The TXT record host and value
    # @raise [Onetime::Problem] If the generated record is invalid
    #
    # Examples:
    #   _onetime-challenge-domainid -> 7709715a6411631ce1d447428d8a70
    #   _onetime-challenge-domainid.status -> cd94fec5a98fd33a0d70d069acaae9
    #
    def generate_txt_validation_record
      # Include a short identifier that is unique to this domain. This
      # allows for multiple customers to use the same domain without
      # conflicting with each other.
      shortid     = identifier.to_s[0..6]
      record_host = "#{self.class.txt_validation_prefix}-#{shortid}"

      # Append the TRD if it exists. This allows for multiple subdomains
      # to be used for the same domain.
      # e.g. The `status` in status.example.com.
      record_host = "#{record_host}.#{trd}" unless trd.to_s.empty?

      # The value needs to be sufficiently unique and non-guessable to
      # function as a challenge response. IOW, if we check the DNS for
      # the domain and match the value we've generated here, then we
      # can reasonably assume that the customer controls the domain.
      record_value = SecureRandom.hex(16)

      OT.info "[CustomDomain] Generated txt record #{record_host} -> #{record_value}"

      @txt_validation_host  = record_host
      @txt_validation_value = record_value

      validate_txt_record!

      # These can now be displayed to the customer for them
      # to continue the validation process.
      [record_host, record_value]
    end

    # The fully qualified domain name for the TXT record.
    #
    # Used to validate the domain ownership by the customer
    # via the Approximated check_records API.
    #
    # e.g. `_onetime-challenge-domainid.froogle.com`
    #
    def validation_record
      [txt_validation_host, base_domain].join('.')
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

        dbclient.watch(obj.dbkey) do
          if obj.exists?
            dbclient.unwatch
            raise Onetime::Problem, 'Duplicate domain for customer'
          end

          dbclient.multi do |_multi|
            obj.generate_txt_validation_record
            obj.save
            # Create minimal customer instance for database key
            cust = V2::Customer.new(custid: custid)
            cust.add_custom_domain(obj)
            # Add to global values set
            add(obj)
          end
        end

        obj # Return the created object
      rescue Redis::BaseError => ex
        OT.le "[CustomDomain.create] Redis error: #{ex.message}"
        raise Onetime::Problem, 'Unable to create custom domain'
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
        raise Onetime::Problem, 'Customer ID required' if custid.to_s.empty?

        segments = input.to_s.split('.').reject(&:empty?)
        raise Onetime::Problem, 'Invalid domain format' if segments.empty?

        raise Onetime::Problem, "Domain too deep (max: #{MAX_SUBDOMAIN_DEPTH})" if segments.length > MAX_SUBDOMAIN_DEPTH

        raise Onetime::Problem, "Domain too long (max: #{MAX_TOTAL_LENGTH})" if input.length > MAX_TOTAL_LENGTH

        display_domain      = self.display_domain(input)
        obj                 = new(display_domain, custid)
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
      def base_domain(input)
        # We don't need to fuss with empty stripping spaces, prefixes,
        # etc because PublicSuffix does that for us.
        PublicSuffix.domain(input, default_rule: nil)
      rescue PublicSuffix::DomainInvalid => ex
        OT.le "[CustomDomain.base_domain] #{ex.message} for `#{input}`"
        nil
      end

      # Takes the given input domain and returns the display domain,
      # the one that we ask the user to create an A record for. So
      # subdir.www.froogle.com would return subdir.www.froogle.com here;
      # www.froogle.com would return www.froogle.com; and froogle.com
      # would return froogle.com.
      #
      def display_domain(input)
        ps_domain = PublicSuffix.parse(input, default_rule: nil)
        ps_domain.subdomain || ps_domain.domain
      rescue PublicSuffix::Error => ex
        OT.le "[CustomDomain.parse] #{ex.message} for `#{input}`"
        raise Onetime::Problem, ex.message
      end

      # Returns boolean, whether the domain is a valid public suffix
      # which checks without actually parsing it.
      def valid?(input)
        PublicSuffix.valid?(input, default_rule: nil)
      end

      def default_domain?(input)
        display_domain = V2::CustomDomain.display_domain(input)
        site_host      = OT.conf.dig('site', 'host')
        OT.ld "[CustomDomain.default_domain?] #{display_domain} == #{site_host}"
        display_domain.eql?(site_host)
      rescue PublicSuffix::Error => ex
        OT.le "[CustomDomain.default_domain?] #{ex.message} for `#{input}"
        false
      end

      # Simply instatiates a new CustomDomain object and checks if it exists.
      def exists?(input, custid)
        # The `parse`` method instantiates a new CustomDomain object but does
        # not save it to the database. We do that here to piggyback on the inital
        # validation and parsing. We use the derived identifier to load
        # the object from the database using
        obj = parse(input, custid)
        OT.ld "[CustomDomain.exists?] Got #{obj.identifier} #{obj.display_domain} #{obj.custid}"
        obj.exists?
      rescue Onetime::Problem => ex
        OT.le "[CustomDomain.exists?] #{ex.message}"
        false
      end

      def add(fobj)
        values.add OT.now.to_i, fobj.to_s # created time, identifier
        display_domains.put fobj.display_domain, fobj.identifier
        owners.put fobj.to_s, fobj.custid # domainid => customer id
      end

      def rem(fobj)
        values.remove fobj.to_s
        display_domains.remove fobj.display_domain
        owners.remove fobj.to_s
      end

      def all
        # Load all instances from the sorted set. No need
        # to involve the owners HashKey here.
        values.revrangeraw(0, -1).collect { |identifier| from_identifier(identifier) }
      end

      def recent(duration = 48.hours)
        spoint = OT.now.to_i - duration
        epoint = OT.now.to_i
        values.rangebyscoreraw(spoint, epoint).collect { |identifier| load(identifier) }
      end

      # Implement a load method for CustomDomain to make sure the
      # correct derived ID is used as the key.
      def load(display_domain, custid)
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
      def from_display_domain(display_domain)
        # Get the domain ID from the display_domains hash
        domain_id = display_domains.get(display_domain)
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

    extend ClassMethods
  end
end
