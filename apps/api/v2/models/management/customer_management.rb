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

        cust = new custid: custid, email: email || custid, role: 'customer'
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

      def increment_field(cust, field)
        return if cust.global?

        curval = cust.send(field)
        OT.info "[increment_field] cust.#{field} is #{curval} for #{cust}"

        cust.increment field
      rescue Redis::CommandError => e
        # For whatever reason, redis throws an error when trying to
        # increment a non-existent hashkey field (rather than setting
        # it to 1): "ERR hash value is not an integer"
        OT.le "[increment_field] Redis error (#{curval}): #{e.message}"

        # So we'll set it to 1 if it's empty. It's possible we're here
        # due to a different error, but this value needs to be
        # initialized either way.
        cust.send("#{field}!", 1) if curval.to_i.zero? # nil and '' cast to 0
      end

      # Generate a unique session ID with 32 bytes of random data
      # @return [String] base-36 encoded random string
      def generate_id
        OT::Utils.generate_id
      end
    end

    # Customer Management
    #
    # e.g. Customer.create, Customer.all, Customer.add
    extend Management
  end
end
