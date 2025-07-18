# apps/api/v2/models/session.rb

require_relative 'mixins/session_messages'

module V2
  class Session < Familia::Horreum
  include V2::Mixins::RateLimited

  feature :safe_dump
  feature :expiration

  ttl 20.minutes
  prefix :session

  class_sorted_set :values, key: 'onetime:session'

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

  field :shrimp # as string?

  # We check this field in check_referrer! but we rely on this field when
  # receiving a redirect back from Stripe subscription payment workflow.
  field :referrer

  @safe_dump_fields = [
    { identifier: ->(obj) { obj.identifier } },
    :sessid,
    :external_identifier,
    :authenticated,
    :stale,
    :created,
    :updated,
  ].freeze

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
    @sessid ||= nil # rubocop:disable Naming/MemoizedInstanceVariableName
  end

  def sessid
    @sessid ||= self.class.generate_id
    @sessid
  end

  def to_s
    "#{sessid}/#{external_identifier}"
  end

  # The external identifier is used by the rate limiter to estimate a unique
  # client. We can't use the session ID b/c the request agent can choose to
  # not send cookies, or the user can clear their cookies (in both cases the
  # session ID would change which would circumvent the rate limiter). The
  # external identifier is now a randomly generated ID that remains consistent
  # for the session lifecycle, providing rate limiting without relying on
  # potentially unreliable data like IP addresses or customer IDs.
  #
  # To put it another way, the risk of colliding external identifiers is
  # acceptable for the rate limiter, but not for the session data. Acceptable
  # b/c the rate limiter is a temporary measure to prevent abuse, and the
  # worse case scenario is that a user is rate limited when they shouldn't be.
  # The session data is permanent and must be kept separate to avoid leaking
  # data between users.
  def external_identifier
    @external_identifier ||= self.class.generate_id
    @external_identifier
  end

  def short_identifier
    identifier.slice(0, 12)
  end

  def stale?
    stale.to_s == 'true'
  end

  def replace!
    @custid ||= custid
    newid     = self.class.generate_id

    # Remove the existing session key from Redis
    if exists?
      begin
        delete!
      rescue StandardError => ex
        OT.le "[Session.replace!] Failed to delete key #{rediskey}: #{ex.message}"
      end
    end

    # This update is important b/c it ensures that the
    # data gets written to redis.
    self.sessid = newid

    # Familia doesn't automatically keep the key in sync with the
    # identifier field. We need to do it manually. See #860.
    self.key = sessid

    save

    sessid
  end

  def shrimp?(guess)
    shrimp = self.shrimp.to_s
    guess  = guess.to_s
    OT.ld '[Sess#shrimp?] Checking with a constant time comparison'
    (!shrimp.empty?) && Rack::Utils.secure_compare(shrimp, guess)
  end

  def add_shrimp
    # Shrimp is removed each time it's used to prevent replay attacks. Here
    # we only add it if it's not already set ao that we don't accidentally
    # dispose of perfectly good piece of shrimp. Because of this guard, the
    # method is idempotent and can be called multiple times without side effects.
    replace_shrimp! if shrimp.to_s.empty?
    shrimp # fast writer bang methods don't return the value
  end

  def replace_shrimp!
    shrimp! self.class.generate_id
  end

  def authenticated?
    !disable_auth && authenticated.to_s == 'true'
  end

  def anonymous?
    disable_auth || sessid.to_s == 'anon' || sessid.to_s.empty?
  end

  def load_customer
    return V2::Customer.anonymous if anonymous?

    cust = V2::Customer.load custid
    cust.nil? ? V2::Customer.anonymous : cust
  end

  module ClassMethods
    # @return [Object] the class-level values sorted set
    attr_reader :values

    # Add session to the class-level sorted set and remove old entries
    # @param sess [Session] the session to add
    # @return [void]
    def add(sess)
      values.add OT.now.to_i, sess.identifier
      values.remrangebyscore 0, OT.now.to_i-2.days
    end

    # Retrieve all sessions from the sorted set
    # @return [Array<Session>] all sessions in reverse chronological order
    def all
      values.revrangeraw(0, -1).collect { |identifier| load(identifier) }
    end

    # Retrieve sessions within a specified duration
    # @param duration [ActiveSupport::Duration] time range to query (default: 30.days)
    # @return [Array<Session>] sessions within the specified duration
    def recent(duration = 30.days)
      spoint = OT.now.to_i-duration
      epoint = OT.now.to_i
      values.rangebyscoreraw(spoint, epoint).collect { |identifier| load(identifier) }
    end

    # Create and persist a new session
    # @param ipaddress [String] client IP address
    # @param custid [String] customer ID
    # @param useragent [String, nil] user agent string
    # @return [Session] the created session
    def create(ipaddress, custid, useragent = nil)
      sess = new ipaddress: ipaddress, custid: custid, useragent: useragent

      sess.save
      add sess # to the class-level values relation (sorted set)
      sess
    end

    # Generate a unique session ID with 32 bytes of random data
    # @return [String] base-36 encoded random string
    def generate_id
      OT::Utils.generate_id
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
  include V2::Mixins::SessionMessages

  extend ClassMethods
  end
end
