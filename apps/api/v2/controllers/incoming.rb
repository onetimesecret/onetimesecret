# apps/api/v2/controllers/incoming.rb

require_relative 'base'
require_relative '../logic/incoming'

module V2
  module Controllers
    class Incoming
      include V2::Controllers::Base

      @check_utf8 = true
      @check_uri_encoding = true

      def get_config
        retrieve_records(V2::Logic::Incoming::GetConfig, allow_anonymous: true)
      end

      def create_secret
        process_action(
          V2::Logic::Incoming::CreateIncomingSecret,
          "Incoming secret created successfully.",
          "Incoming secret could not be created.",
          allow_anonymous: true,
        )
      end

      def validate_recipient
        retrieve_records(V2::Logic::Incoming::ValidateRecipient, allow_anonymous: true)
      end
    end
  end
end
