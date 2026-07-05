# apps/api/v2/logic/secrets/show_secret_status.rb
#
# frozen_string_literal: true

module V2::Logic
  module Secrets
    using Familia::Refinements::TimeLiterals

    # Show Secret Status
    #
    # @api Checks whether a secret exists and returns its current state
    #   without consuming it or changing it. Returns the secret's metadata
    #   including expiration details, or a state of "unknown" if the secret
    #   does not exist. The access is recorded as telemetry on the secret's
    #   receipt, visible to the secret's creator.
    class ShowSecretStatus < V2::Logic::Base
      include AccessTelemetry

      SCHEMAS = { response: 'secretStatus' }.freeze

      attr_reader :identifier, :current_expiration, :secret, :verification

      def process_params
        @identifier = sanitize_identifier(params['identifier'].to_s)
        @secret     = Onetime::Secret.load identifier
      end

      def raise_concerns
        require_entitlement!('api_access')
      end

      def process
        @current_expiration = secret.current_expiration unless secret.nil?

        # A status check reads the secret's state; it must not advance it
        # (GET is a safe method, #3633). The fetch is recorded on the
        # receipt's access timeline instead.
        record_access_telemetry('status_get')

        success_data
      end

      def success_data
        if secret.nil?
          { record: { state: 'unknown' } }
        else
          { record: secret.safe_dump, details: { current_expiration: @current_expiration } }
        end
      end
    end
  end
end
