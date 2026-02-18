# lib/onetime/cli/email/preview_command.rb
#
# frozen_string_literal: true

# CLI command for previewing rendered email templates.
#
# Usage:
#   ots email preview <template>                  # Text output using sample data
#   ots email preview <template> --html           # HTML output
#   ots email preview <template> --html --open    # Open in browser (macOS)
#   ots email preview <template> --data '{"key":"val"}'
#   ots email preview <template> --locale fr

require 'json'
require 'yaml'

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

          template_data  = load_data(data, template)
          template_class = resolve_template(template)
          instance       = template_class.new(template_data, locale: locale)

          if html
            body = instance.render_html || '(no HTML template)'
            if open
              open_in_browser(body)
            else
              puts body
            end
          else
            puts instance.render_text
          end
        rescue ArgumentError => ex
          handle_argument_error(ex, template)
        rescue JSON::ParserError => ex
          warn "Invalid JSON in --data: #{ex.message}"
          exit 1
        end

        private

        def load_data(json_string, template_name)
          if json_string
            parsed                       = JSON.parse(json_string)
            symbolized                   = parsed.transform_keys(&:to_sym)
            symbolized[:recipient]     ||= 'preview@example.com'
            symbolized[:email_address] ||= symbolized[:recipient]
            symbolized
          else
            load_sample_data(template_name)
          end
        end

        def load_sample_data(template_name)
          sample_file = File.join(SAMPLES_PATH, "#{template_name}.yml")

          unless File.exist?(sample_file)
            warn "No sample data found: #{sample_file}"
            warn "Create a YAML file there or pass --data '{...}'"
            exit 1
          end

          parsed                       = YAML.safe_load_file(sample_file, permitted_classes: [Symbol])
          symbolized                   = parsed.transform_keys(&:to_sym)
          symbolized[:recipient]     ||= symbolized.delete(:email_address) || 'preview@example.com'
          symbolized[:email_address] ||= symbolized[:recipient]
          symbolized
        end

        def resolve_template(name)
          Onetime::Mail::Mailer.send(:template_class_for, name.to_sym)
        end

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
