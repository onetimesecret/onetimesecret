# apps/api/v2/models/customer/increment_field.rb

module V2
  module Models
    module Features
      #
      #
      module IncrementField


        def self.included(base)
          OT.ld "[#{name}] Included in #{base}"
          base.extend ClassMethods
          base.include InstanceMethods
        end

        module ClassMethods
        end

        module InstanceMethods

          def increment_field(field)
            if anonymous?
              whereami = caller(1..4)
              OT.le "[increment_field] Refusing to increment #{field} for anon customer #{whereami}"
              return
            end

            # Taking the module Approach simply to keep it out of this busy Customer
            # class. There's a small benefit to being able grep for "cust.method_name"
            # which this approach affords as well. Although it's a small benefit.
            self.class.increment_field(self, field)
          end

        end

        Familia::Base.add_feature self, :increment_field
      end

    end
  end
end
