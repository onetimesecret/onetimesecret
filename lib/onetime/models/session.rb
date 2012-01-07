


# s = Onetime::Session.load ''
class Onetime::Session < Familia::HashKey
  @values = Familia::SortedSet.new name.to_s.downcase.gsub('::', Familia.delim).to_sym, :db => 1
  class << self
    attr_reader :values
    def add sess
      self.values.add OT.now.to_i, sess.identifier
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
  include Onetime::Models::RedisHash
  include Onetime::Models::RateLimited
  attr_reader :entropy
  def initialize ipaddress=nil, useragent=nil, custid=nil
    @ipaddress, @custid, @useragent = ipaddress, custid, useragent  # must be nil or have values!
    @entropy = [ipaddress, custid, useragent]
    # TODO: This calls Entropy every time
    @sessid = "anon"
    super name, :db => 1, :ttl => 20.minutes
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
      sess.exists? ? (add(sess); sess) : nil
    end
    def create ipaddress, custid, useragent=nil
      sess = new ipaddress, custid, useragent
      # force the storing of the fields to redis
      sess.update_sessid
      sess.ipaddress, sess.custid, sess.useragent = ipaddress, custid, useragent
      sess.save
      add sess
      sess
    end
    def generate_id *entropy
      entropy << OT.entropy
      input = [OT.instance, OT.now.to_f, :session, *entropy].join(':')
      # Not using gibbler to make sure it's always SHA512
      Digest::SHA512.hexdigest(input).to_i(16).to_s(36) # base-36 encoding
    end
  end
  def sessid= sid
    @sessid = sid
    @name = name
    @sessid
  end
  def set_form_fields hsh
    self.form_fields = hsh.to_json unless hsh.nil?
  end
  def get_form_fields!
    fields_json = self.form_fields!
    return if fields_json.nil?
    OT::Utils.indifferent_params Yajl::Parser.parse(fields_json)
  end
  def identifier
    @sessid  # Don't call the method
  end
  # Used by the limiter to estimate a unique client. We can't use
  # the session ID b/c they can choose to not send the cookie.
  def external_identifier  
    elements = []
    elements << ipaddress || 'UNKNOWNIP'
    elements << custid || 'anon'
    #OT.ld "sess identifier input: #{elements.inspect}"
    @external_identifier ||= elements.gibbler.base(36)
    @external_identifier
  end
  def stale?
    self[:stale].to_s == "true"
  end
  def update_fields hsh={}
    hsh[:sessid] ||= sessid
    super hsh
  end
  def update_sessid
    self.sessid = self.class.generate_id *entropy
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
    self.authenticated.to_s == 'true'
  end
  def anonymous?
    sessid.to_s == 'anon' || sessid.to_s.empty?
  end
  def load_customer
    return OT::Customer.anonymous if anonymous?
    cust = OT::Customer.load custid 
    cust.nil? ? OT::Customer.anonymous : cust
  end
  def set_error_message msg
    self.error_message = msg
  end
  def set_info_message msg
    self.info_message = msg
  end
  def session_group groups
    sessid.to_i(16) % groups.to_i
  end
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
  def searchengine?()     
    @agent.to_s  =~ /\b(Baidu|Gigabot|Googlebot|libwww-perl|lwp-trivial|msnbot|SiteUptime|Slurp|WordPress|ZIBB|ZyBorg|Yahoo|bing|superfeedr)\b/i
  end
  def clitool?()          @agent.to_s  =~ /curl|wget/i  || stella?      end
  def human?()           !searchengine? && !superfeedr? && !clitool? && !stella? end
  private
end
