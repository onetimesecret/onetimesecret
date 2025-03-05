
require_relative '../web/views/view_helpers'

module Onetime::App
  module Mail

    class Base < Mustache
      include Onetime::App::Views::ViewHelpers

      self.template_path = './templates/mail'
      self.view_namespace = Onetime::App::Mail
      self.view_path = './onetime/email'
      attr_reader :cust, :locale, :emailer, :mode, :from, :to
      attr_accessor :token

      def initialize cust, locale, *args
        @cust, @locale = cust, locale
        OT.ld "#{self.class} locale is: #{locale.to_s}"
        @mode = OT.conf[:emailer][:mode]

        if @mode == :sendgrid
          OT.ld "[mail-sendgrid-from] #{OT.conf[:emailer][:from]}"
          @emailer = OT::App::Mail::SendGridMailer.new OT.conf[:emailer][:from], OT.conf[:emailer][:fromname]
        else
          OT.ld "[mail-smtp-from] #{OT.conf[:emailer][:from]}"
          @emailer = OT::App::Mail::SMTPMailer.new OT.conf[:emailer][:from]
        end

        safe_mail_config = {
          from: OT.conf[:emailer][:from],
          fromname: OT.conf[:emailer][:fromname],
          host: OT.conf[:emailer][:host],
          port: OT.conf[:emailer][:port],
          user: OT.conf[:emailer][:user],
          tls: OT.conf[:emailer][:tls],
          auth: OT.conf[:emailer][:auth],
        }
        OT.info "[mailer] #{mode} #{safe_mail_config.to_json}"
        init(*args) if respond_to? :init
      end

      def i18n
        locale = self.locale || 'en'
        pagename = self.class.name.split('::').last.downcase.to_sym
        locale = 'en' unless OT.locales.key?(locale)
        @i18n ||= {
          locale: locale,
          email: OT.locales[locale][:email][pagename],
          COMMON: OT.locales[locale][:web][:COMMON]
        }
      end

      def deliver_email token=nil
        errmsg = "Your message wasn't sent because we have an email problem"

        email_address_obscured = OT::Utils.obscure_email self[:email_address]
        OT.info "Emailing/#{self.token} #{email_address_obscured} [#{self.class}]"

        message_identifier = if self[:secret]
                    self[:secret].identifier
                  else
                    SecureRandom.hex.to_s[0, 24]
                  end

        mailer_response = begin
          # If we have a token of gratitude, we skip the email. There is only one
          # codepath that has a token set. Just keep in mind that this is not an
          # authentication token or any kind of unique value. It's just a simple
          # flag that when set to any truthy value will skip over this delivery.
          # See Onetime::App::API#create
          unless token
            emailer.send_email self[:email_address], subject, render
          end

        rescue SocketError => ex
        internal_emsg = "Cannot send mail: #{ex.message}\n#{ex.backtrace}"
          OT.le internal_emsg

          Onetime::EmailReceipt.create self[:cust].identifier, message_identifier, internal_emsg
          raise OT::Problem, errmsg

        rescue Exception => ex
          internal_emsg = "Cannot send mail: #{ex.message}\n#{ex.backtrace}"
          OT.le internal_emsg
          OT.le errmsg

          Onetime::EmailReceipt.create self[:cust].identifier, message_identifier, internal_emsg.to_json
          raise OT::Problem, errmsg
        end

        # Nothing left to do here if we didn't send an email
        return unless mailer_response

        Onetime::EmailReceipt.create self[:cust].identifier, message_identifier, mailer_response.to_json

        OT.info "[email-sent] to #{email_address_obscured} #{self[:cust].identifier} #{message_identifier}"
        mailer_response
      end

      def private_uri(obj)
        format('/private/%s', obj.key)
      end

      def secret_uri(obj)
        format('/secret/%s', obj.key)
      end

      def secret_display_domain(obj)
        scheme = base_scheme
        host = obj.share_domain || Onetime.conf[:site][:host]
        [scheme, host].join
      end

      def base_scheme
        Onetime.conf[:site][:ssl] ? 'https://' : 'http://'
      end

      def baseuri
        scheme = base_scheme
        host = Onetime.conf[:site][:host]
        [scheme, host].join
      end

    end

  end
end
