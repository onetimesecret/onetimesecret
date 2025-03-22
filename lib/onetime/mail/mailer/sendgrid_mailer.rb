# lib/onetime/mail/mailer/sendgrid_mailer.rb

require 'sendgrid-ruby'
require_relative 'base_mailer'

module Onetime::Mail
  module Mailer
    class SendGridMailer < BaseMailer
      include SendGrid

      def send_email(to_address, subject, html_content, text_content, test_mode=false)
        mailer_response = nil
        obscured_address = OT::Utils.obscure_email(to_address)
        sender_email = SendGrid::Email.new(email: self.from, name: self.fromname)
        to_email = SendGrid::Email.new(email: to_address)
        reply_to = SendGrid::Email.new(email: self.reply_to)

        OT.ld "[email-send-start] sender:#{sender_email}; reply-to:#{reply_to}"

        # Return early if there is no system email address to send from
        if self.from.to_s.empty?
          OT.le "> [send-exception] No from address [to: #{obscured_address}]"
          return
        end

        OT.li "> [send-start] [to: #{obscured_address}]"

        begin
          sg_content_html = SendGrid::Content.new(
            type: 'text/html',
            value: html_content,
          )

          sg_content_plain = SendGrid::Content.new(
            type: 'text/plain',
            value: text_content,
          )

          # https://github.com/sendgrid/sendgrid-ruby/blob/main/lib/sendgrid/helpers/mail/mail.rb
          mail = SendGrid::Mail.new(sender_email, subject, to_email, sg_content_plain)
          mail.reply_to = reply_to

          mail.add_content(sg_content_html)

          # Enable sandbox mode for testing
          if test_mode
            mail_settings = SendGrid::MailSettings.new
            sandbox_mode = SendGrid::SandBoxMode.new(enable: true)
            mail_settings.sandbox_mode = sandbox_mode
            mail.mail_settings = mail_settings
          end

          OT.ld mail

          mailer_response = self.class.sendgrid_api.client.mail._('send').post(request_body: mail.to_json)

          # NOTE: There doesn't seem to be a SendGrid specific error class. All
          # the examples use the generic Exception class.
        rescue => ex
          OT.le "> [send-exception-sending] #{ex.class} #{ex.message} [to: #{obscured_address}]"
          OT.ld ex.backtrace
        end

        return unless mailer_response

        OT.info "> [send-success] Email sent successfully [to: #{obscured_address}] (test mode: #{test_mode})"

        OT.ld mailer_response.status_code
        OT.ld mailer_response.body
        OT.ld mailer_response.headers

        mailer_response
      end

      def self.setup
        @sendgrid_api = SendGrid::API.new(api_key: OT.conf[:emailer][:pass])
      end

      class << self
        attr_reader :sendgrid_api
      end
    end
  end
end
