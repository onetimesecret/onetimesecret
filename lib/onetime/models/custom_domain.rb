# lib/onetime/models/custom_domain.rb
#
# frozen_string_literal: true

require 'public_suffix'

module Onetime

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
    include Familia::Features::Autoloader

    unless defined?(MAX_SUBDOMAIN_DEPTH)
      MAX_SUBDOMAIN_DEPTH = 10 # e.g., a.b.c.d.e.f.g.h.i.j.example.com
      MAX_TOTAL_LENGTH    = 253   # RFC 1034 section 3.1
    end

    using Familia::Refinements::TimeLiterals

    prefix :customdomain

    feature :safe_dump_fields
    feature :relationships  # Enable Familia v2 features
    feature :object_identifier  # Auto-generates objid

    # NOTE: The dbkey used by older models for values is simply
    # "onetime:customdomain". We'll want to rename those at some point.
    #
    # "values" was Familia v1 convention. In Familia, the same functionality
    # is provided automatically by ModelName.instances.
    #   class_sorted_set :values

    class_hashkey :display_domains
    class_hashkey :owners

    identifier_field :domainid

    field :display_domain
    field :org_id       # Organization foreign key (replaces custid)
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

    # Familia v2 relationships
    # Participate in Organization.domains collection (auto-generated sorted_set)
    participates_in :Organization, :domains, score: :created

    # Global unique index - domain can only exist once
    unique_index :display_domain, :display_domain_index

    @txt_validation_prefix = '_onetime-challenge'



    def init
      # Display domain should already be set via accessor methods
      # The ObjectIdentifier feature provides objid automatically via lazy generation
      # which is aliased to domainid below
      OT.ld "[CustomDomain.init] #{display_domain} id:#{domainid} org_id:#{org_id}"

      # Parse the domain structure (will raise if invalid)
      if display_domain && !display_domain.empty?
        ps_domain = PublicSuffix.parse(display_domain, default_rule: nil)

        # Store the individual domain parts that PublicSuffix parsed out
        @base_domain = ps_domain.domain.to_s
        @subdomain   = ps_domain.subdomain.to_s
        @trd         = ps_domain.trd.to_s
        @tld         = ps_domain.tld.to_s
        @sld         = ps_domain.sld.to_s
      end

      # Don't call generate_txt_validation_record here otherwise we'll
      # create a new validation record every time we instantiate a
      # custom domain object. Instead, we'll call it when we're ready
      # to verify the domain.
    end

    # Alias domainid to objid for API compatibility
    # The object_identifier feature provides objid automatically
    def domainid
      objid
    end

    # Validate required fields before save
    def save
      raise Onetime::Problem, 'Organization ID required' if org_id.to_s.empty?
      raise Onetime::Problem, 'Display domain required' if display_domain.to_s.empty?
      super
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
    # In the new model, ownership is through organization membership
    #
    # @param cust [Onetime::Customer, String] The customer object or customer ID to check
    # @return [Boolean] true if the customer is the owner, false otherwise
    def owner?(cust)
      return false unless org_id

      org = Onetime::Organization.load(org_id)
      return false unless org

      # Normalize input to Customer object for safe method calls
      customer = cust.is_a?(Onetime::Customer) ? cust : Onetime::Customer.load(cust)
      return false unless customer

      org.owner_id == customer.custid || org.member?(customer)
    end

    # Check if this domain is owned by the given organization
    #
    # @param org [Onetime::Organization] The organization to check
    # @return [Boolean] true if the organization owns this domain
    def owned_by_organization?(org)
      organization_instances.any? { |o| o.objid == org.objid }
    end

    # Get the primary organization for this domain based on org_id field
    # This works even if the participation has been removed
    #
    # @return [Onetime::Organization, nil] The organization or nil if org_id is not set
    def primary_organization
      return nil if org_id.to_s.empty?

      Onetime::Organization.load(org_id)
    rescue Familia::RecordNotFound
      nil
    end

    # Destroy the custom domain record
    #
    # Removes the domain identifier from the CustomDomain values
    # and then calls the superclass destroy method
    #
    # @param args [Array] Additional arguments to pass to the superclass destroy method
    # @return [Object] The result of the superclass destroy method
    def delete!(*args)
      Onetime::CustomDomain.rem self
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
    # - Familia v2 participations in organization.domains collections
    #
    # @return [void]
    def destroy!
      # Remove from organization participations before Familia cleanup
      organization_instances.each do |o|
        remove_from_organization_domains(o)
      end

      # Call Familia's built-in destroy which handles:
      # - Main object key deletion
      # - Related fields cleanup (brand, logo, icon hashkeys)
      # - Transaction management
      super
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
      # @param org_id [String] The organization ID to associate with (replaces custid)
      # @return [Onetime::CustomDomain] The created custom domain
      # @raise [Onetime::Problem] If domain is invalid or already exists
      #
      # More Info:
      # We need a minimum of a domain and organization id to create a custom
      # domain -- or more specifically, a custom domain identifier. We
      # allow instantiating a custom domain without an organization id, but
      # instead raise a fuss if we try to save it later without one.
      #
      # See CustomDomain.base_domain and display_domain for details on
      # the difference between display domain and base domain.
      #
      # NOTE: Internally within this class, we try not to use the
      # unqualified term "domain" on its own since there's so much
      # room for confusion.
      #
      def create!(input, org_id)
        obj = parse(input, org_id)

        dbclient.watch(obj.dbkey) do
          if obj.exists?
            dbclient.unwatch
            raise Onetime::Problem, 'Duplicate domain for organization'
          end

          dbclient.multi do |_multi|
            obj.generate_txt_validation_record
            obj.save

            # Use Familia v2 participation to add to organization.domains
            org = Onetime::Organization.load(org_id)
            obj.add_to_organization_domains(org) if org

            # Add to global values set
            add(obj)
          end
        end

        obj # Return the created object
      rescue Familia::RecordExistsError => ex
        OT.le "[CustomDomain.create] Duplicate domain: #{ex.message}"
        raise Onetime::Problem, 'Duplicate domain for organization'
      rescue Redis::BaseError => ex
        OT.le "[CustomDomain.create] Redis error: #{ex.message}"
        raise Onetime::Problem, 'Unable to create custom domain'
      end

      # Returns a new Onetime::CustomDomain object (without saving it).
      #
      # @param input [String] The domain name to parse
      # @param org_id [String] Organization ID associated with the domain (replaces custid)
      #
      # @return [Onetime::CustomDomain]
      #
      # @raise [PublicSuffix::DomainInvalid] If domain is invalid
      # @raise [PublicSuffix::DomainNotAllowed] If domain is not allowed
      # @raise [PublicSuffix::Error] For other PublicSuffix errors
      # @raise [Onetime::Problem] If domain exceeds MAX_SUBDOMAIN_DEPTH or MAX_TOTAL_LENGTH
      #
      def parse(input, org_id)
        raise Onetime::Problem, 'Organization ID required' if org_id.to_s.empty?

        segments = input.to_s.split('.').reject(&:empty?)
        raise Onetime::Problem, 'Invalid domain format' if segments.empty?

        raise Onetime::Problem, "Domain too deep (max: #{MAX_SUBDOMAIN_DEPTH})" if segments.length > MAX_SUBDOMAIN_DEPTH

        raise Onetime::Problem, "Domain too long (max: #{MAX_TOTAL_LENGTH})" if input.length > MAX_TOTAL_LENGTH

        display_domain      = self.display_domain(input)
        OT.ld "[CustomDomain.parse] Creating with display_domain=#{display_domain.inspect}, org_id=#{org_id.inspect}"
        obj                 = new(display_domain: display_domain, org_id: org_id)
        obj._original_value = input

        # Debug the created object
        OT.ld "[CustomDomain.parse] Created object: display_domain=#{obj.display_domain.inspect}, org_id=#{obj.org_id.inspect}, identifier=#{obj.identifier.inspect}"

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
        result = ps_domain.subdomain || ps_domain.domain

        # Safety check to prevent nil display_domain which causes serialization issues
        if result.nil?
          OT.le "[CustomDomain.display_domain] Parsed domain resulted in nil: subdomain=#{ps_domain.subdomain.inspect}, domain=#{ps_domain.domain.inspect} for input `#{input}`"
          raise Onetime::Problem, "Invalid domain format - unable to determine display domain"
        end

        result
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
        display_domain = Onetime::CustomDomain.display_domain(input)
        site_host      = OT.conf.dig('site', 'host')
        OT.ld "[CustomDomain.default_domain?] #{display_domain} == #{site_host}"
        display_domain.eql?(site_host)
      rescue PublicSuffix::Error => ex
        OT.le "[CustomDomain.default_domain?] #{ex.message} for `#{input}"
        false
      end

      # Simply instatiates a new CustomDomain object and checks if it exists.
      def exists?(input, org_id)
        # The `parse` method instantiates a new CustomDomain object but does
        # not save it to the database. We do that here to piggyback on the initial
        # validation and parsing. We use the derived identifier to load
        # the object from the database.
        obj = parse(input, org_id)
        OT.ld "[CustomDomain.exists?] Got #{obj.identifier} #{obj.display_domain} #{obj.org_id}"
        obj.exists?
      rescue Onetime::Problem => ex
        OT.le "[CustomDomain.exists?] #{ex.message}"
        false
      end

      def add(fobj)
        # Safety checks to prevent serialization errors
        if fobj.display_domain.nil?
          OT.le "[CustomDomain.add] display_domain is nil for #{fobj.class}:#{fobj.identifier}"
          raise Onetime::Problem, "Cannot add custom domain with nil display_domain"
        end

        if fobj.identifier.nil?
          OT.le "[CustomDomain.add] identifier is nil for #{fobj.class}:#{fobj.display_domain}"
          raise Onetime::Problem, "Cannot add custom domain with nil identifier"
        end

        if fobj.org_id.nil?
          OT.le "[CustomDomain.add] org_id is nil for #{fobj.class}:#{fobj.display_domain}:#{fobj.identifier}"
          debug_info = begin
            { to_h: fobj.to_h, methods: fobj.methods.grep(/org/) }
          rescue => e
            { error: e.message }
          end
          OT.le "[CustomDomain.add] fobj debug: #{debug_info.inspect}"
          raise Onetime::Problem, "Cannot add custom domain with nil org_id. display_domain=#{fobj.display_domain.inspect}, identifier=#{fobj.identifier.inspect}"
        end

        values.add fobj.to_s # created time, identifier
        display_domains.put fobj.display_domain, fobj.identifier
        owners.put fobj.to_s, fobj.org_id # domainid => organization id
      end

      def rem(fobj)
        values.remove fobj.to_s
        display_domains.remove fobj.display_domain
        owners.remove fobj.to_s
      end

      def all
        # Load all instances from the sorted set. No need
        # to involve the owners HashKey here.
        values.revrangeraw(0, -1).collect { |identifier| find_by_identifier(identifier) }
      end

      def recent(duration = 48.hours)
        spoint = OT.now.to_i - duration
        epoint = OT.now.to_i
        values.rangebyscoreraw(spoint, epoint).collect { |identifier| load(identifier) }
      end

      # Implement a load method for CustomDomain to make sure the
      # correct derived ID is used as the key.
      def load(display_domain, org_id)
        custom_domain = parse(display_domain, org_id).tap do |obj|
          OT.ld "[CustomDomain.load] Got #{obj.identifier} #{obj.display_domain} #{obj.org_id}"
          raise Onetime::RecordNotFound, "Domain not found #{obj.display_domain}" unless obj.exists?
        end

        # Continue with the built-in `load` from Familia.
        super(custom_domain.identifier)
      end

      # Load a custom domain by display domain only. Used during requests
      # after determining the domain strategy is :custom.
      #
      # @param display_domain [String] The display domain to load
      # @return [Onetime::CustomDomain, nil] The custom domain record or nil if not found
      def from_display_domain(display_domain)
        # Get the domain ID from the display_domains hash
        domain_id = display_domains.get(display_domain)
        return nil unless domain_id

        # Load the record using the domain ID
        begin
          find_by_identifier(domain_id)
        rescue Onetime::RecordNotFound
          nil
        end
      end

      # Generate a cryptographically secure short identifier using
      # 256-bit random value truncated to 64 bits for shorter length.
      # @return [String] A secure short identifier in base-36 encoding
      def generate_id
        Familia.generate_id
      end

      # Find all custom domains for a given organization
      # Uses the Familia v2 participates_in relationship
      #
      # @param org_id [String] The organization identifier (orgid)
      # @return [Array<String>] Array of domain identifiers
      def find_all_by_org_id(org_id)
        org = Onetime::Organization.load(org_id)
        return [] unless org

        # org.domains is the auto-generated SortedSet from participates_in
        org.domains.to_a
      rescue Familia::RecordNotFound
        []
      end
    end

    extend ClassMethods
  end
end
