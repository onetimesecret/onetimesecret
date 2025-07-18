# apps/api/v2/models/customer/class_methods.rb

require 'familia/horreum'

module V2

  # Customer Model - Class Methods
  #
  class Customer < Familia::Horreum

    module ClassMethods
      attr_reader :values

      def create(custid, email = nil)
        raise Onetime::Problem, 'custid is required' if custid.to_s.empty?
        raise Onetime::Problem, 'Customer exists' if exists?(custid)

        attrs = {
          custid: custid,
          email: email || custid,
          role: 'customer',
          api_version: 'v2',
          user_type: 'authenticated',
        }

        cust = new attrs
        cust.save
        add cust
        cust
      end



      def find_by_objid(objid)
        return nil if objid.to_s.empty?

        # self.obj

        Familia.ld "[.find_by_objid] #{self} from key #{objkey})"
        if Familia.debug?
          reference = caller(1..1).first
          Familia.trace :FIND_BY_OBJID, Familia.redis(uri), objkey, reference
        end

        find_by_key objkey
      end

      def add(cust)
        values.add OT.now.to_i, cust.identifier
        object_ids.add OT.now.to_f, cust.objid
      end

      def all
        object_ids.revrangeraw(0, -1).collect { |identifier| load(identifier) }
      end

      def recent(duration = 30.days, epoint = OT.now.to_i)
        spoint = OT.now.to_i-duration
        values.rangebyscoreraw(spoint, epoint).collect { |identifier| load(identifier) }
      end

      def anonymous
        new({ custid: 'anon', user_type: 'anonymous' }).freeze
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
      rescue Redis::CommandError => ex
        # For whatever reason, redis throws an error when trying to
        # increment a non-existent hashkey field (rather than setting
        # it to 1): "ERR hash value is not an integer"
        OT.le "[increment_field] Redis error (#{curval}): #{ex.message}"

        # So we'll set it to 1 if it's empty. It's possible we're here
        # due to a different error, but this value needs to be
        # initialized either way.
        cust.send("#{field}!", 1) if curval.to_i.zero? # nil and '' cast to 0
      end
    end

    extend ClassMethods
  end
end
