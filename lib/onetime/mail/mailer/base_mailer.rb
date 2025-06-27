# lib/onetime/mail/mailer/base_mailer.rb

require 'onetime/refinements/indifferent_hash_access'

module Onetime
  module Mail
    module Mailer
      class BaseMailer
        using Onetime::IndifferentHashAccess

        attr_accessor :reply_to
        attr_reader :from, :fromname

        class << self
          # These are set during boot by setup class method
          attr_reader :mail_settings, :mail_domain
        end

        def initialize(from, fromname, reply_to = nil)
          OT.ld "[mail-init] from:#{from}, fromname:#{fromname}, reply-to:#{reply_to}"
          @from     = from
          @fromname = fromname
          @reply_to = reply_to
        end

        def send_email(to_address, subject, html_content, text_content)
          raise NotImplementedError
        end

        def self.clear
          raise NotImplementedError
        end

        # Implementing classes are expected to set the mail_settings and
        # mail_domain class attributes using the config hash. e.g.
        #
        #   @mail_settings = config['mail']['connection']
        #   @mail_domain   = config['site']['domain']
        #
        def self.setup(config)
          raise NotImplementedError
        end
      end
    end
  end
end
