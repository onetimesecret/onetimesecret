require 'aws-sdk-sesv2'

require_relative 'base_mailer'

module Onetime::App
  module Mail

    class AmazonSESMailer < BaseMailer

      def send_email(to_address, subject, html_content, text_content)
        OT.info '[email-send-start]'
        mailer_response = nil

        begin
          obscured_address = OT::Utils.obscure_email(to_address)
          from_email = OT.conf[:emailer][:from]
          reply_to = "#{fromname} <#{self.from}>"
          to_email = to_address

          OT.ld "> [send-start] #{obscured_address}"

          # Prepare the email parameters
          email_params = {
            destination: {
              to_addresses: [to_email]
            },
            content: {
              simple: {
                subject: {
                  data: subject,
                  charset: 'UTF-8'
                },
                body: {
                  html: {
                    data: html_content,
                    charset: 'UTF-8'
                  },
                  text: {
                    data: text_content,
                    charset: 'UTF-8'
                  }
                }
              }
            },
            from_email_address: from_email,
            reply_to_addresses: [reply_to]
          }

          # Send the email
          mailer_response = self.class.ses_client.send_email(email_params)

          OT.info '[email-sent]'
          OT.ld mailer_response.message_id
          # Remove the context and http_response references that don't exist in the actual SDK
          OT.ld "Email sent successfully"

        rescue Aws::SESV2::Errors::ServiceError => ex
          OT.info "> [send-exception-ses-error] #{obscured_address} #{ex.class} #{ex.message}"
          OT.ld "#{ex.backtrace}"
        rescue => ex
          OT.info "> [send-exception-sending] #{obscured_address} #{ex.class} #{ex.message}"
          OT.ld "#{ex.backtrace}"
        end

        mailer_response
      end

      def self.setup
        # Configure AWS SES client
        @@ses_client = Aws::SESV2::Client.new(
          region: OT.conf[:emailer][:region] || raise("Region not configured"),
          credentials: Aws::Credentials.new(
            OT.conf[:emailer][:user],
            OT.conf[:emailer][:pass]
          )
        )
      end

      def self.ses_client
        @@ses_client
      end
    end

  end
end
