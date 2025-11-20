# .purgatory/lib-onetime-mail/mailer/base_mailer.rb
#
# frozen_string_literal: true

module Onetime
  module Mail
    module Mailer
      class BaseMailer
        attr_accessor :reply_to
        attr_reader :from, :from_name

        def initialize(from, from_name, reply_to = nil)
          OT.ld "[mail-init] from:#{from}, from_name:#{from_name}, reply-to:#{reply_to}"
          @from     = from
          @from_name = from_name
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
