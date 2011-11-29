

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
  def role
    self.get_value(:role) || 'customer'
  end
  def role? guess
    role.to_s == guess.to_s
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