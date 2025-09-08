# apps/api/v2/models/session.rb

module V2
  class Session < Familia::Horreum

    using Familia::Refinements::TimeLiterals

    feature :safe_dump
    feature :expiration

    default_expiration 20.minutes
    prefix :session

    class_sorted_set :values, dbkey: 'onetime:session'

    identifier_field :sessid

    field :ipaddress
    field :custid
    field :useragent
    field :stale
    field :sessid, on_conflict: :skip
    field :updated
    field :created
    field :authenticated
    field :external_identifier, on_conflict: :skip

    transient_field :favourite_salad # this will not persist to the database

    field :shrimp # as string?

    # We check this field in check_referrer! but we rely on this field when
    # receiving a redirect back from Stripe subscription payment workflow.
    field :referrer

    safe_dump_field :identifier, ->(obj) { obj.identifier }
    safe_dump_field :sessid
    safe_dump_field :external_identifier
    safe_dump_field :authenticated
    safe_dump_field :stale
    safe_dump_field :created
    safe_dump_field :updated

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

    def save
      @sessid ||= self.class.generate_id
      super
    end

    def sessid
      @sessid ||= self.class.generate_id
    end

    # Sessions often need IDs before save for cookies, logging, etc so
    # it's important to maintain the lazy generation of the session ID,
    # even in a case like this where the sessions convenient short
    # identifier is use before the full monty sessid.
    def short_identifier
      @short_identifier ||= sessid.slice(0, 12)
    end

    def external_identifier
      @external_identifier ||= Familia.generate_id
    end

    def to_s
      "#{sessid}/#{external_identifier}"
    end

    def stale?
      stale.to_s == 'true'
    end

    def replace!
      @custid ||= custid
      newid     = self.class.generate_id

      # Remove the existing session key from the database
      if exists?
        begin
          delete!
        rescue StandardError => ex
          OT.le "[Session.replace!] Failed to delete key #{dbkey}: #{ex.message}"
        end
      end

      # This update is important b/c it ensures that the
      # data gets written to the database.
      self.sessid = newid

      save

      sessid
    end

    def shrimp?(guess)
      shrimp = self.shrimp.to_s
      guess  = guess.to_s
      OT.ld '[Sess#shrimp?] Checking with a constant time comparison'
      !shrimp.empty? && Rack::Utils.secure_compare(shrimp, guess)
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
      attr_reader :values

      # Creates and persists a new session with full tracking.
      # The session is immediately saved to the database and added to the class-level
      # collection for management and cleanup operations.
      #
      # @param ipaddress [String] Client IP address
      # @param custid [String] Customer identifier
      # @param useragent [String, nil] User agent string
      # @return [Session] Saved and tracked session instance
      def create(ipaddress, custid, useragent = nil)
        sess = new ipaddress: ipaddress, custid: custid, useragent: useragent
        sess.save
        add sess # to the class-level values relation (sorted set)
        sess
      end

      # Creates an ephemeral (non-persistent) anonymous session for temporary use.
      # Unlike #create, this session is not saved to the database or tracked in the class
      # collection, making it suitable for:
      #
      # - Anonymous users who may not complete actions requiring persistence
      # - Temporary request correlation before determining if session should persist
      # - Reducing Redis writes for sessions that might be immediately discarded
      #
      # The session ID is generated immediately to support logging and debugging,
      # but can be saved later if needed via #save.
      #
      # @param useragent [String] User agent string for the session
      # @return [Session] Unsaved session instance with generated ID
      def create_ephemeral(useragent)
        sess = new(custid: 'anon', useragent: useragent)
        sess.sessid # Force ID generation for logging/correlation
        sess
      end

      def add(sess)
        values.add OT.now.to_i, sess.identifier
        values.remrangebyscore 0, OT.now.to_i - 2.days
      end

      def all
        values.revrangeraw(0, -1).collect { |identifier| load(identifier) }
      end

      def recent(duration = 30.days)
        spoint = OT.now.to_i - duration
        epoint = OT.now.to_i
        values.rangebyscoreraw(spoint, epoint).collect { |identifier| load(identifier) }
      end

      def generate_id
        Familia.generate_id
      end
    end

    include V2::Mixins::SessionMessages
    extend ClassMethods
  end
end
