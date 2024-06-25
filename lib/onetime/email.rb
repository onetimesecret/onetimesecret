
require 'mustache'
require 'mail'


module Onetime

  require 'onetime/app/web/views/helpers'
  class Email < Mustache
    include Onetime::App::Views::Helpers
    self.template_path = './templates/email'
    self.view_namespace = Onetime::Email
    self.view_path = './onetime/email'
    attr_reader :cust, :locale, :emailer, :mode, :from, :to
    attr_accessor :token
    def initialize cust, locale, *args
      @cust, @locale = cust, locale
      OT.le "#{self.class} locale is: #{locale.to_s}"
      @mode = OT.conf[:emailer][:mode]
      if @mode == :sendgrid
        OT.ld "[mail-sendgrid-from] #{OT.conf[:emailer][:from]}"
        @emailer = OT::SendGridEmail.new OT.conf[:emailer][:from], OT.conf[:emailer][:fromname]
      else
        OT.ld "[mail-smtp-from] #{OT.conf[:emailer][:from]}"
        @emailer = OT::SMTPEmailer.new OT.conf[:emailer][:from]
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
    class Welcome < OT::Email
      def init secret
        self[:secret] = secret
        self[:email_address] = cust.email
      end
      def subject
        i18n[:email][:subject]
      end
      def verify_uri
        secret_uri self[:secret]
      end
    end
    class SecretLink < OT::Email
      def init secret, recipient
        self[:secret] = secret
        self[:custid] = cust.custid
        self[:email_address] = recipient
        self.subdomain = cust.load_subdomain if cust.has_key?(:cname)
        if self.subdomain
          self[:from_name] = subdomain['contact']
          self[:from] = subdomain['email']
          self[:signature_link] = subdomain['homepage']
          emailer.from = self[:from]
          emailer.fromname = self[:from_name]
        else
          self[:from_name] = OT.conf[:emailer][:fromname]
          self[:from] = OT.conf[:emailer][:from]
          self[:signature_link] = 'https://onetimesecret.com/'
          emailer.fromname = 'Onetime Secret'
        end
      end
      def subject
        i18n[:email][:subject] % [self[:from]]
      end
      def verify_uri
        secret_uri self[:secret]
      end
    end
    class PasswordRequest < OT::Email
      def init secret
        self[:secret] = secret
        self[:email_address] = cust.email
      end
      def subject
        "Reset your password (OneTimeSecret.com)"
      end
      def forgot_path
        '/forgot/%s' % self[:secret].key
      end
    end
    class IncomingSupport < OT::Email
      attr_accessor :ticketno
      def init secret, recipient
        self[:secret] = secret
        self[:custid] = cust.custid
        self[:email_address] = recipient
        self.subdomain = cust.load_subdomain if cust.has_key?(:cname)
      end
      def subject
        puts [self[:ticketno], i18n[:email]]
        i18n[:email][:subject] % [self[:ticketno]]
      end
      def verify_uri
        secret_uri self[:secret]
      end
    end
    class TestEmail < OT::Email
      def init
        self[:email_address] = cust.email
      end
      def subject
        "This is a test email #{OT.now}"
      end
      def test_variable
        'test_value'
      end
    end
  end
end
