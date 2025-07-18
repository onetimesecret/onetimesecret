# apps/api/v2/models/features/core_object.rb

module V2
  module Features
    # CoreObject
    #
    # Provides the standard core object fields and methods.
    #
    module CoreObject
      def self.included(base)
        base.class_sorted_set :object_ids
        base.field :objid
        base.field :extid
        base.field :api_version
        base.identifier :objid
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
          @objid ||= begin
            generated_id = self.class.generate_objid
            # Using the attr_writer method ensures any future Familia
            # enhancements to the setter are properly invoked (as opposed
            # to directly assigning @objid).
            self.objid = generated_id
          end
        end

        def extid
          @extid ||= begin
            generated_id = self.class.generate_extid
            self.extid = generated_id
          end
        end
      end

      module ClassMethods
        def generate_objid
          SecureRandom.uuid_v7
        end

        def generate_extid
          OT::Utils.generate_id
        end
      end

      # Self-register the kids for martial arts classes
      Familia::Base.add_feature(V2::Features::CoreObject, :core_object)
    end
  end
end
