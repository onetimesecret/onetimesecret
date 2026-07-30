# apps/api/v3/logic/receipt_shape.rb
#
# frozen_string_literal: true

module V3
  module Logic
    # V3 receipt wire-shape normalization (2026-07-29 API audit, items 5 and 7).
    #
    # The receipt safe_dump (lib/onetime/models/receipt/features/safe_dump_fields.rb)
    # is shared with V2, whose response contract is frozen. V3 is pre-release, so
    # the two known shape defects are corrected here — at the V3 serialization
    # boundary — instead of in the shared dump. V1/V2 output is untouched.
    #
    #   custid      Deprecated creator identifier (see
    #               receipt/features/deprecated_fields.rb — it lives in the
    #               :deprecated_fields group). New receipts only write owner_id,
    #               so custid is always null on post-migration records. Dropped
    #               from V3 entirely; owner_id is the canonical field.
    #
    #   recipients  safe_dump emits a String — the obscured recipient addresses
    #               joined with ', ' by Receipt#deliver_by_email, or '' when the
    #               secret was never emailed. V3 emits null when there are no
    #               recipients and an Array of strings otherwise, so a client
    #               never has to branch on the type. Splitting on ',' is safe
    #               after obscuring: an obscured address contains no comma.
    #
    # NOT touched here, deliberately — these are distinct fields, not aliases of
    # `recipients` (audit item 7): `details.recipient` is the request echo from
    # BaseSecretAction#process_recipient (already always an Array), and
    # `recipient_name` is an incoming-secrets display name (null for standard
    # secrets).
    #
    # Prepend, do not include: ShowMultipleReceipts defines success_data directly
    # on the V3 class, so an included module would sit behind it in the ancestor
    # chain and never run.
    module ReceiptShape
      # Receipt fields removed from every V3 payload.
      DEAD_FIELDS = [:custid].freeze

      def success_data
        ReceiptShape.normalize!(super)
      end

      class << self
        # Normalize every receipt hash reachable in a logic response envelope.
        #
        # Receipt records land in exactly two slots:
        #   data[:record]           single receipt (show / burn / update)
        #   data[:record][:receipt] the conceal / generate envelope
        #   data[:records]          receipt lists and the guest batch endpoint
        #
        # ListReceipts' details.revealed_receipts / details.pending_receipts are
        # partitions holding the same record objects, so in-place mutation of
        # data['records'] covers them too.
        #
        # @param data [Hash, nil] a logic success_data envelope (RevealSecret
        #   and ShowSecret can legitimately return nil).
        # @return [Hash, nil] the same object, mutated in place.
        def normalize!(data)
          return data unless data.is_a?(Hash)

          record = fetch(data, :record)
          if record.is_a?(Hash)
            nested = fetch(record, :receipt)
            normalize_receipt!(nested.is_a?(Hash) ? nested : record)
          end

          records = fetch(data, :records)
          records.each { |entry| normalize_receipt!(entry) } if records.is_a?(Array)

          data
        end

        # @param receipt [Hash] a serialized record. Left untouched unless it
        #   carries at least one field we own — secret safe_dumps share the
        #   :record slot (ShowSecret, RevealSecret, ListSecretStatus) and must
        #   pass through unchanged.
        # @return [Hash] the same object, mutated in place.
        def normalize_receipt!(receipt)
          return receipt unless receipt.is_a?(Hash)
          return receipt unless key?(receipt, :recipients) || key?(receipt, :custid)

          DEAD_FIELDS.each do |field|
            receipt.delete(field)
            receipt.delete(field.to_s)
          end

          if key?(receipt, :recipients)
            key          = receipt.key?(:recipients) ? :recipients : 'recipients'
            receipt[key] = normalize_recipients(receipt[key])
          end

          receipt
        end

        # @param value [String, Array, nil] the stored/serialized recipients.
        # @return [Array<String>, nil] null when there are no recipients.
        def normalize_recipients(value)
          entries = case value
                    when nil   then []
                    when Array then value
                    else value.to_s.split(',')
                    end

          entries = entries.map { |entry| entry.to_s.strip }.reject(&:empty?)
          entries.empty? ? nil : entries
        end

        private

        # Receipt hashes are symbol-keyed (safe_dump); envelopes are mixed —
        # ListReceipts builds a string-keyed envelope, the rest use symbols.
        def fetch(hash, key)
          hash.fetch(key) { hash[key.to_s] }
        end

        def key?(hash, key)
          hash.key?(key) || hash.key?(key.to_s)
        end
      end
    end
  end
end
