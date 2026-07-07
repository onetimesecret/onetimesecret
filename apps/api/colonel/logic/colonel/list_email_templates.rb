# apps/api/colonel/logic/colonel/list_email_templates.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/email/list_templates'

module ColonelAPI
  module Logic
    module Colonel
      # List the available email templates + their renderable formats (Colonel).
      #
      # Thin adapter over {Onetime::Operations::Email::ListTemplates} — the single
      # implementation shared with the `bin/ots email templates` CLI (ticket #44).
      # READ-ONLY: nothing mutates, so nothing is audited (CONTRACT 4). Feeds the
      # email-tools screen's template picker.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class ListEmailTemplates < ColonelAPI::Logic::Base
        attr_reader :templates

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          @templates = Onetime::Operations::Email::ListTemplates.new.call
          success_data
        end

        def success_data
          {
            record: {
              templates: templates.map do |entry|
                {
                  name: entry.name,
                  class_name: entry.klass,
                  formats: entry.formats,
                }
              end,
            },
            details: {
              count: templates.length,
            },
          }
        end
      end
    end
  end
end
