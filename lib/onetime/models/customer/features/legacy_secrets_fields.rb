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
      def metadata_list
        metadata.revmembers.collect do |key|
          Onetime::Metadata.load(key)
        rescue Onetime::RecordNotFound => ex
          OT.le "[metadata_list] Error: #{ex.message} (#{key} / #{custid})"
        end.compact
      end

      def add_metadata(obj)
        metadata.add obj.identifier
      end
    end
  end
end
