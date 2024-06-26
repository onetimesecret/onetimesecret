require_relative 'base_mailer'
require 'mail'

class Onetime::App
  module Mail

    class SMTPMailer < BaseMailer
      def send_email to_address, subject, content # rubocop:disable Metrics/MethodLength
        OT.info '[email-send-start]'
        mailer_response = nil

        obscured_address = OT::Utils.obscure_email to_address
        OT.ld "> [send-start] #{obscured_address}"

        from_email = "#{self.fromname} <#{self.from}>"
        to_email = to_address
        OT.ld "[send-from] #{from_email}: #{fromname} #{from}"

        if from_email.nil? || from_email.empty?
          OT.info "> [send-exception-no-from-email] #{obscured_address}"
          return
        end

        begin
          mailer_response = ::Mail.deliver do
            # Send emails from a known address that we control. This
            # is important for delivery reliability and some service
            # providers like Amazon SES require it. They'll return
            # "554 Message rejected" response otherwise.
            from      OT.conf[:emailer][:from]

            # But set the reply to address as the customer's so that
            # when people reply to the mail (even though it came from
            # our address), it'll go to the intended recipient.
            reply_to  from_email

            to        to_email
            subject   subject

            # We sending the same HTML content as the content for the
            # plain-text part of the email. There number of folks not
            # viewing their emails as HTML is very low, but we should
            # really get back around to adding text template as well.
            text_part do
              body         content
            end

            html_part do
              content_type 'text/html; charset=UTF-8'
              body         content
            end
          end

        rescue Net::SMTPFatalError => ex
          OT.info "> [send-exception-smtperror] #{obscured_address}"
          OT.ld "#{ex.class} #{ex.message}\n#{ex.backtrace}"
          return
        rescue => ex
          OT.info "> [send-exception-sending] #{obscured_address}"
          OT.ld "#{ex.class} #{ex.message}\n#{ex.backtrace}"
          return
        end

        # Log the details
        OT.ld "From: #{mailer_response.from}"
        OT.ld "To: #{mailer_response.to}"
        OT.ld "Subject: #{mailer_response.subject}"
        OT.ld "Body: #{mailer_response.body.decoded}"

        # Log the headers
        mailer_response.header.fields.each do |field|
          OT.ld "#{field.name}: #{field.value}"
        end

        # Log the delivery status if available
        if mailer_response.delivery_method.respond_to?(:response_code)
          OT.ld "SMTP Response: #{mailer_response.delivery_method.response_code}"
        end

      end
      def self.setup
        ::Mail.defaults do
          opts = { :address   => OT.conf[:emailer][:host] || 'localhost',
                  :port      => OT.conf[:emailer][:port] || 587,
                  :domain    => OT.conf[:site][:domain],
                  :user_name => OT.conf[:emailer][:user],
                  :password  => OT.conf[:emailer][:pass],
                  :authentication => OT.conf[:emailer][:auth],
                  :enable_starttls_auto => OT.conf[:emailer][:tls].to_s == 'true'
          }
          delivery_method :smtp, opts
        end
      end
    end

  end
end
