
class Onetime::Session < Familia::Horreum
  include Onetime::Models::RateLimited

  db 9
  ttl 20.minutes
  prefix :session

  feature :safe_dump

  class_sorted_set :values, key: "onetime:session"

  identifier :sessid

  # NOTE: Avoid adding fields with the same name as settings (e.g. ttl)

  field :ipaddress
  field :custid
  field :useragent
  field :stale
  field :sessid
  field :updated
  field :created
  field :authenticated
  field :external_identifier
  field :key
  field :shrimp

  # In some UI flows, we temporarily store form values after a form
  # error so that the form UI inputs can be prepopulated, even if
  # there's a redirect inbetween. Ideally we can move this to local
  # storage with Vue.
  field :form_fields

  # TODO: The authenticated_by field needs to be revisited
  field :authenticated_by

  # When set to true, the session reports itself as not authenticated
  # regardless of the value of the authenticated field. This allows
  # the site to disable authentication without affecting the session
  # data. For example, if we want to disable authenticated features
  # temporarily (in case of abuse, etc.) we can set this to true so
  # the user will remain signed in after we enable authentication again.
  #
  # During the time that authentication is disabled, the session will
  # be anonymous and the customer will be anonymous.
  #
  # This value is set on every request and should not be persisted.
  attr_accessor :disable_auth

  def init

    # Defaulting the session ID to nil ensures we can't persist this instance
    # to redis until one is set (see `RedisHash#check_identifier!`). This is
    # important b/c we don't want to be colliding a default session ID and risk
    # leaking session data (e.g. across anonymous users).
    #
    # This is the distinction between .new and .create. .new is a new session
    # that hasn't been saved to redis yet. .create is a new session that has
    # been saved to redis.
    #@sessid = nil
    self.key ||= identifier

    @disable_auth = false

    OT.ld "[Session.init] Initialized session #{self}"
  end

  def sessid
    @sessid ||= self.class.generate_id
    @sessid
  end

  def set_form_fields hsh
    self.form_fields = hsh.to_json unless hsh.nil?
  end

  def get_form_fields!
    fields_json = self.form_fields # previously name self.form_fields!
    return if fields_json.nil?
    self.form_fields = nil
    OT::Utils.indifferent_params Yajl::Parser.parse(fields_json)
  end

  # The external identifier is used by the rate limiter to estimate a unique
  # client. We can't use the session ID b/c the request agent can choose to
  # not send cookies, or the user can clear their cookies (in both cases the
  # session ID would change which would circumvent the rate limiter). The
  # external identifier is a hash of the IP address and the customer ID
  # which means that anonymous users from the same IP address are treated
  # as the same client (as far as the limiter is concerned). Not ideal.
  #
  # To put it another way, the risk of colliding external identifiers is
  # acceptable for the rate limiter, but not for the session data. Acceptable
  # b/c the rate limiter is a temporary measure to prevent abuse, and the
  # worse case scenario is that a user is rate limited when they shouldn't be.
  # The session data is permanent and must be kept separate to avoid leaking
  # data between users.
  def external_identifier
    elements = []
    elements << ipaddress || 'UNKNOWNIP'
    elements << custid || 'anon'
    @external_identifier ||= elements.gibbler.base(36)
    OT.ld "[Session.external_identifier] sess identifier input: #{elements.inspect} (result: #{@external_identifier})"
    @external_identifier
  end

  def short_identifier
    identifier.slice(0, 12)
  end

  def stale?
    self.stale.to_s == 'true'
  end

  def update_sessid!
    self.sessid = self.class.generate_id
  end

  def update_fields(**kwargs)
    kwargs.each do |field, value|
      self.send("#{field}=", value)
    end
    self.save
  end

  def rename(newkey)
    redis.rename rediskey, newkey
  end

  def replace!
    @custid ||= self.custid
    newid = self.class.generate_id

    # Rename the existing key in redis if necessary
    if exists?
      self.sessid = newid
      #self.rename rediskey # disabled, part of Familia v1.0 updates
    end

    # This update is important b/c it ensures that the
    # data gets written to redis.
    self.stale = 'false'
    self.sessid = newid
    save

    sessid
  end

  def shrimp? guess
    shrimp = self.shrimp.to_s
    (!shrimp.empty?) && shrimp == guess.to_s
  end

  def add_shrimp
    self.shrimp ||= self.class.generate_id
    self.shrimp
  end

  def clear_shrimp!
    delete :shrimp
    nil
  end

  def authenticated?
    !disable_auth && authenticated.to_s == 'true'
  end

  def anonymous?
    disable_auth || sessid.to_s == 'anon' || sessid.to_s.empty?
  end

  def load_customer
    return OT::Customer.anonymous if anonymous?
    cust = OT::Customer.load custid
    cust.nil? ? OT::Customer.anonymous : cust
  end

  def unset_error_message
    self.error_message = nil # todo
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
  def superfeedr?()       @agent.to_s  =~ /superfeedr/i                 end
  def google?()           @agent.to_s  =~ /google/i                     end
  def yahoo?()            @agent.to_s  =~ /yahoo/i                      end
  def yandex?()           @agent.to_s  =~ /yandex/i                     end
  def baidu?()            @agent.to_s  =~ /baidu/i                      end
  def searchengine?()
    @agent.to_s  =~ /\b(Baidu|Gigabot|Googlebot|libwww-perl|lwp-trivial|msnbot|SiteUptime|Slurp|WordPress|ZIBB|ZyBorg|Yahoo|bing|superfeedr)\b/i
  end

  module ClassMethods
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

    def exists? sessid
      sess = new sessid: sessid
      sess.exists?
    end

    def load sessid
      Familia.ld "[LOAD] Loading session #{sessid}"
      sess = from_redis(sessid)
      Familia.ld " got session #{sess.sessid}"
      unless sess.nil?
        add(sess) # make sure this sess is in the values set
        sess
      end
      # Returns sess or nil
    end

    def create ipaddress, custid, useragent=nil
      sess = new ipaddress: ipaddress, custid: custid, useragent: useragent

      Familia.ld "[Session.create] Creating new session #{sess}"

      # Save immediately
      sess.save

      add sess # to the @values sorted set
      sess
    end

    def generate_id
      input = SecureRandom.hex(32)  # 16=128 bits, 32=256 bits
      # Not using gibbler to make sure it's always SHA256
      Digest::SHA256.hexdigest(input).to_i(16).to_s(36) # base-36 encoding
    end
  end

  extend ClassMethods
end
