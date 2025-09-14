# lib/onetime/models/customer/features/legacy_secrets_fields.rb

module V2::Customer::Features
  module LegacySecretsFields

    V2::Customer.add_feature self, :legacy_secrets_fields

    def self.included(base)
      OT.ld "[#{name}] Included in #{base}"
      base.extend ClassMethods
      base.include InstanceMethods
    end

    module ClassMethods
    end

    module InstanceMethods
      def metadata_list
        metadata.revmembers.collect do |key|
          V2::Metadata.load(key)
        rescue Onetime::RecordNotFound => ex
          OT.le "[metadata_list] Error: #{ex.message} (#{key} / #{custid})"
        end.compact
      end

      def add_metadata(obj)
        metadata.add OT.now.to_i, obj.key
      end
    end

  end
end
