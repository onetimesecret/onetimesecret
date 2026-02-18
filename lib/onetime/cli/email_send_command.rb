# lib/onetime/cli/email_send_command.rb
#
# frozen_string_literal: true

# CLI command for sending transactional emails directly via SMTP.
#
# Usage:
#   ots email send <template> --to user@example.com --data '{"key":"val"}'
#   ots email send <template> --to user@example.com --data '{"key":"val"}' --execute
#   ots email send <template> --to user@example.com --data '{"key":"val"}' --locale fr
#
# Dry-run by default. Use --execute to actually deliver.
# Bypasses RabbitMQ/workers — sends directly via configured SMTP backend.

require 'json'

module Onetime
  module CLI
    class EmailSendCommand < Command
      AVAILABLE_TEMPLATES = [
        :secret_link,
        :welcome,
        :password_request,
        :incoming_secret,
        :feedback_email,
        :secret_revealed,
        :expiration_warning,
        :organization_invitation,
        :email_change_confirmation,
        :email_change_requested,
        :email_changed,
      ].freeze

      desc 'Send a transactional email (dry-run by default)'

      argument :template,
        type: :string,
        required: true,
        desc: "Template name: #{AVAILABLE_TEMPLATES.join(', ')}"

      option :to,
        type: :string,
        required: true,
        desc: 'Recipient email address'

      option :data,
        type: :string,
        required: true,
        desc: 'JSON blob of template variables'

      option :execute,
        type: :boolean,
        default: false,
        desc: 'Actually send the email (default: dry-run)'

      option :locale,
        type: :string,
        default: 'en',
        desc: 'Locale for translations'

      option :format,
        type: :string,
        default: 'text',
        aliases: ['f'],
        desc: 'Output format: text or json'

      def call(template:, to:, data:, execute: false, locale: 'en', format: 'text', **)
        boot_application!

        template_data  = parse_and_merge_data(data, to)
        template_class = resolve_template(template)
        instance       = build_template(template_class, template_data, locale)
        email          = instance.to_email(
          from: Onetime::Mail::Mailer.from_address,
          reply_to: Onetime::Mail::Mailer.send(:reply_to_address, instance),
        )

        if format == 'json'
          output_json(email, template, execute)
        else
          output_text(email, template, locale, execute)
        end

        deliver!(email) if execute
      rescue ArgumentError => ex
        handle_argument_error(ex, template)
      rescue JSON::ParserError => ex
        warn "Invalid JSON in --data: #{ex.message}"
        exit 1
      end

      private

      def parse_and_merge_data(json_string, recipient)
        parsed                     = JSON.parse(json_string)
        symbolized                 = parsed.transform_keys(&:to_sym)
        symbolized[:recipient]     = recipient
        symbolized[:email_address] = recipient
        symbolized
      end

      def resolve_template(name)
        Onetime::Mail::Mailer.send(:template_class_for, name.to_sym)
      end

      def build_template(template_class, data, locale)
        template_class.new(data, locale: locale)
      end

      def deliver!(email)
        Onetime::Mail::Mailer.delivery_backend.deliver(email)
        puts
        puts 'Delivery: SENT'
      rescue StandardError => ex
        $stderr.puts
        warn "Delivery FAILED: #{ex.message}"
        exit 1
      end

      def output_text(email, template, locale, execute)
        puts format('Template:  %s', template)
        puts format('To:        %s', email[:to])
        puts format('From:      %s', email[:from])
        puts format('Subject:   %s', email[:subject])
        puts format('Locale:    %s', locale)
        puts
        puts "\u2500\u2500 Text Body \u2500\u2500"
        puts email[:text_body] || '(none)'
        puts
        puts "\u2500\u2500 HTML Body \u2500\u2500"
        puts email[:html_body] || '(none)'
        puts
        unless execute
          puts 'Mode: DRY RUN (use --execute to send)'
        end
      end

      def output_json(email, template, execute)
        result = {
          template: template,
          to: email[:to],
          from: email[:from],
          reply_to: email[:reply_to],
          subject: email[:subject],
          text_body: email[:text_body],
          html_body: email[:html_body],
          mode: execute ? 'execute' : 'dry_run',
        }
        puts JSON.pretty_generate(result)
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

    register 'email send', EmailSendCommand
  end
end
