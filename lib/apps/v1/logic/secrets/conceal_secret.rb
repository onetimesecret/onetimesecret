# lib/onetime/logic/secrets/conceal_secret.rb

require_relative './base_secret_action'

module V1::Logic
  module Secrets
    class ConcealSecret < BaseSecretAction

      def process_secret
        @kind = :conceal
        @secret_value = payload[:secret]
      end

      def raise_concerns
        super
        raise_form_error "You did not provide anything to share" if secret_value.to_s.empty?
      end

    end
  end
end
