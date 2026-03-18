# apps/api/v3/logic/secrets.rb
#
# frozen_string_literal: true

# V3 Secret Logic Classes
#
# Inherits from V2 logic but uses JSON-type serialization via V3::Logic::Base.
# Includes all secret operations (create, reveal, receipt, burn).
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
      # V3 uses modern "receipt" terminology exclusively.
      # This module removes the legacy "metadata" key from V2 responses.
      module ModernResponseFormat
        def success_data
          data = super
          return data unless data.is_a?(Hash)

          # Remove legacy "metadata" key from record (V3 uses "receipt" only)
          if data[:record].is_a?(Hash)
            data[:record].delete(:metadata)
            data[:record].delete('metadata')
          end

          data
        end
      end

      # Conceal a secret (create from user-provided value)
      #
      # @api Store a user-provided secret value and return share metadata
      #   including a secret link for the recipient and a receipt link for
      #   the creator. The secret can only be retrieved once before it is
      #   permanently destroyed.
      class ConcealSecret < V2::Logic::Secrets::ConcealSecret
        include ModernResponseFormat
        include Onetime::Logic::GuestRouteGating

        SCHEMAS = { response: 'concealData', request: 'concealSecret' }.freeze

        def raise_concerns
          require_guest_route_enabled!(:conceal)
          super
        end
      end

      # Generate a secret (create from system-generated value)
      #
      # @api Generate a random secret value using configurable character sets
      #   and length, then return share metadata including a secret link and
      #   a receipt link. The generated value can only be retrieved once.
      class GenerateSecret < V2::Logic::Secrets::GenerateSecret
        include ModernResponseFormat
        include Onetime::Logic::GuestRouteGating

        SCHEMAS = { response: 'concealData', request: 'generateSecret' }.freeze

        def raise_concerns
          require_guest_route_enabled!(:generate)
          super
        end
      end

      # Reveal a secret (decrypt and return value)
      # Extended to notify owner when their secret is revealed
      #
      # @api Retrieve and decrypt a secret value. The secret is permanently
      #   destroyed immediately after retrieval and cannot be accessed again.
      #   Requires a passphrase if one was set during creation. The secret
      #   owner is optionally notified when the secret is revealed.
      class RevealSecret < V2::Logic::Secrets::RevealSecret
        include Onetime::Logic::GuestRouteGating

        SCHEMAS = { response: 'secret' }.freeze

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

      # Show secret receipt without revealing value
      #
      # @api Return metadata about a secret without revealing its value.
      #   Includes state, expiration details, and whether a passphrase is
      #   required. Marks the secret as previewed on first access.
      class ShowSecret < V2::Logic::Secrets::ShowSecret
        include Onetime::Logic::GuestRouteGating

        SCHEMAS = { response: 'secret' }.freeze

        def raise_concerns
          require_guest_route_enabled!(:show)
          super
        end
      end

      # Show secret status
      #
      # @api Check the current status of a secret by its identifier.
      #   Returns the secret's state and expiration details, or an
      #   unknown state if the secret does not exist.
      class ShowSecretStatus < V2::Logic::Secrets::ShowSecretStatus
        SCHEMAS = { response: 'secret' }.freeze

        # include ::V3::Logic::Base
      end

      # List secret status for multiple identifiers
      #
      # @api Retrieve the status of multiple secrets in a single request.
      #   Accepts a comma-separated list of secret identifiers and returns
      #   their current state and metadata.
      class ListSecretStatus < V2::Logic::Secrets::ListSecretStatus
        SCHEMAS = { response: 'secretList' }.freeze

        # include ::V3::Logic::Base
      end

      # List user's receipts (recent secrets - receipt/private)
      #
      # @api List receipts for the authenticated user's recent secrets.
      #   Returns receipts from the last 30 days, sorted by most recently
      #   updated. Supports scoping by organization or custom domain.
      class ListReceipts < V2::Logic::Secrets::ListReceipts
        SCHEMAS = { response: 'receiptList' }.freeze

        # include ::V3::Logic::Base
      end

      # Burn a secret
      #
      # @api Permanently destroy a secret before it has been revealed.
      #   Requires a passphrase if one was set during creation. Returns
      #   the updated receipt confirming the secret has been burned.
      class BurnSecret < V2::Logic::Secrets::BurnSecret
        include Onetime::Logic::GuestRouteGating

        SCHEMAS = { response: 'receipt' }.freeze

        def raise_concerns
          require_guest_route_enabled!(:burn)
          super
        end
      end

      # Show receipt for a secret (receipt/private endpoints)
      #
      # @api Retrieve a receipt with full details about a secret's lifecycle,
      #   including share and burn URLs, expiration, and current state. On
      #   first access, may include the generated secret value briefly.
      class ShowReceipt < V2::Logic::Secrets::ShowReceipt
        include Onetime::Logic::GuestRouteGating

        SCHEMAS = { response: 'receipt' }.freeze

        def raise_concerns
          require_guest_route_enabled!(:receipt)
          super
        end
      end

      # Show multiple receipts for guest users (batch status check)
      #
      # @api Retrieve multiple receipts in a single request by providing an
      #   array of receipt identifiers. Returns up to 25 receipts per
      #   request. Useful for checking the status of several secrets at once.
      class ShowMultipleReceipts < V2::Logic::Base
        include Onetime::Logic::GuestRouteGating

        SCHEMAS = { response: 'receiptList' }.freeze

        # Maximum receipt identifiers per batch request
        MAX_RECEIPT_IDENTIFIERS_PER_BATCH = 25

        attr_reader :identifiers, :records

        def process_params
          # Accept JSON array of identifiers
          raw          = params['identifiers']
          @identifiers = case raw
                         when Array
                           raw.map { |id| id.to_s.strip.downcase.gsub(/[^a-z0-9]/, '') }
                         when String
                           raw.strip.downcase.gsub(/[^a-z0-9,]/, '').split(',')
                         else
                           []
                         end.compact.reject(&:empty?)
        end

        def raise_concerns
          require_guest_route_enabled!(:receipt)
          return if identifiers.length <= MAX_RECEIPT_IDENTIFIERS_PER_BATCH

          raise_form_error("Too many identifiers (max #{MAX_RECEIPT_IDENTIFIERS_PER_BATCH})")
        end

        def process
          receipt_objects = Onetime::Receipt.load_multi(identifiers).compact
          @records        = receipt_objects.map(&:safe_dump)
          success_data
        end

        def success_data
          { records: records, count: records.length }
        end
      end

      # Update receipt (memo field)
      #
      # @api Update the memo field on a receipt owned by the authenticated
      #   user. Returns the updated receipt record.
      class UpdateReceipt < V2::Logic::Secrets::UpdateReceipt
        SCHEMAS = { response: 'receipt' }.freeze

        # include ::V3::Logic::Base
      end
    end
  end
end
