# apps/api/v2/models/management/session_management.rb

module V2
  class Session < Familia::Horreum
    module Management
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
        OT::Utils.generate_id
      end
    end

    extend Management
  end
end
