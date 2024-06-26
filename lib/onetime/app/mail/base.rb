
require_relative '../web/views/helpers'

class Onetime::App
  module Mail

    class Base < Mustache
      include Onetime::App::Views::Helpers
      self.template_path = './templates/email'
      self.view_namespace = Onetime::App::Mail
      self.view_path = './onetime/email'
      attr_reader :cust, :locale, :emailer, :mode, :from, :to
      attr_accessor :token
      def initialize cust, locale, *args
        @cust, @locale = cust, locale
        OT.le "#{self.class} locale is: #{locale.to_s}"
        @mode = OT.conf[:emailer][:mode]
        if @mode == :sendgrid
          OT.ld "[mail-sendgrid-from] #{OT.conf[:emailer][:from]}"
          @emailer = OT::App::Mail::SendGridEmail.new OT.conf[:emailer][:from], OT.conf[:emailer][:fromname]
        else
          OT.ld "[mail-smtp-from] #{OT.conf[:emailer][:from]}"
          @emailer = OT::App::Mail::SMTPEmailer.new OT.conf[:emailer][:from]
        end
        OT.le "[emailer] #{@emailer} (#{@mode})"
        init *args if respond_to? :init
      end
      def i18n
        locale = self.locale || 'en'
        pagename = self.class.name.split('::').last.downcase.to_sym
        @i18n ||= {
          locale: locale,
          email: OT.locales[locale][:email][pagename],
          COMMON: OT.locales[locale][:web][:COMMON]
        }
      end
      def deliver_email token=nil
        errmsg = "Your message wasn't sent because we have an email problem"
        OT.info "[deliver-email] with token:(#{token})"
        begin
          email_address_obscured = OT::Utils.obscure_email self[:email_address]
          OT.info "Emailing/#{self.token} #{email_address_obscured} [#{self.class}]"

          unless token
            emailer.send_email self[:email_address], subject, render
          end

        rescue SocketError => ex
          OT.le "Cannot send mail: #{ex.message}\n#{ex.backtrace}"
          raise OT::Problem, errmsg
        rescue Exception => ex
          OT.le "Cannot send mail: #{ex.message}\n#{ex.backtrace}"
          OT.le errmsg
          raise OT::Problem, errmsg
        end
      end
    end

  end
end
