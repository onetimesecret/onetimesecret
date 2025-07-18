# apps/api/v2/models/custom_domain/definition.rb

module V2
  class CustomDomain < Familia::Horreum

    unless defined?(MAX_SUBDOMAIN_DEPTH)
      MAX_SUBDOMAIN_DEPTH = 10 # e.g., a.b.c.d.e.f.g.h.i.j.example.com
      MAX_TOTAL_LENGTH    = 253   # RFC 1034 section 3.1
    end

    prefix :customdomain

    feature :safe_dump

    identifier :derive_id

    # NOTE: The redis key used by older models for values is simply
    # "onetime:customdomain". We'll want to rename those at some point.
    class_sorted_set :values
    class_hashkey :display_domains
    class_hashkey :owners

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

    @txt_validation_prefix = '_onetime-challenge'.freeze

    @safe_dump_fields = [
      { identifier: ->(obj) { obj.identifier } },
      :domainid,
      :display_domain,
      :custid,
      :base_domain,
      :subdomain,
      :trd,
      :tld,
      :sld,
      { is_apex: ->(obj) { obj.apex? } },
      :_original_value,
      :txt_validation_host,
      :txt_validation_value,
      { brand: ->(obj) { obj.brand.hgetall } },
      # NOTE: We don't serialize images here
      :status,
      { vhost: ->(obj) { obj.parse_vhost } },
      :verified,
      :created,
      :updated,
    ].freeze

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
    def derive_id
      if @display_domain.to_s.empty? || @custid.to_s.empty?
        raise Onetime::Problem, 'Cannot generate identifier with emptiness'
      end

      [@display_domain, @custid].gibbler.shorten
    end

  end
end
