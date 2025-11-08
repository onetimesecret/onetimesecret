# apps/api/v2/logic/secrets/show_secret_status.rb
#
# frozen_string_literal: true

module V2::Logic
  module Secrets
    using Familia::Refinements::TimeLiterals

    class ShowSecretStatus < V2::Logic::Base
      attr_reader :identifier, :current_expiration, :secret, :verification

      def process_params
        @identifier = params['identifier'].to_s
        @secret     = Onetime::Secret.load identifier
      end

      def raise_concerns; end

      def process
        @current_expiration = secret.current_expiration unless secret.nil?

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
