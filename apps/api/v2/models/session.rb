# apps/api/v2/models/session.rb

# NOTE: Due to a limitation in Familia::Horreum (when a field is defined its
# read accessor is created the same way regardless of whether there was an
# existing accessor), the model definitions must live at the top. More
# specifically, the horreum field definitions must be loaded prior to the
# model instance methods.
require_relative 'definitions/session_definition'

module V2
  class Session < Familia::Horreum
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
      @external_identifier ||= OT::Utils.generate_id
    end

    def to_s
      "#{sessid}/#{external_identifier}"
    end

    def stale?
      stale.to_s == 'true'
    end

    def replace!
      @custid ||= custid
      newid = self.class.generate_id

      # Remove the existing session key from Redis
      if exists?
        begin
          delete!
        rescue StandardError => e
          OT.le "[Session.replace!] Failed to delete key #{rediskey}: #{e.message}"
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
  end
end

require_relative 'management/session_management'
