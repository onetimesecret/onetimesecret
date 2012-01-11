require 'mustache'

module Onetime
  require 'onetime/app/web/views/helpers'
  class Email < Mustache
    include Onetime::App::Views::Helpers
    self.template_path = './templates/email'
    self.view_namespace = Onetime::Email
    self.view_path = './onetime/email'
    attr_reader :cust
    def initialize cust, *args
      @cust = cust
      init *args if respond_to? :init
    end
    def deliver_email
      #OT.ld "Emailing #{self[:email_address]} [#{self.class}]"
      ret = OT.emailer.send self[:email_address], subject, render
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
          self[:signature_link] = subdomain['homepage']
        else 
          self[:from_name] = 'Chris, co-founder'
          self[:signature_link] = 'https://onetimesecret.com/'
        end
      end
      def subject
        "#{self[:custid]} sent you a secret"
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