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
        def perform_delivery(email)
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

          # Log straight to standard out, bypassing our centralized semantic
          # logger. This avoids confusing scenarios where nothing appears in
          # the logs b/c the log level was set incorrectly.
          puts output

          # Return a simple success indicator
          { status: 'logged', to: email[:to] }
        end

        def delivery_log_status
          'logged'
        end
      end
    end
  end
end
