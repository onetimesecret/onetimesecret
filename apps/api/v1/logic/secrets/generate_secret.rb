# apps/api/v1/logic/secrets/generate_secret.rb

require_relative './base_secret_action'

module V1::Logic
  module Secrets
    class GenerateSecret < BaseSecretAction

      def process_secret
        @kind = :generate
        @secret_value = Onetime::Utils.strand(12)
      end

    end
  end
end
