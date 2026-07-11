# lib/onetime/operations/email/list_templates.rb
#
# frozen_string_literal: true

# Central (cross-cutting) admin operation — see decision D3. Enumerating the
# available email templates + their rendered formats is mailer infrastructure
# with no single domain owner.
require 'onetime/mail'
require 'onetime/operations/email/preview_template'

module Onetime
  module Operations
    module Email
      # List the available email templates and which formats (text/html) each
      # renders — the SINGLE implementation of the template-list capability the UI
      # dropdown, the colonel `GET /api/colonel/email/templates` endpoint, and the
      # `bin/ots email templates` CLI list all share.
      #
      # READ-ONLY: pure filesystem/class inspection, no side effects, no audit
      # (CONTRACT 4). Output mirrors the CLI's `build_template_list` verbatim.
      class ListTemplates
        # One template summary row.
        Entry = Data.define(:name, :klass, :formats)

        # @return [Array<Entry>] one row per *available* {AVAILABLE_TEMPLATES}
        #   entry, in order. Billing-gated templates (e.g. trial_expiring,
        #   subscription_changed) resolve to no class when billing is disabled;
        #   template_class_for raises ArgumentError for those, so we skip them
        #   rather than crash the whole listing. template_class_for is the single
        #   authority on which names are billing-gated.
        def call
          AVAILABLE_TEMPLATES.filter_map do |name|
            template_class = resolve_class(name)
            next if template_class.nil?

            has_html = File.exist?(erb_path(name, 'html'))
            has_text = File.exist?(erb_path(name, 'txt'))

            Entry.new(
              name: name.to_s,
              klass: template_class.name.split('::').last,
              formats: [has_text ? 'text' : nil, has_html ? 'html' : nil].compact,
            )
          end
        end

        private

        # Resolve a template name to its view class, or nil when the template is
        # not available in this deployment (billing disabled). AVAILABLE_TEMPLATES
        # only holds known names, so the only reachable ArgumentError here is the
        # billing-disabled rejection — never the "Unknown template" else branch.
        def resolve_class(name)
          Onetime::Mail::Mailer.send(:template_class_for, name)
        rescue ArgumentError
          nil
        end

        def erb_path(name, extension)
          File.join(
            Onetime::Mail::Templates::Base::TEMPLATE_PATH,
            "#{name}.#{extension}.erb",
          )
        end
      end
    end
  end
end
