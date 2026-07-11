# lib/onetime/cli/email/preview_command.rb
#
# frozen_string_literal: true

# CLI command for previewing rendered email templates.
#
# Thin adapter over {Onetime::Operations::Email::PreviewTemplate} (ticket #44) —
# the SINGLE implementation of the preview verb, shared with the colonel API.
# The op owns the sample-data resolution + rendering; this command keeps only the
# CLI concerns (arg/option parsing, --open, and the error messaging).
#
# Usage:
#   ots email preview <template>                  # Text output using sample data
#   ots email preview <template> --html           # HTML output
#   ots email preview <template> --html --open    # Open in browser (macOS)
#   ots email preview <template> --data '{"key":"val"}'
#   ots email preview <template> --locale fr

require 'json'
require 'onetime/operations/email/preview_template'

module Onetime
  module CLI
    module Email
      class PreviewCommand < Command
        desc 'Render a template for visual inspection'

        argument :template,
          type: :string,
          required: true,
          desc: "Template name: #{AVAILABLE_TEMPLATES.join(', ')}"

        option :html,
          type: :boolean,
          default: false,
          desc: 'Output HTML body instead of text'

        option :data,
          type: :string,
          required: false,
          desc: 'JSON blob of template variables (omit to use sample data)'

        option :locale,
          type: :string,
          default: 'en',
          desc: 'Locale for translations'

        option :open,
          type: :boolean,
          default: false,
          desc: 'Open HTML in browser (macOS, requires --html)'

        def call(template:, html: false, data: nil, locale: 'en', open: false, **)
          boot_application!

          parsed_data = data ? JSON.parse(data).transform_keys(&:to_sym) : nil

          result = Onetime::Operations::Email::PreviewTemplate.new(
            template: template,
            data: parsed_data,
            locale: locale,
            format: html ? 'html' : 'text',
          ).call

          if html && open
            open_in_browser(result.body)
          else
            puts result.body
          end
        rescue Onetime::Operations::Email::PreviewTemplate::MissingSampleError => ex
          warn ex.message
          warn "Create a YAML file there or pass --data '{...}'"
          exit 1
        rescue ArgumentError => ex
          handle_argument_error(ex, template)
        rescue JSON::ParserError => ex
          warn "Invalid JSON in --data: #{ex.message}"
          exit 1
        end

        private

        def open_in_browser(html_body)
          require 'tempfile'
          tmpfile = Tempfile.new(['email_preview', '.html'])
          tmpfile.write(html_body)
          tmpfile.close
          warn tmpfile.path
          system('open', tmpfile.path)
        end

        def handle_argument_error(ex, template)
          warn "Error: #{ex.message}"
          unless AVAILABLE_TEMPLATES.include?(template.to_sym)
            $stderr.puts
            warn 'Available templates:'
            AVAILABLE_TEMPLATES.each { |t| warn "  #{t}" }
          end
          exit 1
        end
      end
    end

    register 'email preview', Email::PreviewCommand
  end
end
