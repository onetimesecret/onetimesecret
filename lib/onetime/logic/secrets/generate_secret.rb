# lib/onetime/logic/secrets/generate_secret.rb
require_relative './base_secret_action'

module Onetime::Logic
  module Secrets
    class GenerateSecret < BaseSecretAction

      def process_secret
        @kind = :generate
        @secret_value = Onetime::Utils.strand(12)
      end

    end
  end
end
