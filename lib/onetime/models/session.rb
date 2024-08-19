
require_relative 'mixins/session_messages'

class Onetime::Session < Familia::Horreum
  include Onetime::Models::RateLimited


  db 1
  ttl 20.minutes
  prefix :session

  feature :safe_dump

  class_sorted_set :values, key: "onetime:session"

  identifier :sessid

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
  #
  attr_accessor :disable_auth

  def init
    # This regular attribute that gets set on each request (if necessary). When
    # true this instance will report authenticated? -> false regardless of what
    # the authenticated field is set to.
    @disable_auth = false

    # Don't call the sessid accessor in here. We intentionally allow
    # instantiating a session without a sessid. It's a distinction
    # from create which generates an sessid _and_ saves.
    @sessid ||= nil

    OT.ld "[Session.init] Initialized session #{self}"
  end

  def sessid
    @sessid ||= self.class.generate_id
    @sessid
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
    self.shrimp! self.class.generate_id if self.shrimp.to_s.empty?
    self.shrimp
  end

  def clear_shrimp!
    hdel! :shrimp
    nil
  end

  def authenticated?
    !disable_auth && authenticated.to_s == 'true'
  end

  def anonymous?
    disable_auth || sessid.to_s.to_sym == :anon || sessid.to_s.empty?
  end

  def load_customer
    return OT::Customer.anonymous if anonymous?
    cust = OT::Customer.load custid
    cust.nil? ? OT::Customer.anonymous : cust
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

    def create ipaddress, custid, useragent=nil
      sess = new ipaddress: ipaddress, custid: custid, useragent: useragent

      OT.ld "[Session.create] Creating new session #{sess}"

      sess.save
      add sess # to the class-level values relation (sorted set)
      sess
    end

    def generate_id
      input = SecureRandom.hex(32)  # 16=128 bits, 32=256 bits
      # Not using gibbler to make sure it's always SHA256
      Digest::SHA256.hexdigest(input).to_i(16).to_s(36) # base-36 encoding
    end
  end

  # Mixin Placement for Field Order Control
  #
  # We include the SessionMessages mixin at the end of this class definition
  # for a specific reason related to how Familia::Horreum handles fields.
  #
  # In Familia::Horreum subclasses (like this Session class), fields are processed
  # in the order they are defined. When creating a new instance with Session.new,
  # any provided positional arguments correspond to these fields in the same order.
  #
  # By including SessionMessages last, we ensure that:
  # 1. Its additional fields appear at the end of the field list.
  # 2. These fields don't unexpectedly consume positional arguments in Session.new.
  #
  include Onetime::Models::SessionMessages

  extend ClassMethods
end
