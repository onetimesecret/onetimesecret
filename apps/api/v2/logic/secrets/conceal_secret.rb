# apps/api/v2/logic/secrets/conceal_secret.rb
#
# frozen_string_literal: true

require_relative 'base_secret_action'

module V2::Logic
  module Secrets
    using Familia::Refinements::TimeLiterals

    # Conceal Secret
    #
    # @api Creates a new secret from user-provided content. Accepts the secret
    #   value, an optional passphrase, TTL, recipient email, and share domain.
    #   Returns the receipt and secret records with share URLs.
    class ConcealSecret < BaseSecretAction
      SCHEMAS = { response: 'concealData', request: 'concealSecret' }.freeze

      def process_secret
        @kind         = 'conceal'
        @secret_value = payload['secret']
      end

      def raise_concerns
        super
        raise_form_error 'You did not provide anything to share' if secret_value.to_s.empty?
      end
    end
  end
end
