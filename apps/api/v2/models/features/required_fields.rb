# apps/api/v2/models/features/required_fields.rb

module V2
  module Models
    module Features
      module RequiredFields
        def self.included(base)
          OT.ld "[RequiredFields] Relationships included in #{base}"
          base.extend ClassMethods
          # base.include InstanceMethods
        end

        module ClassMethods
        end

        Familia::Base.add_feature self, :required_fields, depends_on: [:relationships, :object_identifiers]
      end
    end
  end
end
