# lib/onetime/mail/mailer/smtp_mailer.rb

require 'mail'  # gem 'mail', here referred to as ::Mail

require 'onetime/refinements/hash_refinements'

require_relative 'base_mailer'

module Onetime::Mail
  module Mailer
    class SMTPMailer < BaseMailer

      using IndifferentHashAccess

      def send_email(to_address, subject, html_content, text_content) # rubocop:disable Metrics/MethodLength
        mailer_response = nil
        obscured_address = OT::Utils.obscure_email(to_address)
        sender_email = self.from # just the email address, not with the name
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
          mailer_response = ::Mail.deliver do
            # Send emails from a known address that we control. This
            # is important for delivery reliability and some service
            # providers like Amazon SES require it. They'll return
            # "554 Message rejected" response otherwise.
            from      sender_email

            # But set the reply to address as the customer's so that
            # when people reply to the mail (even though it came from
            # our address), it'll go to the intended recipient.
            reply_to  reply_to

            to        to_email
            subject   subject

            # We sending the same HTML content as the content for the
            # plain-text part of the email. There number of folks not
            # viewing their emails as HTML is very low, but we should
            # really get back around to adding text template as well.
            text_part do
              content_type 'text/plain; charset=UTF-8'
              body         html_content
            end

            html_part do
              content_type 'text/html; charset=UTF-8'
              body         text_content
            end
          end

        rescue Net::SMTPFatalError => ex
          OT.le "> [send-exception-smtperror] #{ex.message} [to: #{obscured_address}]"
          OT.ld "#{ex.class} #{ex.message}\n#{ex.backtrace}"

        rescue => ex
          OT.le "> [send-exception-sending] #{ex.class} #{ex.message} [to: #{obscured_address}]"
          OT.ld ex.backtrace
        end

        return unless mailer_response

        OT.info "> [send-success] Email sent successfully [to: #{obscured_address}]"

        # Log the details
        OT.ld "From: #{mailer_response.from}"
        OT.ld "To: #{obscured_address}"
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

        mailer_response
      end

      def self.setup
        ::Mail.defaults do
          delivery_method :smtp, {
            :address   => OT.conf[:emailer][:host] || 'localhost',
            :port      => OT.conf[:emailer][:port] || 587,
            :domain    => OT.conf[:site][:domain],
            :user_name => OT.conf[:emailer][:user],
            :password  => OT.conf[:emailer][:pass],
            :authentication => OT.conf[:emailer][:auth],
            :enable_starttls_auto => OT.conf[:emailer][:tls].to_s == 'true',
          }
        end
      end

      def self.clear
        # No instance variables to clear, so this is intentionally a nullop.
      end

    end

  end
end
