# lib/onetime/models/features/required_fields.rb
#
# frozen_string_literal: true

module Onetime
  module Models
    module Features
      module RequiredFields
        Familia::Base.add_feature self, :required_fields, depends_on: [:relationships, :object_identifier]

        def self.included(base)
          OT.ld "[features] RequiredFields: Relationships included in #{base}"
          base.extend ClassMethods

          base.field :created
          base.field :updated
        end

        module ClassMethods
          # TODO: Could the `base.field` calls live here? When the model class
          # extends this module, do class-level function calls work the same
          # way they would if they were in the model itself? e.g.
          #
          #     field :created
          #     field :updated
          #
          # I think it would work since extend doesn't just add methods - it
          # also executes any top-level code in the module within the
          # extending class's context.
        end
      end
    end
  end
end
