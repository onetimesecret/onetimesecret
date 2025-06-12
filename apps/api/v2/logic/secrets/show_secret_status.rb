# apps/api/v2/logic/secrets/show_secret_status.rb

module V2::Logic
  module Secrets
    class ShowSecretStatus < V2::Logic::Base
      attr_reader :key, :realttl
      attr_reader :secret, :verification

      def process_params
        @key = params[:key].to_s
        @secret = V2::Secret.load key
      end

      def raise_concerns
        limit_action :show_secret
      end

      def process
        @realttl = secret.realttl unless secret.nil?
      end

      def success_data
        ret = if secret.nil?
          { record: { state: 'unknown' } }
        else
          { record: secret.safe_dump, details: { realttl: realttl } }
        end

        ret
      end
    end
  end
end
