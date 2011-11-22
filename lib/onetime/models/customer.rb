

class Onetime::Customer < Familia::HashKey
  include Onetime::Models::RedisHash
  def initialize custid=:anon
    self.cache[:custid] = custid  # if we use accessor methods it will sync to redis.
    super name, :db => 1
  end
  def suffix 
    custid
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