# apps/api/v2/logic/secrets/list_secret_status.rb
#
# frozen_string_literal: true

module V2::Logic
  module Secrets
    using Familia::Refinements::TimeLiterals

    # List Secret Status
    #
    # @api Retrieves the status of multiple secrets in a single request.
    #   Accepts a comma-separated list of secret identifiers and returns
    #   each secret's current state and metadata. Does not consume or
    #   reveal any secret values.
    class ListSecretStatus < V2::Logic::Base
      SCHEMAS = { response: 'secretList' }.freeze

      attr_reader :identifiers, :secrets

      def process_params
        @identifiers      = params['identifiers'].to_s.strip.split(',').map { |id| sanitize_identifier(id) }.compact
        # Filter out empty identifiers first, then use optimized bulk loading
        valid_identifiers = identifiers.reject(&:empty?)
        secret_objects    = Onetime::Secret.load_multi(valid_identifiers).compact
        @secrets          = secret_objects.map(&:safe_dump)
      end

      def raise_concerns
        require_entitlement!('api_access')
      end

      def process
        # We don't get the actual TTL value for batches of secrets
        # since that would double the calls to the database.

        success_data
      end

      def success_data
        if secrets.nil?
          { records: [], count: 0 }
        else
          { records: secrets, count: secrets.length }
        end
      end
    end
  end
end
