require 'mustache'

module Onetime
  require 'onetime/app/web/views/helpers'
  class Email < Mustache
    include Onetime::Views::Helpers
    self.template_path = './templates/email'
    self.view_namespace = Onetime::Email
    self.view_path = './onetime/email'
    attr_reader :cust
    def initialize cust, *args
      @cust = cust
      init *args if respond_to? :init
    end
    def send_email
    end
    class Welcome < OT::Email
      def init
        self[:subject] = "Verify your One-time Secret account"
        self[:secret] = secret
        
      end
      def verify_uri
        secret_uri self[:secret]
      end
    end
  end
end