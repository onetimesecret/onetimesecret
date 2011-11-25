

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
    def create custid, email=nil
      cust = new custid
      # force the storing of the fields to redis
      cust.sess.custid = custid
      sess.update_fields # calls update_time!
      sess
    end
  end
end