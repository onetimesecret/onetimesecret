# lib/onetime/models/customer/features/deprecated_fields.rb
#
# frozen_string_literal: true

module Onetime::Customer::Features
  module DeprecatedFields
    using Familia::Refinements::TimeLiterals

    Familia::Base.add_feature self, :deprecated_fields

    # reset_secret is one string key written by two flows (password recovery
    # and account verification). A read-then-write from Ruby leaves a window
    # in which the other flow's write is lost, so the pointer is only ever
    # replaced or cleared by comparing it server-side (#4735 review, F6/F7).
    RESET_POINTER_SET_IF = <<~LUA
      local current = redis.call('GET', KEYS[1])
      if current == false then current = '' end
      if current ~= ARGV[1] then return 0 end
      if tonumber(ARGV[3]) > 0 then
        redis.call('SET', KEYS[1], ARGV[2], 'EX', ARGV[3])
      else
        redis.call('SET', KEYS[1], ARGV[2])
      end
      return 1
    LUA

    RESET_POINTER_DEL_IF = <<~LUA
      if redis.call('GET', KEYS[1]) ~= ARGV[1] then return 0 end
      return redis.call('DEL', KEYS[1])
    LUA

    def self.included(base)
      OT.ld "[features] #{base}: #{name}"

      base.extend ClassMethods
      base.include InstanceMethods

      base.field_group :deprecated_fields do
        base.field :sessid
        base.field :apitoken # TODO: use sorted set?
        # Epoch second of the last API key rotation (#regenerate_apitoken),
        # written in the same HSET as the new key. The watermark that retires
        # the v3 bearer tokens minted while the previous key was live
        # (#bearer_token_watermark); deliberately NOT last_password_update,
        # which also retires sessions: rotating a leaked key must not sign
        # the owner out of the browser they rotated it from.
        base.field :last_apitoken_update
        base.field :contributor

        # These were used for the old counter fields implementation. We can
        # remove these after v0.24 upgrade migrations which externalize the
        # counters to separate keys. @see counter_fields.rb
        # base.field :secrets_created # regular hashkey string field
        # base.field :secrets_burned
        # base.field :secrets_shared
        # base.field :emails_sent

        # Needed for data migration. Moved to Organization.
        base.field :stripe_customer_id       # Stripe Customer ID
        base.field :stripe_subscription_id   # Active Stripe Subscription ID
      end
    end

    module ClassMethods
      # Use Familia 2's generated class methods
      # def add(cust)
      #   instances.add cust.identifier, OT.now.to_i
      # end

      def all
        instances.revrangeraw(0, -1).collect { |identifier| load(identifier) }
      end

      def recent(duration = 30.days, epoint = OT.now.to_i)
        spoint = OT.now.to_i - duration
        instances.rangebyscoreraw(spoint, epoint).collect { |identifier| load(identifier) }
      end

      # Generate a unique session ID with 32 bytes of random data
      # @return [String] base-36 encoded random string
      def generate_id
        OT::Utils.generate_id
      end
    end

    module InstanceMethods
      def locale?
        !locale.to_s.empty?
      end

      def apitoken?(guess)
        apitoken.to_s == guess.to_s
      end

      # Replace the API key and stamp #last_apitoken_update in one write, so
      # no process can see the new key without the watermark that retires
      # the bearer tokens minted from the old one (an unstamped rotation
      # would leave a leaked key's tokens alive until they expire).
      #
      # The write is the two fields and nothing else: no TTL refresh on the
      # record or its relations (the former fast writer was a bare HSET, and
      # #destroy_requested sets a 365-day default_expiration right before
      # calling this without meaning to apply it here).
      #
      # @return [String] the new key
      def regenerate_apitoken
        self.apitoken             = Familia.generate_id
        self.last_apitoken_update = Familia.now.to_i
        save_fields(:apitoken, :last_apitoken_update, update_expiration: false)
        apitoken
      end

      # The instant a v3 bearer token must be issued strictly after, and is
      # refused at or before: the later of the two credential changes that
      # retire tokens, a password change (#last_password_update, the
      # watermark that retires sessions too) and an API key rotation
      # (#last_apitoken_update, which retires tokens only). One reader for
      # both the verifier (PasetoAuthStrategy#predates_credential_change?)
      # and the mint (V3::Logic::Auth::GenerateToken#issuance_time), so
      # the two cannot disagree about where the line is. 0 when neither
      # has been stamped.
      #
      # @return [Integer] epoch seconds
      def bearer_token_watermark
        [last_password_update.to_i, last_apitoken_update.to_i].max
      end

      def external_identifier
        raise OT::Problem, 'Anonymous customer has no external identifier' if anonymous?

        @external_identifier ||= Familia.generate_id # generate but don't save
        @external_identifier
      end

      def global?
        custid.to_s.eql?('GLOBAL')
      end

      # NOT named reset_secret?: Familia's `string :reset_secret` field
      # generates a zero-arity Customer#reset_secret? predicate directly on the
      # class, which shadows any same-named module method here — a one-arg call
      # then raises ArgumentError, which is exactly how the simple-mode reset
      # flow was breaking (valid_reset_secret! 500'd on every attempt).
      def matches_reset_secret?(secret)
        return false if secret.nil? || !secret.exists? || secret.identifier.to_s.empty?

        Rack::Utils.secure_compare(reset_secret.to_s, secret.identifier)
      end

      # Point reset_secret at `identifier`, but only while it still holds
      # `expected` ('' for an absent key). Runs server-side so the comparison
      # and the write are one step: a recovery request that lands between a
      # caller's read and this write keeps its pointer (#4735 review, F6
      # concurrent). Re-applies the pointer's 24h expiry on success.
      #
      # @param identifier [String] the secret to record
      # @param expected [String] the value the caller read and classified
      # @return [Boolean] true when the pointer was written
      def claim_reset_pointer(identifier, expected:)
        ttl    = reset_secret.default_expiration.to_i
        result = reset_secret.dbclient.eval(
          RESET_POINTER_SET_IF,
          keys: [reset_secret.dbkey],
          argv: [expected.to_s, identifier.to_s, ttl],
        )
        result == 1
      end

      # Clear reset_secret, but only while it still names `secret`. The
      # comparison and the delete are one server-side step, so a recovery
      # token recorded after the caller compared is never deleted by a
      # consumer of the older link (#4735 review, F7 concurrent). The Ruby
      # comparison first keeps the common non-matching reveal off the
      # scripting path.
      #
      # @param secret [Onetime::Secret] the secret being consumed
      # @return [Boolean] true when the pointer named the secret and is now gone
      def release_reset_pointer(secret)
        return false unless matches_reset_secret?(secret)

        result = reset_secret.dbclient.eval(
          RESET_POINTER_DEL_IF,
          keys: [reset_secret.dbkey],
          argv: [secret.identifier],
        )
        result == 1
      end

      def valid_reset_secret!(secret)
        if is_valid = release_reset_pointer(secret)
          OT.ld "[valid_reset_secret!] Reset secret is valid for #{custid} #{secret.shortid}"
          secret.delete!
        end
        is_valid
      end

      # Session management is now handled by Rack::Session middleware
      # This deprecated method has been removed as part of the migration
    end
  end
end
