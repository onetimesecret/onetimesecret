

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
  def colonel?
    role.to_s == 'colonel'
  end
  class << self
    def anonymous
      cust = new
    end
  end
end