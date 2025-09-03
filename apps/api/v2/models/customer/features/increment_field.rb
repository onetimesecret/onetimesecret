# apps/api/v2/models/customer/increment_field.rb

module V2
  module Models
    module Features
      module IncrementField
        def self.included(base)
          OT.ld "[#{name}] Included in #{base}"
          base.extend ClassMethods
          base.include InstanceMethods

          base.field :secrets_created # regular hashkey string field
          base.field :secrets_burned
          base.field :secrets_shared
          base.field :emails_sent
        end

        module ClassMethods
          # TODO: The `cust` argument should now be `fobj` for familia object if
          # we want to move IncrementField to a common directory
          def increment_field(cust, field)
            return if cust.global?

            curval = cust.send(field)
            OT.info "[increment_field] cust.#{field} is #{curval} for #{cust}"

            cust.increment field
          rescue Redis::CommandError => ex
            # For whatever reason, the database throws an error when trying to
            # increment a non-existent hashkey field (rather than setting
            # it to 1): "ERR hash value is not an integer"
            OT.le "[increment_field] Redis error (#{curval}): #{ex.message}"

            # So we'll set it to 1 if it's empty. It's possible we're here
            # due to a different error, but this value needs to be
            # initialized either way.
            cust.send("#{field}!", 1) if curval.to_i.zero? # nil and '' cast to 0
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

        Familia::Base.add_feature self, :increment_field
      end
    end
  end
end
