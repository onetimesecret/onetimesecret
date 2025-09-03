# apps/api/v2/models/secret/features/secret_deprecated_fields.rb

module V2
  module Models
    module Features
      module SecretDeprecatedFields
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

        Familia::Base.add_feature self, :secret_deprecated_fields
      end
    end
  end
end
