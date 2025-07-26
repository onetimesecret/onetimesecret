# apps/api/v2/models/features/relatable_object.rb

module V2
  module Features
    class RelatableObjectError < Familia::Problem; end

    # RelatableObject
    #
    # Provides the standard core object fields and methods.
    #
    module RelatableObject
      klass = self
      err_klass = V2::Features::RelatableObjectError

      def self.included(base)
        base.class_sorted_set :object_ids # rename relatable_object_ids?
        base.class_hashkey :owners
        base.field :objid
        base.field :extid
        base.field :api_version
        # base.identifier_field :objid
        base.extend(ClassMethods)

        # prepend ensures our methods execute BEFORE field-generated accessors
        # include would place them AFTER, but they'd never execute because
        # attr_reader doesn't call super - it just returns the instance variable
        #
        # Method lookup chain:
        #   prepend:  [InstanceMethods] → [Field Methods] → [Parent]
        #   include:  [Field Methods] → [InstanceMethods] → [Parent]
        #              (stops here, no super)    (never reached)
        #
        base.prepend(InstanceMethods)
      end

      module InstanceMethods
        # We lazily generate the object ID and external ID when they are first
        # accessed so that we can instantiate and load existing objects, without
        # eagerly generating them, only to be overridden by the storage layer.
        #
        def init
          super if defined?(super)  # Only call if parent has init

          @api_version ||= 'v2'
        end

        def objid
          @objid ||= begin # lazy loader
            generated_id = self.class.generate_objid
            # Using the attr_writer method ensures any future Familia
            # enhancements to the setter are properly invoked (as opposed
            # to directly assigning @objid).
            self.objid   = generated_id
          end
        end
        alias_method :object_identifier, :objid

        def extid
          @extid ||= begin # lazy loader
            generated_id = self.class.generate_extid
            self.extid   = generated_id
          end
        end
        alias_method :external_identifier, :extid

        # Check if the given customer is the owner of this domain
        #
        # @param cust [V2::Customer, String] The customer object or customer ID to check
        # @return [Boolean] true if the customer is the owner, false otherwise
        def owner?(related_object)
          self.class.relatable?(related_object) do
            # Check the hash (our objid => related_object's objid)
            owner_objid = self.class.owners.get(objid).to_s
            return false if owner_objid.empty?

            owner_objid.eql?(related_object.objid)
          end
        end

        def owned?
          # We can only have an owner if we are relatable ourselves.
          self.class.relatable?(self) do
            # If our object identifier is present, we have an owner
            self.class.owners.key?(objid)
          end
        end
      end

      module ClassMethods
        def relatable?(obj, &)
          is_relatable = obj.is_a?(klass)
          err_klass = V2::Features::RelatableObjectError
          raise err_klass, 'Not relatable object' unless is_relatable
          raise err_klass, 'No self-ownership' if cust.is_a?(self.class)
          block_given? ? yield : is_relatable
        end

        def find_by_objid(objid)
          return nil if objid.to_s.empty?

          if Familia.debug?
            reference = caller(1..1).first
            Familia.trace :FIND_BY_OBJID, Familia.dbclient(uri), objkey, reference
          end

          find_by_key objkey
        end

        def generate_objid
          SecureRandom.uuid_v7
        end

        def generate_extid
          OT::Utils.generate_id
        end
      end

      # Self-register the kids for martial arts classes
      Familia::Base.add_feature(V2::Features::RelatableObject, :relatable_object)
    end

  end
end
