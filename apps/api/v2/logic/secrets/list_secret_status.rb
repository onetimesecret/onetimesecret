# apps/api/v2/logic/secrets/list_secret_status.rb

module V2::Logic
  module Secrets
    using Familia::Refinements::TimeLiterals

    class ListSecretStatus < V2::Logic::Base
      attr_reader :identifiers

      def process_params
        @identifiers    = params[:identifiers].to_s.strip.downcase.gsub(/[^a-z0-9,]/, '').split(',').compact
        @secrets = identifiers.map do |identifier|
          next unless identifier

          record = Onetime::Secret.load(identifier)
          next unless record

          record.safe_dump
        end.compact
      end

      def raise_concerns; end

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
