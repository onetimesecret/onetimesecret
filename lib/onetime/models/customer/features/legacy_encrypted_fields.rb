# lib/onetime/models/customer/features/legacy_encrypted_fields.rb

module Onetime::Customer::Features
  #
  #
  module LegacyEncryptedFields
    Familia::Base.add_feature self, :legacy_encrypted_fields

    def self.included(base)
      OT.ld "[#{name}] Included in #{base}"
      base.extend ClassMethods
      base.include InstanceMethods
    end

    module ClassMethods
    end

    module InstanceMethods
      def encryption_key
        Onetime::Secret.encryption_key OT.global_secret, custid
      end
    end
  end
end
