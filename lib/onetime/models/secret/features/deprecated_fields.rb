# lib/onetime/models/secret/features/deprecated_fields.rb

module Onetime::Secret::Features
  module DeprecatedFields

    Familia::Base.add_feature self, :deprecated_fields

    def self.included(base)
      OT.ld "[features] #{base}: #{name}"

      base.extend ClassMethods
      base.include InstanceMethods

      # NOTE: this field is a nullop. It's only populated if a value was entered
      # into a hidden field which is something a regular person would not do.
      base.field :token
    end

    module ClassMethods
    end

    module InstanceMethods
    end

  end
end
