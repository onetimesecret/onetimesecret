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
      ret = OT.emailer.send cust.email, subject, render
      p [cust.email, subject, ret.class, ret.code]
    end
    class Welcome < OT::Email
      def init secret
        self[:secret] = secret
      end
      def subject
        "Verify your One-time Secret account"
      end
      def verify_uri
        secret_uri self[:secret]
      end
    end
  end
end