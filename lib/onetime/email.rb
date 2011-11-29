require 'mustache'

module Onetime
  #require 'onetime/app/web/views/helpers'
  class Email < Mustache
    #include Onetime::Views::Helpers
    self.template_path = './templates/email'
    self.view_namespace = Onetime::Email
    self.view_path = './onetime/email'
    def initialize *args
      init *args if respond_to? :init
    end
    class Welcome < OT::Email
      def init
        self[:poop] = :hihi
      end
    end
  end
end