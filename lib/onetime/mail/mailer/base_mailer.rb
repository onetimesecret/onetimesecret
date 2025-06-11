# lib/onetime/mail/mailer/base_mailer.rb

require 'onetime/refinements/hash_refinements'

module Onetime
  module Mail
    module Mailer

      class BaseMailer
        attr_accessor :reply_to
        attr_reader :from, :fromname

        using IndifferentHashAccess

        def initialize(from, fromname, reply_to = nil)
          OT.ld "[mail-init] from:#{from}, fromname:#{fromname}, reply-to:#{reply_to}"
          @from = from
          @fromname = fromname
          @reply_to = reply_to
        end

        def send_email(to_address, subject, html_content, text_content)
          raise NotImplementedError
        end

        def self.clear
          raise NotImplementedError
        end

        def self.setup
          raise NotImplementedError
        end
      end

    end
  end
end
