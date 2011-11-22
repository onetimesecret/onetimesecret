


# s = Onetime::Session.load ''
class Onetime::Session < Familia::HashKey
  include Onetime::Models::RedisHash
  include Onetime::Models::RateLimited
  attr_reader :entropy
  db 1
  def initialize ipaddress=nil, custid=nil, useragent=nil
    @ipaddress, @custid, @useragent = ipaddress, custid, useragent
    @entropy = [ipaddress, custid, useragent]
    @sessid = self.sessid || self.class.generate_id(*entropy)
    super name, :ttl => 20.minutes
  end
  class << self
    def exists? sessid
      sess = new 
      sess.sessid = sessid
      sess.exists?
    end
    def load sessid
      sess = new 
      sess.sessid = sessid
      sess.exists? ? sess : nil
    end
    def create ipaddress, custid, useragent=nil
      sess = new ipaddress, custid, useragent
      # force the storing of the fields to redis
      sess.ipaddress, sess.custid, sess.useragent = ipaddress, custid, useragent
      sess.update_fields # calls update_time!
      sess
    end
    def generate_id *entropy
      entropy << OT.entropy
      input = [OT.instance, OT.now, self.class, entropy].join(':')
      # Not using gibbler to make sure it's always SHA512
      Digest::SHA512.hexdigest(input).to_i(16).to_s(36) # base-36 encoding
    end
  end
  def sessid= sid
    @sessid = sid
    @name = name
    @sessid
  end
  def suffix
    @sessid  # Don't call the method
  end
  def stale?
    self[:stale].to_s == "true"
  end
  def update_fields hsh={}
    hsh[:sessid] ||= sessid
    super hsh
  end
  def replace!
    @custid ||= self[:custid]
    newid = self.class.generate_id @entropy
    rename name(newid) if exists?
    @sessid = newid
    # This update is important b/c it ensures that the
    # data gets written to redis. 
    update_fields :stale => false
    sessid
  end
  def shrimp? guess
    shrimp = self[:shrimp].to_s
    (!shrimp.empty?) && shrimp == guess.to_s
  end
  def add_shrimp
    ret = self.shrimp
    if ret.to_s.empty?
      ret = self.shrimp = self.class.generate_id(sessid, custid, :shrimp) 
    end
    ret
  end
  def clear_shrimp!
    delete :shrimp
    nil
  end
  def authenticated?
    unless self.cache.has_key?(:authenticated)
      refresh_cache
    end
    self.authenticated.to_s == 'true'
  end
  #def load_customer
  #  ret = OT::Customer.first(:custid=>custid) || OT::Customer.anonymous
  #  ret
  #end
  def opera?()            @agent.to_s  =~ /opera/i                      end
  def firefox?()          @agent.to_s  =~ /firefox/i                    end
  def chrome?()          !(@agent.to_s =~ /chrome/i).nil?               end
  def safari?()           (@agent.to_s =~ /safari/i && !chrome?)        end
  def konqueror?()        @agent.to_s  =~ /konqueror/i                  end
  def ie?()               (@agent.to_s =~ /msie/i && !opera?)           end
  def gecko?()            (@agent.to_s =~ /gecko/i && !webkit?)         end
  def webkit?()           @agent.to_s  =~ /webkit/i                     end
  def stella?()           @agent.to_s  =~ /stella/i                     end
  def superfeedr?()       @agent.to_s  =~ /superfeedr/i                 end
  def google?()           @agent.to_s  =~ /google/i                     end
  def yahoo?()            @agent.to_s  =~ /yahoo/i                      end
  def yandex?()           @agent.to_s  =~ /yandex/i                     end
  def baidu?()            @agent.to_s  =~ /baidu/i                      end
  def stella?()           @agent.to_s  =~ /stella/i                     end
  def searchengine?()     google? || yahoo? || yandex? || baidu?        end
  def clitool?()          @agent.to_s  =~ /curl|wget/i  || stella?      end
  def human?()           !searchengine? && !superfeedr? && !clitool? && !stella? end
  private
end
