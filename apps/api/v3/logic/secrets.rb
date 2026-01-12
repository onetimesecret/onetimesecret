# apps/api/v3/logic/secrets.rb
#
# frozen_string_literal: true

# V3 Secret Logic Classes
#
# Inherits from V2 logic but uses JSON-type serialization via V3::Logic::Base.
# Includes all secret operations (create, reveal, metadata, burn).
# No business logic changes needed - only serialization format differs.
#
# Guest route gating is enforced for operations that support anonymous access:
# - ConcealSecret: guest conceal toggle
# - GenerateSecret: guest generate toggle
# - RevealSecret: guest reveal toggle
# - BurnSecret: guest burn toggle
# - ShowSecret: guest show toggle
# - ShowReceipt: guest receipt toggle

require_relative '../../v2/logic/secrets'
require_relative 'base'

module V3
  module Logic
    module Secrets
      # Conceal a secret (create from user-provided value)
      class ConcealSecret < V2::Logic::Secrets::ConcealSecret
        include Onetime::Logic::GuestRouteGating

        def raise_concerns
          require_guest_route_enabled!(:conceal)
          super
        end
      end

      # Generate a secret (create from system-generated value)
      class GenerateSecret < V2::Logic::Secrets::GenerateSecret
        include Onetime::Logic::GuestRouteGating

        def raise_concerns
          require_guest_route_enabled!(:generate)
          super
        end
      end

      # Reveal a secret (decrypt and return value)
      # Extended to notify owner when their secret is revealed
      class RevealSecret < V2::Logic::Secrets::RevealSecret
        include Onetime::Logic::GuestRouteGating

        def raise_concerns
          require_guest_route_enabled!(:reveal)
          super
        end

        def process
          result = super

          # Only notify on actual reveal (not verification flow)
          # show_secret is set in parent class when secret is actually shown
          notify_owner_of_reveal if show_secret && !verification

          result
        end

        private

        # Send notification to secret owner if they have opted in
        def notify_owner_of_reveal
          owner = secret.load_owner
          return if owner.nil? || owner.anonymous?
          return unless owner.email.to_s.present?
          return unless owner.notify_on_reveal?

          Onetime::Jobs::Publisher.enqueue_email(
            :secret_revealed,
            {
              recipient: owner.email,
              secret_shortid: secret.shortid,
              revealed_at: Time.now.utc.iso8601,
              locale: owner.locale.to_s.empty? ? OT.default_locale : owner.locale,
            },
          )
        rescue StandardError => ex
          # Log but don't fail the reveal - notification is non-critical
          secret_logger.error "[RevealSecret] Failed to notify owner: #{ex.message}"
        end
      end

      # Show secret metadata without revealing value
      class ShowSecret < V2::Logic::Secrets::ShowSecret
        include Onetime::Logic::GuestRouteGating

        def raise_concerns
          require_guest_route_enabled!(:show)
          super
        end
      end

      # Show secret status
      class ShowSecretStatus < V2::Logic::Secrets::ShowSecretStatus
        # include ::V3::Logic::Base
      end

      # List secret status for multiple identifiers
      class ListSecretStatus < V2::Logic::Secrets::ListSecretStatus
        # include ::V3::Logic::Base
      end

      # List user's receipts (recent secrets - receipt/private)
      class ListReceipts < V2::Logic::Secrets::ListReceipts
        # include ::V3::Logic::Base
      end

      # Burn a secret
      class BurnSecret < V2::Logic::Secrets::BurnSecret
        include Onetime::Logic::GuestRouteGating

        def raise_concerns
          require_guest_route_enabled!(:burn)
          super
        end
      end

      # Show receipt for a secret (receipt/private endpoints)
      class ShowReceipt < V2::Logic::Secrets::ShowReceipt
        include Onetime::Logic::GuestRouteGating

        def raise_concerns
          require_guest_route_enabled!(:receipt)
          super
        end
      end
    end
  end
end
