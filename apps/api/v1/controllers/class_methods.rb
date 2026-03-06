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
      # Transforms a receipt into a structured hash with enhanced information.
      #
      # This method processes a receipt object and optional parameters to create
      # a comprehensive hash representation. It includes derived and calculated
      # values, providing a rich snapshot of the receipt and associated secret
      # state.
      #
      # @param md [Receipt] The receipt object to process
      # @param opts [Hash] Optional parameters to influence the output
      # @option opts [Integer, nil] :secret_ttl The actual TTL of the associated
      #   secret, if available
      #
      # @return [Hash] A structured hash containing metadata and derived
      #   information
      #
      # @note This method relies on the FlexibleHashAccess refinement for hash
      #   key access.
      #
      # @example Basic usage
      #   receipt = Receipt.new(key: 'abc123', custid: 'user@example.com')
      #   result = API.receipt_hsh(receipt)
      #   puts result[:custid] # => "user@example.com"
      #
      # @example With secret TTL provided
      #   result = API.receipt_hsh(receipt, secret_ttl: 3600)
      #   puts result[:secret_ttl] # => 3600
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
        v1_custid = opts[:custid] || hsh.fetch('v1_custid', nil)
        v1_custid = hsh.fetch('custid', nil) if v1_custid.nil? || v1_custid.to_s.empty?

        # Map v0.24.0 state values back to v0.23.x vocabulary for V1 compat.
        # Internally: previewed -> viewed, revealed -> received, shared -> new
        v1_state_map = { 'previewed' => 'viewed', 'revealed' => 'received', 'shared' => 'new' }.freeze
        raw_state = hsh.key?('state') ? hsh['state'] : 'new'

        ret = {
          'custid' => v1_custid,
          'metadata_key' => md.identifier,
          'secret_key' => (secret_id_val && !secret_id_val.empty? ? secret_id_val : hsh.fetch('secret_key', nil)),
          'ttl' => receipt_ttl, # static value from database hash field
          'metadata_ttl' => receipt_realttl, # actual number of seconds left to live
          'secret_ttl' => secret_realttl, # ditto, actual number
          'state' => v1_state_map.fetch(raw_state, raw_state),
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
        ret
      end

    end
  end
end
