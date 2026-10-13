# lib/onetime/models/custom_domain/identity_guard.rb
#
# frozen_string_literal: true

module Onetime
  class CustomDomain < Familia::Horreum
    # Keeps the canonical display-domain claim in step with what is stored.
    #
    # canonical_display_domain_index holds one entry per DNS name (the A-label
    # form), so the Unicode and A-label spellings of a name cannot both be
    # registered. create! takes that claim before it saves. This module covers
    # every other write:
    #
    # - A full write (save, commit_fields, save_if_not_exists!) of a record
    #   that is not stored yet claims the canonical name first, and refuses
    #   when the name belongs to another record or has no A-label form. A
    #   claim this write created is released again if the write does not
    #   land. create! has already claimed the name, so here the claim is
    #   :owned and stays create!'s to release.
    # - A full write of a stored record passes through unchanged when its
    #   identity fields match what is stored, without reading the canonical
    #   index. Records registered before the index existed have no entry and
    #   keep saving normally. When the identity fields differ, the write is
    #   refused: there is no rename.
    # - atomic_write is refused for a record that is not stored yet, and
    #   refuses an identity change made inside its block.
    # - Partial writes (save_fields, multi_field_update,
    #   multi_field_fast_write, the fast writers such as display_domain!) are
    #   refused when they name an identity field. Others pass through.
    #
    # Stored values are read with HMGET and compared with the in-memory
    # values. Dirty tracking cannot be used: new and the loaders set fields
    # and then clear the dirty flags.
    #
    # Raw hash commands (hset, hmset, remove_field) are not guarded: they are
    # the plumbing the writers above use inside their own transactions.
    #
    # Prepended so the fast writers Familia generates for each field can be
    # wrapped, and so the guard runs before CustomDomain#save's own checks.
    module IdentityGuard
      # The fields derived from, or equal to, the domain name.
      IDENTITY_FIELDS = [:display_domain, :base_domain, :subdomain, :trd, :tld, :sld].freeze

      def save(...)
        guard_identity_full_write { super }
      end

      def commit_fields(...)
        guard_identity_full_write { super }
      end

      def save_if_not_exists!(...)
        guard_identity_full_write { super }
      end

      def atomic_write(...)
        return super if Fiber[:familia_transaction] # Familia refuses the nesting itself

        stored = stored_identity
        if stored.nil?
          raise Onetime::Problem,
            'A custom domain is created with create! or save, not atomic_write'
        end

        super do
          result = yield
          # Inside the MULTI: compares with the values read above, no reads here.
          refuse_identity_change!(stored)
          result
        end
      end

      def save_fields(*names, **)
        refuse_identity_partial_write!(names)
        super
      end

      def multi_field_update(**fields)
        refuse_identity_partial_write!(fields.keys - [:update_expiration])
        super
      end

      def multi_field_fast_write(**fields)
        refuse_identity_partial_write!(fields.keys - [:update_expiration])
        super
      end

      IDENTITY_FIELDS.each do |name|
        # With no value the fast writer is a read (HGET); only a write is refused.
        define_method(:"#{name}!") do |*args|
          refuse_identity_partial_write!([name]) unless args.empty? || args.first.nil? || args.first.is_a?(Redis::Future)
          super(*args)
        end
      end

      private

      def guard_identity_full_write
        # Familia refuses a save inside a transaction or pipeline; reads here
        # would only return futures.
        return yield if Fiber[:familia_transaction] || Fiber[:familia_pipeline]

        stored = stored_identity
        if stored
          refuse_identity_change!(stored)
          return yield
        end

        # Not stored yet. A blank name has nothing to claim (save refuses it).
        return yield if display_domain.to_s.empty?

        canonical, created = claim_canonical_for_new_record!
        begin
          result = yield
        rescue StandardError
          release_claim_unless_stored(canonical) if created
          raise
        end
        release_claim_unless_stored(canonical) if created && !write_landed?(result)
        result
      end

      # Releases a claim this write took, unless the record was stored after
      # all: a save can raise after its EXEC landed (the objid/extid lookup
      # writes run after it), and a failed MultiResult may still have
      # written the hash. When existence cannot be read the claim is kept,
      # so the name stays taken rather than open to a second record.
      def release_claim_unless_stored(canonical)
        return if exists?

        self.class.canonical_display_domain_index.release_field(canonical, identifier)
      rescue StandardError => ex
        OT.le "[CustomDomain] Kept the canonical claim for #{extid}: #{ex.class}: #{ex.message}"
      end

      # @return [Hash{Symbol => String, nil}, nil] raw stored identity values,
      #   or nil when the record is not stored
      def stored_identity
        raw = dbclient.hmget(dbkey, *IDENTITY_FIELDS.map(&:to_s))
        return nil if raw.all?(&:nil?) && !exists?

        IDENTITY_FIELDS.zip(raw).to_h
      end

      def refuse_identity_change!(stored)
        changed = IDENTITY_FIELDS.reject { |name| stored_value_matches?(stored[name], send(name), name) }
        return if changed.empty?

        OT.le "[CustomDomain] Refused identity change on #{extid}: #{changed.join(', ')}"
        raise Onetime::Problem, 'The domain name of a custom domain cannot be changed'
      end

      def refuse_identity_partial_write!(names)
        named = names.map(&:to_sym) & IDENTITY_FIELDS
        return if named.empty?

        raise Onetime::Problem,
          "#{named.join(', ')} can only be written by create! or a full save"
      end

      # A stored value (raw HGET string) matches the in-memory value when it is
      # its serialised form, the plain string a pre-JSON record stored, or
      # what loading that raw value produces. The last covers a pre-JSON
      # plain string that reads as a JSON number: "1e100" loads as 1.0e+100
      # and "1.50" as 1.5, so neither of the first two forms matches. It is
      # checked last because decoding a plain string that is not JSON logs.
      def stored_value_matches?(raw, value, name)
        return value.nil? if raw.nil?

        raw == serialize_value(value) ||
          raw == value.to_s ||
          deserialize_value(raw, field_name: name) == value
      end

      # @return [Array(String, Boolean)] canonical name, and whether this call
      #   created the claim (and so must release it if the write fails)
      # @raise [Onetime::Problem] when another record holds the name, or the
      #   name has no A-label form
      def claim_canonical_for_new_record!
        canonical, claim = self.class.claim_canonical_display_domain(display_domain, identifier)
        return [canonical, claim == :created] if [:created, :owned].include?(claim)

        raise Onetime::Problem, 'Domain already registered'
      rescue Onetime::DomainValidation::AsciiHostname::ConversionError => ex
        raise Onetime::Problem, ex.message
      end

      def write_landed?(result)
        return result.successful? if result.is_a?(Familia::MultiResult)

        result == true
      end
    end
  end
end
