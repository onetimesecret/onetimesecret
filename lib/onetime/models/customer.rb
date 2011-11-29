

class Onetime::Customer < Familia::HashKey
  include Onetime::Models::RedisHash
  include Onetime::Models::Passphrase
  def initialize custid=:anon
    @custid = custid  # if we use accessor methods it will sync to redis.
    super name, :db => 6
  end
  def identifier 
    @custid
  end
  def anonymous?
    custid.to_s == 'anon'
  end
  def email
    @custid
  end
  def role
    self.get_value(:role) || 'customer'
  end
  def role? guess
    role.to_s == guess.to_s
  end
  def verified?
    verified.to_s == "verified"
  end
  def metadata_list
    if @metadata_list.nil?
      el = [prefix, identifier, :metadata]
      el.unshift Familia.apiversion unless Familia.apiversion.nil?
      @metadata_list = Familia::SortedSet.new Familia.join(el)
    end
    @metadata_list
  end
  def metadata
    metadata_list.revmembers.collect { |key| OT::Metadata.load key }.compact
  end
  def add_metadata s
    metadata_list.add OT.now.to_i, s.key
  end
  class << self
    def anonymous
      cust = new
    end
    def exists? custid
      cust = new custid
      cust.exists?
    end
    def load custid
      cust = new custid
      cust.exists? ? cust : nil
    end
    def create custid, email=nil
      cust = new custid
      # force the storing of the fields to redis
      cust.custid = custid
      cust.update_fields # calls update_time!
      cust
    end
  end
end