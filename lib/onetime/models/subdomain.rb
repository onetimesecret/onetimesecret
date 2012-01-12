# http://www.artviper.net/website-tools/colorfinder.php
class Onetime::Subdomain < Familia::HashKey
  include Onetime::Models::RedisHash
  @values = Familia::HashKey.new name.to_s.downcase.gsub('::', Familia.delim).to_sym, :db => 6
  class << self
    attr_reader :values
    def add obj
      self.values.put obj.cname, obj.custid
    end
    def rem obj
      self.values.del(obj['cname'])
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
  end
  attr_accessor :values
  def initialize custid=nil, cname=nil
    @prefix, @suffix = :customer, :subdomain
    @cname, @custid = OT::Subdomain.normalize_cname(cname), custid
    super name, :db => 6
  end
  class << self
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
      add obj
      obj
    end
    def normalize_cname cname
      cname.to_s.downcase.gsub(/[^a-z0-9\_]/, '')
    end
  end
  def identifier
    @custid  # Don't call the method
  end
  def update_cname cname
    self.class.rem self
    @cname = self.cname = OT::Subdomain.normalize_cname(cname)
    self.class.add self
  end
  def owner? cust
    (cust.is_a?(OT::Customer) ? cust.custid : cust).to_s == custid.to_s
  end
  def destroy! *args
    OT::Subdomain.values.rem @cname
    super
  end
  def fulldomain
    '%s.%s' % [self['cname'], OT.conf[:site][:domain]]
  end
  def company_domain
    return unless self['homepage']
    URI.parse(self['homepage']).host
  end
end