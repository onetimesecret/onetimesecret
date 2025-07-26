# apps/api/v2/models/session/class_methods.rb

module V2
  class Session < Familia::Horreum

    module ClassMethods
      # @return [Object] the class-level values sorted set
      attr_reader :values

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

      # Generate a unique session ID with 32 bytes of random data
      # @return [String] base-36 encoded random string
      def generate_id
        OT::Utils.generate_id
      end
    end

    extend ClassMethods
  end
end
