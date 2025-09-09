# apps/api/v2/models/customer/legacy_encrypted_fields.rb

module V2::Customer::Features
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
        V2::Secret.encryption_key OT.global_secret, custid
      end


    end


  end
end
