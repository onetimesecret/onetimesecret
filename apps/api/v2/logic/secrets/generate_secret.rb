# apps/api/v2/logic/secrets/generate_secret.rb

require_relative 'base_secret_action'

module V2::Logic
  module Secrets
    class GenerateSecret < BaseSecretAction

      def process_secret
        @kind = :generate
        @secret_value = Onetime::Utils.strand(12)
      end

    end
  end
end
