
module V2
  class StripeEvent < Familia::Horreum

    feature :safe_dump
    feature :expiration

    ttl 5.years
    prefix :stripeevent

    class_sorted_set :values, key: 'onetime:stripeevent:values'

    #identifier :eventid

    field :eventid
    field :custid
    field :message_response
    field :stripe_customer
    field :created
    field :updated

    @safe_dump_fields = [
      { identifier: ->(obj) { obj.identifier } },
      :eventid,
      :message_response,
      :stripe_customer,
      :created,
      :updated,
    ].freeze
    # e.g.
    #
    #  stripeevent:1234567890:object
    #
    def init
      @custid = custid.identifier if custid.is_a?(Familia::Base)
    end

    def identifier
      @eventid
    end

    def destroy! *args
      ret = super
      V2::StripeEvent.values.remove identifier
      ret
    end

    module ClassMethods
      attr_reader :values, :db

      # fobj is a familia object
      def add fobj
        self.values.add OT.now.to_i, fobj.identifier
        self.values.remrangebyscore 0, OT.now.to_i-5.years # keep 5 years of stripe activity
      end

      def all
        self.values.revrangeraw(0, -1).collect { |identifier| load(identifier) }
      end

      def recent duration = 48.hours
        spoint, epoint = OT.now.to_i-duration, OT.now.to_i
        self.values.rangebyscoreraw(spoint, epoint).collect { |identifier| load(identifier) }
      end

      def create(custid, secretid, message_response = nil)
        fobj = new custid: custid, secretid: secretid, message_response: message_response
        OT.ld "[StripeEvent.create] #{custid} #{secretid} #{message_response}"
        raise ArgumentError, "#{name} record exists #{rediskey}" if fobj.exists?

        fobj.apply_fields custid: custid, secretid: secretid, message_response: message_response
        fobj.save

        add fobj # to the @values sorted set
        fobj
      end

    end

    extend ClassMethods
  end
end
