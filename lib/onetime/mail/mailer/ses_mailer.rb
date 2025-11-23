# lib/onetime/mail/mailer/ses_mailer.rb

require 'aws-sdk-sesv2'
require_relative 'base_mailer'

module Onetime::Mail
  module Mailer
    class SESMailer < BaseMailer

      def send_email(to_address, subject, html_content, text_content)
        mailer_response = nil
        obscured_address = OT::Utils.obscure_email(to_address)
        sender_email = self.from
        to_email = to_address
        reply_to = self.reply_to

        OT.ld "[email-send-start] sender:#{sender_email}; reply-to:#{reply_to}"

        # Return early if there is no system email address to send from
        if self.from.to_s.empty?
          OT.le "> [send-exception] No from address [to: #{obscured_address}]"
          return
        end

        OT.li "> [send-start] [to: #{obscured_address}]"

        begin
          # Prepare the email parameters
          email_params = {
            destination: {
              to_addresses: [to_email],
            },
            content: {
              simple: {
                subject: {
                  data: subject,
                  charset: 'UTF-8',
                },
                body: {
                  html: {
                    data: html_content,
                    charset: 'UTF-8',
                  },
                  text: {
                    data: text_content,
                    charset: 'UTF-8',
                  },
                },
              },
            },
            from_email_address: sender_email,
          }

          # Only include reply_to_addresses if reply_to is present
          if reply_to && !reply_to.to_s.empty?
            email_params[:reply_to_addresses] = [reply_to]
          end

          # Send the email
          mailer_response = self.class.ses_client.send_email(email_params)

        rescue Aws::SESV2::Errors::ServiceError => ex
          OT.le "> [send-exception-ses-error] #{ex.message} [to: #{obscured_address}]"
          OT.ld "#{ex.backtrace}"

        rescue => ex
          OT.le "> [send-exception-sending] #{ex.class} #{ex.message} [to: #{obscured_address}]"
          OT.ld ex.backtrace
        end

        return unless mailer_response

        OT.info "> [send-success] Email sent successfully [to: #{obscured_address}]"

        OT.ld mailer_response.inspect

        mailer_response
      end

      def self.setup
        # Configure AWS SES client with OpenSSL 3.6+ CRL fix
        # OpenSSL 3.6 enables strict CRL checking by default, but macOS's
        # OpenSSL build lacks a CRL bundle, causing valid certificates to fail.
        # We create a custom X509::Store with CRL checking disabled.
        # See: https://github.com/rails/rails/issues/55886

        # Create custom certificate store with system certs but no CRL checking
        cert_store = OpenSSL::X509::Store.new
        cert_store.set_default_paths

        @ses_client = Aws::SESV2::Client.new(
          region: OT.conf[:emailer][:region] || raise("Region not configured"),
          credentials: Aws::Credentials.new(
            OT.conf[:emailer][:user],
            OT.conf[:emailer][:pass],
          ),
          ssl_verify_peer: true,
          ssl_ca_store: cert_store,
        )
      end

      def self.clear
        @ses_client = nil
      end

      class << self
        attr_reader :ses_client
      end
    end

  end
end
