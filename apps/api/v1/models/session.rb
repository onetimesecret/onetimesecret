# apps/api/v1/models/session.rb

module V1
  class Session < Familia::Horreum

    feature :safe_dump
    feature :expiration

    ttl 20.minutes
    prefix :session

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

    field :shrimp # as string?

    # We check this field in check_referrer! but we rely on this field when
    # receiving a redirect back from Stripe subscription payment workflow.
    field :referrer

    @safe_dump_fields = [
      { :identifier => ->(obj) { obj.identifier } },
      :sessid,
      :external_identifier,
      :authenticated,
      :stale,
      :created,
      :updated,
    ]

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

    def external_identifier
      @external_identifier ||= OT::Utils.generate_id
    end

    def short_identifier
      identifier.slice(0, 12)
    end

    def stale?
      self.stale.to_s == 'true'
    end

    def replace!
      @custid ||= self.custid
      newid = self.class.generate_id

      # Remove the existing session key from Redis
      if exists?
        begin
          self.delete!
        rescue => ex
          OT.le "[Session.replace!] Failed to delete key #{rediskey}: #{ex.message}"
        end
      end

      # This update is important b/c it ensures that the
      # data gets written to redis.
      self.sessid = newid

      # Familia doesn't automatically keep the key in sync with the
      # identifier field. We need to do it manually. See #860.
      self.key = self.sessid

      save

      sessid
    end

    def shrimp? guess
      shrimp = self.shrimp.to_s
      guess = guess.to_s
      OT.ld "[Sess#shrimp?] Checking with a constant time comparison"
      (!shrimp.empty?) && Rack::Utils.secure_compare(shrimp, guess)
    end

    def add_shrimp
      # Shrimp is removed each time it's used to prevent replay attacks. Here
      # we only add it if it's not already set ao that we don't accidentally
      # dispose of perfectly good piece of shrimp. Because of this guard, the
      # method is idempotent and can be called multiple times without side effects.
      self.shrimp! self.class.generate_id if self.shrimp.to_s.empty?
      self.shrimp # fast writer bang methods don't return the value
    end

    def replace_shrimp!
      self.shrimp! self.class.generate_id
    end

    def authenticated?
      !disable_auth && authenticated.to_s == 'true'
    end

    def anonymous?
      disable_auth || sessid.to_s == 'anon' || sessid.to_s.empty?
    end

    def load_customer
      return V1::Customer.anonymous if anonymous?
      cust = V1::Customer.load custid
      cust.nil? ? V1::Customer.anonymous : cust
    end

    module ClassMethods
      attr_reader :values

      # Add session to tracking set and clean up old entries
      # @param sess [Session] session to add
      # @return [void]
      def add sess
        self.values.add OT.now.to_i, sess.identifier
        self.values.remrangebyscore 0, OT.now.to_i-2.days
      end

      # Get all tracked sessions
      # @return [Array<Session>] all sessions in reverse chronological order
      def all
        self.values.revrangeraw(0, -1).collect { |identifier| load(identifier) }
      end

      # Get sessions within specified time duration
      # @param duration [ActiveSupport::Duration] time period to look back (default: 30 days)
      # @return [Array<Session>] sessions within the duration
      def recent duration=30.days
        spoint, epoint = OT.now.to_i-duration, OT.now.to_i
        self.values.rangebyscoreraw(spoint, epoint).collect { |identifier| load(identifier) }
      end

      # Create and save a new session
      # @param ipaddress [String] client IP address
      # @param custid [String] customer ID
      # @param useragent [String, nil] client user agent string
      # @return [Session] the created session
      def create ipaddress, custid, useragent=nil
        sess = new ipaddress: ipaddress, custid: custid, useragent: useragent

        sess.save
        add sess # to the class-level values relation (sorted set)
        sess
      end

      # Generate a unique session ID with 32 bytes of random data
      # @return [String] base-36 encoded SHA256 hash
      def generate_id
        input = SecureRandom.hex(32)  # 16=128 bits, 32=256 bits
        Digest::SHA256.hexdigest(input).to_i(16).to_s(36) # base-36 encoding
      end
    end

    extend ClassMethods
  end
end
