# apps/api/v2/models/session.rb

require_relative 'mixins/session_messages'

module V2
  class Session < Familia::Horreum

    def sessid
      objid
    end

    def to_s
      "#{extid}"
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
  end
end
