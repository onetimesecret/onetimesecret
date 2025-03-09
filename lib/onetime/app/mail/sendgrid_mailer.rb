require 'sendgrid-ruby'

require_relative 'base_mailer'

module Onetime::App
  module Mail
    class SendGridMailer < BaseMailer
      include SendGrid

      def send_email(to_address, subject, content)
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
            value: content,
          )

          plain_content = SendGrid::Content.new(
            type: 'text/plain',
            value: content.gsub(/<\/?[^>]*>/, ''),
          )

          mailer = SendGrid::Mail.new(from_email, subject, to_email, plain_content)
          mailer.add_content(html_content)

          OT.ld mailer

          mailer_response = self.class.sendgrid_api.client.mail._('send').post(request_body: mailer.to_json)
          OT.info "> [send-success] Email sent successfully to #{obscured_address}"
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
