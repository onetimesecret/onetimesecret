# apps/api/v2/models/definitions/custom_domain_definition.rb

# Tryouts:
# - tests/unit/ruby/try/20_models/27_domains_try.rb
# - tests/unit/ruby/try/20_models/27_domains_publicsuffix_try.rb

# Custom Domain
#
module V2
  class CustomDomain < Familia::Horreum

    unless defined?(MAX_SUBDOMAIN_DEPTH)
      MAX_SUBDOMAIN_DEPTH = 10 # e.g., a.b.c.d.e.f.g.h.i.j.example.com
      MAX_TOTAL_LENGTH = 253   # RFC 1034 section 3.1
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

    @txt_validation_prefix = '_onetime-challenge'

    @safe_dump_fields = [
      { :identifier => ->(obj) { obj.identifier } },
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
      @domainid = self.identifier

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
  end
end
