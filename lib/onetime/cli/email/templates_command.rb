# lib/onetime/cli/email/templates_command.rb
#
# frozen_string_literal: true

# CLI command for listing available email templates and their details.
#
# Usage:
#   ots email templates              # List all templates
#   ots email templates secret_link  # Show details for a specific template
#   ots email templates --format json

require 'json'

module Onetime
  module CLI
    module Email
      class TemplatesCommand < Command
        desc 'List available email templates'

        argument :template,
          type: :string,
          required: false,
          desc: 'Template name to show details for (optional)'

        option :format,
          type: :string,
          default: 'text',
          aliases: ['f'],
          desc: 'Output format: text or json'

        def call(template: nil, format: 'text', **)
          boot_application!

          if template
            show_template_detail(template, format)
          else
            list_templates(format)
          end
        end

        private

        def list_templates(format)
          templates = build_template_list

          case format
          when 'json'
            puts JSON.pretty_generate(templates)
          else
            display_template_list(templates)
          end
        end

        def show_template_detail(name, format)
          sym = name.to_sym
          unless AVAILABLE_TEMPLATES.include?(sym)
            warn "Unknown template: #{name}"
            warn
            warn 'Available templates:'
            AVAILABLE_TEMPLATES.each { |t| warn "  #{t}" }
            exit 1
          end

          detail = build_template_detail(sym)

          case format
          when 'json'
            puts JSON.pretty_generate(detail)
          else
            display_template_detail(detail)
          end
        end

        def build_template_list
          AVAILABLE_TEMPLATES.map do |name|
            template_class = Onetime::Mail::Mailer.send(:template_class_for, name)
            has_html       = File.exist?(erb_path(name, 'html'))
            has_text       = File.exist?(erb_path(name, 'txt'))

            {
              name: name.to_s,
              class: template_class.name.split('::').last,
              formats: [has_text ? 'text' : nil, has_html ? 'html' : nil].compact,
            }
          end
        end

        def build_template_detail(name)
          template_class = Onetime::Mail::Mailer.send(:template_class_for, name)
          has_html       = File.exist?(erb_path(name, 'html'))
          has_text       = File.exist?(erb_path(name, 'txt'))

          # Extract required fields from class comments
          source_file                      = class_source_path(name)
          required_fields, optional_fields = extract_documented_fields(source_file)

          {
            name: name.to_s,
            class: template_class.name,
            formats: [has_text ? 'text' : nil, has_html ? 'html' : nil].compact,
            required_fields: required_fields,
            optional_fields: optional_fields,
            template_files: template_file_paths(name),
            view_file: source_file,
          }
        end

        def display_template_list(templates)
          puts format('%-35s %-22s %s', 'TEMPLATE', 'CLASS', 'FORMATS')
          puts "\u2500" * 70
          templates.each do |t|
            puts format('%-35s %-22s %s', t[:name], t[:class], t[:formats].join(', '))
          end
          puts
          puts "#{templates.size} templates available"
          puts
          puts 'Show details: ots email templates <name>'
        end

        def display_template_detail(detail)
          puts format('Template:  %s', detail[:name])
          puts format('Class:     %s', detail[:class])
          puts format('Formats:   %s', detail[:formats].join(', '))
          puts

          if detail[:required_fields].any?
            puts 'Required fields:'
            detail[:required_fields].each { |f| puts "  #{f}" }
            puts
          end

          if detail[:optional_fields].any?
            puts 'Optional fields:'
            detail[:optional_fields].each { |f| puts "  #{f}" }
            puts
          end

          puts 'Files:'
          detail[:template_files].each { |f| puts "  #{f}" }
          puts "  #{detail[:view_file]}"
        end

        def erb_path(name, extension)
          File.join(
            Onetime::Mail::Templates::Base::TEMPLATE_PATH,
            "#{name}.#{extension}.erb",
          )
        end

        def template_file_paths(name)
          %w[txt html].filter_map do |ext|
            path = erb_path(name, ext)
            path if File.exist?(path)
          end
        end

        def class_source_path(name)
          File.join(File.expand_path('../../mail/views', __dir__), "#{name}.rb")
        end

        # Parse the view source file for documented Required/Optional data fields.
        # Scans all comment lines for "Required data:" and "Optional data:" markers,
        # then collects indented field definitions below them.
        def extract_documented_fields(source_file)
          required = []
          optional = []
          return [required, optional] unless File.exist?(source_file)

          current = nil
          File.readlines(source_file).each do |line|
            stripped = line.strip
            next unless stripped.start_with?('#')

            text = stripped.sub(/^#\s?/, '')
            if text =~ /^(Required data|One of the following)/i
              current = required
            elsif text =~ /^Optional data:/i
              current = optional
            elsif current && text =~ /^\s+(\w+):\s*(.*)/
              field_name = Regexp.last_match(1)
              field_desc = Regexp.last_match(2).strip
              current << "#{field_name}: #{field_desc}" unless field_desc.empty?
              current << field_name.to_s if field_desc.empty?
            elsif current && (text.strip.empty? || text =~ /^(NOTE|class\s)/i)
              current = nil
            end
          end

          [required, optional]
        end
      end
    end

    register 'email templates', Email::TemplatesCommand
  end
end
