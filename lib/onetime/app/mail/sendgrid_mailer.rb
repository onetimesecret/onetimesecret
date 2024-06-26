require 'sendgrid-ruby'

require_relative 'base_mailer'

class Onetime::App
  module Mail

    class SendGridMailer < BaseMailer
      include SendGrid

      def send_email to_address, subject, content
        OT.info '[email-send-start]'
        mailer_response = nil

        begin
          obscured_address = OT::Utils.obscure_email to_address
          OT.ld "> [send-start] #{obscured_address}"

          to_email = SendGrid::Email.new(email: to_address)
          from_email = SendGrid::Email.new(email: self.from, name: self.fromname)

          prepared_content = SendGrid::Content.new(
            type: 'text/html',
            value: content,
          )

        rescue => ex
          OT.info "> [send-exception-preparing] #{obscured_address}"
          OT.info content  # this is our template with only the secret link
          OT.le ex.message
          OT.ld ex.backtrace
          raise OT::MailError, MAIL_ERROR
        end

        begin
          mailer = SendGrid::Mail.new(from_email, subject, to_email, prepared_content)
          OT.ld mail

          mailer_response = @sendgrid.client.mail._('send').post(request_body: mailer.to_json)
          OT.info '[email-sent]'
          OT.ld mailer_response.status_code
          OT.ld mailer_response.body
          OT.ld mailer_response.parsed_body
          OT.ld mailer_response.headers

        rescue => ex
          OT.info "> [send-exception-sending] #{obscured_address}"
          OT.ld "#{ex.class} #{ex.message}\n#{ex.backtrace}"
        end

        mailer_response
      end

      def self.setup
        @sendgrid = SendGrid::API.new(api_key: OT.conf[:emailer][:pass])
      end
    end

  end
end
