# apps/api/v2/logic/secrets/show_secret_status.rb

module V2::Logic
  module Secrets
    class ShowSecretStatus < V2::Logic::Base
      attr_reader :key, :realttl, :secret, :verification

      def process_params
        @key    = params[:key].to_s
        @secret = V2::Secret.load key
      end

      def raise_concerns
        limit_action :show_secret
      end

      def process
        @realttl = secret.current_expiration unless secret.nil?
      end

      def success_data
        if secret.nil?
          { record: { state: 'unknown' } }
        else
          { record: secret.safe_dump, details: { current_expiration: current_expiration } }
        end
      end
    end
  end
end
