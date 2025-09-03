# apps/api/v2/models/management/customer_management.rb

module V2
  # Customer Model - Class Methods
  #
  class Customer < Familia::Horreum
    module Management
      attr_reader :values

      def create(custid, email = nil)
        raise Onetime::Problem, 'custid is required' if custid.to_s.empty?
        raise Onetime::Problem, 'Customer exists' if exists?(custid)

        cust        = new custid: custid, email: email || custid, role: 'customer'
        cust.planid = 'basic'
        OT.ld "[create] custid: #{custid}, #{cust.safe_dump}"
        cust.save
        add cust
        cust
      end

      def anonymous
        new('anon').freeze
      end

      def add(cust)
        values.add OT.now.to_i, cust.identifier
      end

      def all
        values.revrangeraw(0, -1).collect { |identifier| load(identifier) }
      end

      def recent(duration = 30.days, epoint = OT.now.to_i)
        spoint = OT.now.to_i - duration
        values.rangebyscoreraw(spoint, epoint).collect { |identifier| load(identifier) }
      end

      def global
        @global ||= from_identifier(:GLOBAL) || create(:GLOBAL)
        @global
      end

      # Generate a unique session ID with 32 bytes of random data
      # @return [String] base-36 encoded random string
      def generate_id
        Familia.generate_id
      end
    end

    # Customer Management
    #
    # e.g. Customer.create, Customer.all, Customer.add
    extend Management
  end
end
