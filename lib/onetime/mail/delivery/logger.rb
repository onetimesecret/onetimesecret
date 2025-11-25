# lib/onetime/mail/delivery/logger.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Delivery
      # Logger delivery backend for development and testing.
      # Outputs email content to logs instead of sending.
      #
      class Logger < Base
        def deliver(email)
          email = normalize_email(email)

          output = <<~EMAIL
            === EMAIL (Logger) ===
            To: #{email[:to]}
            From: #{email[:from]}
            Reply-To: #{email[:reply_to] || '(none)'}
            Subject: #{email[:subject]}
            --- Text Body ---
            #{email[:text_body]}
            --- HTML Body ---
            #{email[:html_body].to_s.empty? ? '(none)' : email[:html_body]}
            === END EMAIL ===
          EMAIL

          # Log using OT if available, otherwise puts
          if defined?(OT) && OT.respond_to?(:info)
            OT.info output
          else
            puts output
          end
          log_delivery(email, 'logged')

          # Return a simple success indicator
          { status: 'logged', to: email[:to] }
        end
      end
    end
  end
end
