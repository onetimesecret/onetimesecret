# lib/onetime/mail/delivery/disabled.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Delivery
      # No-op delivery backend for instances that intentionally have no email delivery.
      #
      # Useful for:
      #   - SSO-only deployments with AUTH_AUTOVERIFY=true
      #   - Air-gapped or internal instances without outbound SMTP
      #   - Staging/testing environments
      #
      # Enable with EMAILER_MODE=disabled (or EMAILER_MODE=none).
      # All delivery attempts succeed silently with no side effects.
      #
      class Disabled < Base
        def perform_delivery(_email)
          nil
        end

        def delivery_log_status
          'skipped'
        end

        private

        def validate_config!
          # No config required
        end
      end
    end
  end
end
