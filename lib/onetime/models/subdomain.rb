
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
class Onetime::Subdomain < Familia::Horreum
  db 6

  class_sorted_set :values, key: 'onetime:subdomain'

  identifier :custid

  field :custid
  field :cname
  field :createed
  field :updated
  field :homepage

  def initialize custid=nil, cname=nil
    @prefix, @suffix = :customer, :subdomain
    @cname, @custid = OT::Subdomain.normalize_cname(cname), custid
    super name, db: 6
  end

  def identifier
    @custid  # Don't call the method
  end

  def update_cname cname
    @cname = self.cname = OT::Subdomain.normalize_cname(cname)
  end

  def owner? cust
    (cust.is_a?(OT::Customer) ? cust.custid : cust).to_s == custid.to_s
  end

  def destroy! *args
    OT::Subdomain.values.rem @cname
    super
  end

  def fulldomain
    # Previously was:
    #   '%s.%s' % [self['cname'], OT.conf[:site][:domain]]
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
      ret = self.values.del(cname)
    end
    def all
      self.values.all.collect { |cname,custid| load(custid) }.compact
    end
    def owned_by? cname, custid
      map(cname) == custid
    end
    def map cname
      self.values.get(cname)
    end
    def mapped? cname
      self.values.has_key?(cname)
    end
    def load_by_cname cname
      load map(cname)
    end

    def exists? objid
      obj = new objid
      obj.exists?
    end
    def load objid
      obj = new objid
      obj.exists? ? obj : nil
    end
    def create custid, cname
      obj = new custid, cname
      obj.update_fields :cname => normalize_cname(cname), :custid => custid
      obj
    end
    def normalize_cname cname
      cname.to_s.downcase.gsub(/[^a-z0-9\_]/, '')
    end
  end

  extend ClassMethods
end
