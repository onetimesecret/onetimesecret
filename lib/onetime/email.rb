require 'byebug'

require 'mustache'
require 'mail'
require 'sendgrid-ruby'


module Onetime
   MAIL_ERROR = """
    We're experiencing an email delivery issues. You can
    <a href='mailto:problems@onetimesecret.com'>let us know.</a>
    """

  class BaseEmailer
    attr_accessor :from, :fromname
    def initialize from, fromname=nil
      @from, @fromname = from, fromname
      OT.info "[initialize]"
    end

    def send_email to_address, subject, content
      raise NotImplementedError
    end

    def self.setup
      raise NotImplementedError
    end
  end

  class SendGridEmailer < BaseEmailer
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
  class SMTPEmailer < BaseEmailer
    def send_email to_address, subject, content
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
        mailer_response = Mail.deliver do
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
      rescue => ex
        OT.info "> [send-exception-sending] #{obscured_address}"
        OT.ld "#{ex.class} #{ex.message}\n#{ex.backtrace}"
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
      Mail.defaults do
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
  require 'onetime/app/web/views/helpers'
  class Email < Mustache
    include Onetime::App::Views::Helpers
    self.template_path = './templates/email'
    self.view_namespace = Onetime::Email
    self.view_path = './onetime/email'
    attr_reader :cust, :locale, :emailer, :mode, :from, :to
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
    def deliver_email
      errmsg = "Your message wasn't sent because we have an email problem"

      begin
        email_address_obscured = OT::Utils.obscure_email self[:email_address]
        OT.info "Emailing #{email_address_obscured} [#{self.class}]"
        ret = emailer.send_email self[:email_address], subject, render
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
