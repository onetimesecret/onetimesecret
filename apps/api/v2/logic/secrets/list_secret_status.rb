# apps/api/v2/logic/secrets/list_secret_status.rb

module V2::Logic
  module Secrets
    class ListSecretStatus < V2::Logic::Base
      attr_reader :keys

      def process_params
        @keys    = params[:keys].to_s.strip.downcase.gsub(/[^a-z0-9,]/, '').split(',').compact
        @secrets = keys.map do |key|
          next unless key

          record = V2::Secret.load(key)
          next unless record

          record.safe_dump
        end.compact
      end

      def raise_concerns; end

      def process
        # We don't get the actual TTL value for batches of secrets
        # since that would double the calls to the database.
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
