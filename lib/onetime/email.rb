require 'mustache'

module Onetime
  require 'onetime/app/web/views/helpers'
  class Email < Mustache
    include Onetime::App::Views::Helpers
    self.template_path = './templates/email'
    self.view_namespace = Onetime::Email
    self.view_path = './onetime/email'
    attr_reader :cust, :emailer
    def initialize cust, *args
      @cust = cust
      emailer_opts = OT.conf[:emailer].values_at :account, :password, :from, :fromname, :bcc
      @emailer = SendGrid.new *emailer_opts
      init *args if respond_to? :init
    end
    def deliver_email
      #OT.ld "Emailing #{self[:email_address]} [#{self.class}]"
      ret = emailer.send self[:email_address], subject, render
      # TODO: 
      #raise OT::Problem if ret.code != 200
    end
    class Welcome < OT::Email
      def init secret
        self[:secret] = secret
        self[:email_address] = cust.email
      end
      def subject
        "Verify your One-time Secret account"
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
          self[:from_name] = 'Delano, co-founder'
          self[:signature_link] = 'https://onetimesecret.com/'
          emailer.fromname = 'One-Time Secret'
          self[:from] = cust.custid
        end
      end
      def subject
        "#{self[:from]} sent you a secret"
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
  end
end
