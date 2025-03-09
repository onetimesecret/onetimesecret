require 'sendgrid-ruby'

require_relative 'base_mailer'

module Onetime::App
  module Mail
    class SendGridMailer < BaseMailer
      include SendGrid

      def send_email(to_address, subject, html, text_content, test_mode=false)
        OT.info '[email-send-start]'
        mailer_response = nil

        # Return early if no from address
        if self.from.nil? || self.from.empty?
          OT.info "> [send-exception] No from address #{OT::Utils.obscure_email(to_address)}"
          return nil
        end

        begin
          obscured_address = OT::Utils.obscure_email(to_address)
          OT.ld "> [send-start] #{obscured_address}"

          to_email = SendGrid::Email.new(email: to_address)
          from_email = SendGrid::Email.new(email: self.from, name: self.fromname)

          html_content = SendGrid::Content.new(
            type: 'text/html',
            value: html_content,
          )

          plain_content = SendGrid::Content.new(
            type: 'text/plain',
            value: text_content,
          )

          mailer = SendGrid::Mail.new(from_email, subject, to_email, plain_content)
          mailer.add_content(html_content)

          # Enable sandbox mode for testing
          if test_mode
            mail_settings = SendGrid::MailSettings.new
            sandbox_mode = SendGrid::SandBoxMode.new(enable: true)
            mail_settings.sandbox_mode = sandbox_mode
            mailer.mail_settings = mail_settings
          end

          OT.ld mailer

          mailer_response = self.class.sendgrid_api.client.mail._('send').post(request_body: mailer.to_json)
          OT.info "> [send-#{test_mode ? 'test' : 'success'}] Email #{test_mode ? 'validated' : 'sent'} to #{obscured_address}"
          OT.ld mailer_response.status_code
          OT.ld mailer_response.body
          OT.ld mailer_response.headers

        rescue => ex
          OT.info "> [send-exception-sending] #{obscured_address} #{ex.class} #{ex.message}"
          OT.ld "#{ex.backtrace}"
        end

        mailer_response
      end

      def self.setup
        @@sendgrid_api = SendGrid::API.new(api_key: OT.conf[:emailer][:pass])
      end

      def self.sendgrid_api
        @@sendgrid_api
      end
    end
  end
end
