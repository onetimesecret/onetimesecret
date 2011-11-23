

class Onetime::Customer < Familia::HashKey
  include Onetime::Models::RedisHash
  db 3
  def initialize custid=:anon
    @custid = custid  # if we use accessor methods it will sync to redis.
    super name
  end
  def identifier 
    @custid
  end
  def anonymous?
    custid.to_s == 'anon'
  end
  class << self
    def anonymous
      cust = new
    end
  end
end