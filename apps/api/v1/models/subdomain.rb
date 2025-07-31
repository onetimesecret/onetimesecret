# apps/api/v1/models/subdomain.rb

# Customer->Subdomain
#
# Every customer has or can have a subdomain. This was a feature
# from the early years. Since there can only be 0 or 1, the redis
# key for this object is simply `customer:custid:subdomain`. Real-
# world example of a subdomain: mypage.github.io.
#
# The customer subdomain is distinct from CustomDomain (plural)
# which is a list of domains that are managed by the customer.
#
module V1
  class Subdomain < Familia::Horreum

    feature :safe_dump

    prefix :customer
    identifier :custid
    suffix :subdomain

    class_hashkey :values, key: 'onetime:subdomain'

    field :custid
    field :cname
    field :created
    field :updated
    field :homepage

    # Safe fields for Stripe Customer object
    @safe_dump_fields = [
      { :identifier => ->(obj) { obj.identifier } },
      :custid,
      :cname,
      :email,
      :created,
      :updated,
      :homepage,

    ]
    def init
      @cname = update_cname(cname)
    end

    def update_cname cname
      @cname = self.cname = V1::Subdomain.normalize_cname(cname)
    end

    def owner? cust
      (cust.is_a?(V1::Customer) ? cust.custid : cust).to_s == custid.to_s
    end

    def destroy! *args
      ret = super
      V1::Subdomain.values.remove identifier
      ret
    end

    def fulldomain
      # Previously was:
      #   '%s.%s' % [self['cname'], OT.conf['site']['domain']]
      #
      raise NotImplementedError
    end

    def company_domain
      return unless self.homepage
      URI.parse(self.homepage).host
    end

    module ClassMethods

      attr_reader :values
      def add cname, custid
        ret = self.values.put cname, custid
        ret
      end

      def rem cname
        self.values.remove(cname)
      end

      def all
        self.values.all.collect { |cname,custid| load(custid) }.compact
      end

      ##
      # Checks if a given CNAME is owned by a specific customer.
      #
      # @param cname [String] The custom domain name (CNAME) to check.
      # @param custid [String, Integer] The customer ID to verify ownership against.
      # @return [Boolean] true if the CNAME is mapped to the given customer ID, false otherwise.
      def owned_by?(cname, custid)
        map(cname) == custid
      end

      ##
      # Retrieves the customer ID associated with a given CNAME.
      #
      # @param cname [String] The custom domain name (CNAME) to look up.
      # @return [String, Integer, nil] The customer ID mapped to the CNAME, or nil if not found.
      #
      # The term "map" is used here to denote the act of looking up the corresponding
      # customer ID for a given domain. It's a concise way to express the domain-to-customer mapping.
      def map(cname)
        self.values.get(cname)
      end

      ##
      # Checks if a given CNAME is mapped to any customer.
      #
      # @param cname [String] The custom domain name (CNAME) to check.
      # @return [Boolean] true if the CNAME is mapped to a customer, false otherwise.
      def mapped?(cname)
        self.values.has_key?(cname)
      end

      ##
      # Loads a customer record based on a given CNAME.
      #
      # @param cname [String] The custom domain name (CNAME) to use for loading.
      # @return [Object, nil] The loaded customer object if found, nil otherwise.
      #
      # This method combines the mapping lookup with loading the customer record,
      # providing a convenient way to retrieve a customer by their custom domain.
      def find_by_cname(cname)
        load map(cname)
      end

      def create cname, custid
        obj = new cname: normalize_cname(cname), custid: custid
        obj.save
        obj
      end

      def normalize_cname cname
        cname.to_s.downcase.gsub(/[^a-z0-9\_]/, '')
      end
    end

    extend ClassMethods
  end
end
