# lib/onetime/models/secret/features/deprecated_fields.rb
#
# frozen_string_literal: true

module Onetime::Secret::Features
  module DeprecatedFields
    Familia::Base.add_feature self, :deprecated_fields

    def self.included(base)
      OT.ld "[features] #{base}: #{name}"

      base.extend ClassMethods
      base.include InstanceMethods

      base.field_group :deprecated_fields do
        base.field :share_domain
        base.field :verification
        base.field :custid
        base.field :metadata_key # do not add receipt_key; just use identifier
        base.field :truncated # boolean
        base.field :secret_key
      end
    end

    module ClassMethods
    end

    module InstanceMethods
    end
  end
end
