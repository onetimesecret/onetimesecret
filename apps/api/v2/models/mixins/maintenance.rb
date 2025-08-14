# apps/api/v2/models/mixins/maintenance.rb

module V2
  module Mixins

     # Model Maintenance
     #
     # Adds methods for performing maintenance on familia horreum models.
     #
     # NOTE: Expects the model to have Expiration enabled.
     #
     # FAMILIA QUIRK: Records with empty identifiers cause stack overflow
     # in exists?, save, and other model operations due to infinite loops
     # in key generation (identifier → dbkey → identifier). Always
     # validate identifier before calling maintenance methods.
     #
     module ModelMaintenance

      def self.included(base)
        base.sorted_set :maintenance_notes # Sorted by time UTC in seconds
      end

      def flag_for_permanent_removal!(reason)
        flag_for_permanent_removal(reason)
        save
      end

      def flag_for_permanent_removal(reason)
        # SAFETY: Ensure the object's record identifier field is
        # populated and valid before model operations.
        return unless exists?

        self.default_expiration  = 7.days
        self.role = 'permanent_removal'

        add_note(reason)
      end

      def add_note(note)
        maintenance_notes.add(OT.now.to_i, note)
      end

      def notes
        maintenance_notes.rangeraw(0, -1, withscores: true)
      end

    end
  end
end
