require 'mustache'

module Onetime
  #require 'onetime/app/web/views/helpers'
  class Email < Mustache
    #include Onetime::Views::Helpers
    module Views
    end
    self.template_path = './templates/email'
    self.view_namespace = Onetime::Email::Views
    self.view_path = './onetime/email/views'
    def initialize *args
      init *args if respond_to? :init
    end
    module Views
      class Welcome < OT::Email
        p self
        def init
          self[:poop] = :hihi
        end
      end
    end
  end
end