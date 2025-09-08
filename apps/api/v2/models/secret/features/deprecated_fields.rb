# apps/api/v2/models/secret/features/deprecated_fields.rb

module V2::Secret::Features
  module DeprecatedFields
    def self.included(base)
      OT.ld "[#{name}] Included in #{base}"
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

    Familia::Base.add_feature self, :deprecated_fields
  end
end
