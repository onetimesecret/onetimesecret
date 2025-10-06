# apps/api/v2/models/features/increment_field.rb

module Onetime
  module Models
    module Features
      module IncrementField

        Familia::Base.add_feature self, :increment_field

        def self.included(base)
          OT.ld "[#{name}] Included in #{base}"
          base.extend ClassMethods
          base.include InstanceMethods
        end

        module ClassMethods

          # fobj - an instance of a Familia::Horreum object
          def increment_field(fobj, field)
            return if fobj.global?

            current_value = fobj.send(field)
            OT.info "[increment_field] fobj.#{field} is #{current_value} for #{fobj}"

            fobj.increment field
          rescue Redis::CommandError => ex
            # For whatever reason, the database throws an error when trying to
            # increment a non-existent hashkey field (rather than setting
            # it to 1): "ERR hash value is not an integer"
            OT.le "[increment_field] Redis error (#{current_value}): #{ex.message}"

            # So we'll set it to 1 if it's empty. It's possible we're here
            # due to a different error, but this value needs to be
            # initialized either way.
            fobj.send("#{field}!", 1) if current_value.to_i.zero? # nil and '' cast to 0
          end
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

      end
    end
  end
end
