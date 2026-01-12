# lib/onetime/models/customer/features/legacy_secrets_fields.rb
#
# frozen_string_literal: true

module Onetime::Customer::Features
  module LegacySecretsFields
    Onetime::Customer.add_feature self, :legacy_secrets_fields

    def self.included(base)
      OT.ld "[features] #{base}: #{name}"

      base.extend ClassMethods
      base.include InstanceMethods
    end

    module ClassMethods
    end

    module InstanceMethods
      def receipts_list
        receipts.revmembers.collect do |key|
          Onetime::Receipt.load(key)
        rescue Onetime::RecordNotFound => ex
          OT.le "[receipts_list] Error: #{ex.message} (#{key} / #{custid})"
        end.compact
      end
      alias metadata_list receipts_list # backward compatibility

      def add_receipt(obj)
        receipts.add obj.identifier
      end
      alias add_metadata add_receipt # backward compatibility
    end
  end
end
