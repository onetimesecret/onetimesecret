class Onetime::Subdomain < Familia::HashKey
  include Onetime::Models::RedisHash
  @values = Familia::SortedSet.new name.to_s.downcase.gsub('::', Familia.delim).to_sym, :db => 6
  class << self
    attr_reader :values
    def add obj
      self.values.add OT.now.to_i, obj.identifier
      self.values.remrangebyscore 0, OT.now.to_i-2.days
    end
    def all
      self.values.revrangeraw(0, -1).collect { |identifier| load(identifier) }
    end
    def recent duration=30.days
      spoint, epoint = OT.now.to_i-duration, OT.now.to_i
      self.values.rangebyscoreraw(spoint, epoint).collect { |identifier| load(identifier) }
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
      obj.exists? ? (add(obj); obj) : nil
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
    self.cname = OT::Subdomain.normalize_cname(cname)
  end
  def owner? cust
    (cust.is_a?(OT::Customer) ? cust.custid : cust).to_s == custid.to_s
  end
  def destroy! *args
    super
    OT::Subdomain.values.rem identifier
  end
  def fulldomain
    '%s.onetimesecret.com' % @cname
  end
end