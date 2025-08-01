# apps/api/v2/models/management/session_management.rb

module V2
  class Session < Familia::Horreum

    module Management
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

    extend Management
  end
end
