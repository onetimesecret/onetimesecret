require 'mustache'
require 'mail'

module Onetime
  class SMTP
    attr_accessor :from, :fromname
    def initialize from, fromname=nil
      @from, @fromname = from, fromname
    end
    def send to_address, subject, content
      mail = Mail.new
      mail.to to_address
      mail.from self.from
      mail.subject subject
      mail.html_part do
        content_type 'text/html; charset=UTF-8'
        body content
      end
      mail.deliver
    end
    def self.setup
      Mail.defaults do
        opts = { :address   => OT.conf[:emailer][:host] || 'localhost',
                 :port      => OT.conf[:emailer][:port] || 587  ,
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
  require 'onetime/app/web/views/helpers'
  class Email < Mustache
    include Onetime::App::Views::Helpers
    self.template_path = './templates/email'
    self.view_namespace = Onetime::Email
    self.view_path = './onetime/email'
    attr_reader :cust, :locale, :emailer, :mode
    def initialize cust, locale, *args
      @cust, @locale = cust, locale
      OT.ld "#{self.class} locale is: #{locale.to_s}"
      @mode = OT.conf[:emailer][:mode]
      if @mode == :sendgrid
        emailer_opts = OT.conf[:emailer].values_at :account, :password, :from, :fromname, :bcc
        @emailer = SendGrid.new *emailer_opts
      else
        OT.ld "[mail-smtp-from] #{OT.conf[:emailer][:from]}"
        @emailer = OT::SMTP.new OT.conf[:emailer][:from]
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
        COMMON: OT.locales[locale][:email][:COMMON]
      }
    end
    def deliver_email
      errmsg = "Your message wasn't sent because we have an email problem"
      begin
        email_address_obscured = OT::Utils.obscure_email self[:email_address]
        OT.info "Emailing #{email_address_obscured} [#{self.class}]"
        ret = emailer.send self[:email_address], subject, render
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
          self[:from_name] = 'Delano'
          self[:signature_link] = 'https://onetimesecret.com/'
          emailer.fromname = 'One-Time Secret'
          self[:from] = cust.custid
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
