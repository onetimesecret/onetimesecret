# apps/api/v1/controllers/class_methods.rb
#
# frozen_string_literal: true

require 'v1/refinements'

module V1

  # FlexibleHashAccess is a refinement for the Hash class that enables
  # the use of either strings or symbols interchangeably when
  # retrieving values from a hash.
  #
  # @see receipt_hsh method
  #
  using FlexibleHashAccess

  module Controllers
    module ClassMethods
      # Translate v0.24 state values back to v0.23.4 vocabulary for V1
      # clients. See issue #2619 for rationale and mapping details.
      #
      #   previewed -> viewed   (renamed in v0.24)
      #   shared    -> new      (new in v0.24, nearest v0.23.4 equivalent)
      #   revealed  -> received (new in v0.24, nearest v0.23.4 equivalent)
      #
      V1_STATE_MAP = {
        'previewed' => 'viewed',
        'shared'    => 'new',
        'revealed'  => 'received',
      }.freeze

      # Translate a single state value from v0.24 to v0.23.4 vocabulary.
      # Unknown states pass through unchanged.
      #
      # @param state [String] The v0.24 state value
      # @return [String] The v0.23.4 equivalent
      def translate_v1_state(state)
        V1_STATE_MAP.fetch(state, state)
      end

      # Enforce V1 wire types on a response hash. [#2618]
      #
      # Ensures every field in a V1 response has the exact type that
      # v0.23.x clients expect, regardless of what upstream code
      # supplies. This is the single enforcement point — call it on
      # the finished hash right before returning from receipt_hsh.
      #
      # Type contracts:
      #   created, updated, received  -> Integer (Unix epoch)
      #   ttl, metadata_ttl, secret_ttl -> Integer (seconds)
      #   passphrase_required          -> true | false (boolean)
      #   recipient                    -> Array of Strings
      #   custid, metadata_key, secret_key, state, share_domain, value -> String
      #
      # @param hsh [Hash] The V1 response hash (mutated in place)
      # @return [Hash] The same hash, with types enforced
      #
      def coerce_v1_types(hsh)
        # Integer fields: timestamps and TTLs
        %w[created updated received ttl metadata_ttl secret_ttl].each do |key|
          next unless hsh.key?(key)
          hsh[key] = hsh[key].to_i
        end

        # Boolean field: passphrase_required must be true/false, never
        # a truthy string like "true" or "1".
        if hsh.key?('passphrase_required')
          val = hsh['passphrase_required']
          hsh['passphrase_required'] = if val.is_a?(String)
                                         !val.empty? && val != '0' && val != 'false'
                                       else
                                         !!val
                                       end
        end

        # Array field: recipient must always be an Array of Strings
        if hsh.key?('recipient')
          hsh['recipient'] = [hsh['recipient']]
            .flatten
            .compact
            .map(&:to_s)
            .reject(&:empty?)
        end

        # String fields: ensure nil doesn't leak as JSON null
        %w[custid metadata_key secret_key state share_domain value].each do |key|
          next unless hsh.key?(key)
          hsh[key] = hsh[key].to_s
        end

        hsh
      end

      # V1 Response Shaping — receipt_hsh [#2615, #2619]
      #
      # Transforms a Receipt (which uses v0.24 vocabulary internally)
      # into a hash using v0.23.x field names. Every V1 endpoint that
      # returns receipt data MUST use this method, and callers MUST
      # pass :custid => cust.email so that the response contains the
      # email address (not the internal UUID).
      #
      # Field mapping (v0.24 internal -> v0.23.x V1 response):
      #   identifier         -> metadata_key
      #   secret_identifier  -> secret_key
      #   has_passphrase     -> passphrase_required
      #   recipients         -> recipient (singular, array)
      #   receipt_ttl        -> metadata_ttl (actual seconds remaining)
      #   secret_value       -> value
      #   share_domain nil   -> '' (empty string, never null)
      #
      # Timestamp fallback:
      #   received timestamp -> falls back to revealed if empty (v0.24
      #   sets revealed!, not the deprecated received field)
      #
      # @param md [Receipt] The receipt object to process
      # @param opts [Hash] Options — :custid (email), :secret_ttl, :value,
      #   :passphrase_required
      # @return [Hash] V1-shaped response hash with string keys
      #
      def receipt_hsh md, opts={}

        # The to_h method comes from Familia::Horreum which is concerned with
        # preparing values for storage in the db. As a result, the hash returned
        # has had its values passed through `serialize_value` where everything becomes
        # a string. e.g. nil becomes ''. We not only allow but encourage this
        # behaviour since the values will become strings in Redis anyway so
        # better to be explicit about it.
        hsh = md.to_h

        # NOTE: This is a workaround for limitation in Familia where we can't add
        # fields that clash with reserved keywords like ttl, db, etc. For the v1
        # API, "ttl" is the requested value (i.e. the value of the ttl param when
        # the secret was created). Although this is getting the value from a
        # different field than the 0.16.x and earlier, it reads better (as in "the
        # secret has a ttl of 123") vs an ambiguous field called just ttl. It's
        # just confusing with the API response fields where `secret_ttl` is the
        # real value.
        #
        # Also note that the ttl used for metadata at creation time is secret_ttl*2
        # so that the creator has time to keep retreiving them metadata after the
        # secret itself has expired. Otherwise there'd be no record of whether the
        # secret was seen or not.
        receipt_ttl = md.secret_ttl&.to_i

        # Show the secret's actual real ttl as of now if we have it.
        secret_realttl = opts[:secret_ttl]&.to_i

        # md.current_expiration is a db command method. This makes a call to the db server
        # to get the current value of the ttl for the metadata object. This is the
        # actual time left before the metadata object is deleted from the db server.
        #
        # For the v1 API, this real value is what gets returned as "receipt_ttl". If
        # you don't find that confusing, take another look through the code.
        receipt_realttl = md.current_expiration&.to_i

        recipient = [hsh.fetch('recipients', nil)]
          .flatten
          .compact
          .reject(&:empty?)
          .uniq

        owner_id_val = hsh.fetch('owner_id', nil)
        secret_id_val = hsh.fetch('secret_identifier', nil)

        # V1 compat: resolve custid to email address.
        # In v0.24, owner_id stores Customer objid (UUID). Legacy custid stored email.
        # Priority: opts[:custid] (caller-supplied email) > v1_custid (migrated) > custid (legacy).
        # Fallback: anonymous secrets return "anon" (not nil) to match v0.23 behavior.
        # In v0.23, every receipt had a custid — unauthenticated ones used "anon".
        v1_custid = opts[:custid] || hsh.fetch('v1_custid', nil)
        v1_custid = hsh.fetch('custid', nil) if v1_custid.nil? || v1_custid.to_s.empty?
        v1_custid = 'anon' if v1_custid.nil? || v1_custid.to_s.empty?

        raw_state = hsh.key?('state') ? hsh['state'] : 'new'

        ret = {
          'custid' => v1_custid,
          'metadata_key' => md.identifier,
          'secret_key' => (secret_id_val && !secret_id_val.empty? ? secret_id_val : hsh.fetch('secret_key', '')).to_s,
          'ttl' => receipt_ttl, # static value from database hash field
          'metadata_ttl' => receipt_realttl, # actual number of seconds left to live
          'secret_ttl' => secret_realttl, # ditto, actual number
          'state' => translate_v1_state(raw_state),
          'updated' => hsh.fetch('updated', nil)&.to_i,
          'created' => hsh.fetch('created', nil)&.to_i,
          # V1 compat: fall back to `revealed` timestamp if `received` is empty.
          # In v0.24, revealed! sets `revealed` (not the deprecated `received` field).
          'received' => (hsh.fetch('received', nil).to_s.empty? ? hsh.fetch('revealed', nil) : hsh.fetch('received', nil)).to_i,
          'recipient' => recipient.compact,
          'share_domain' => hsh.fetch('share_domain', nil) || '',
        }

        if ret['state'] == 'received'
          ret.delete 'secret_ttl'
          ret.delete 'secret_key'
        else
          ret.delete 'received'
        end
        ret['value'] = opts[:value] if opts[:value]
        if !opts[:passphrase_required].nil?
          ret['passphrase_required'] = opts[:passphrase_required]
        end
        coerce_v1_types(ret)
      end

    end
  end
end
