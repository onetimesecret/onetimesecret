require_relative 'v2/base'

class Onetime::App
  class API2
    include Onetime::App::API2::Base

    def status
      sess.event_incr!(:check_status)
      { status: :nominal, locale: locale }
    end

    def version
      sess.event_incr!(:check_version) # TODO: Better to count implicitly for simple counters to avoid forgetting.
      { version: OT::VERSION, locale: locale }
    end

    def create
      # @apidoc
      # @name Create Secret
      # @url /api/v2/secret/create
      # @method POST
      #
      # @example
      # curl -X POST \
      #    -H "Content-Type: application/json" \
      #    -H "Authorization: Bearer APIKEY" \
      #    -d '{"ttl": 7200, "secret": "Enjoy every sandwich"}' \
      #    http://127.0.0.1:7143/api/v2/secret/create
      #
      # @description Create a new secret with a specified Time To Live (TTL).
      #
      # @auth This method requires authentication.
      #
      # @parameter [Integer] ttl The Time To Live for the secret in seconds.
      # @parameter [String] secret The secret message to be stored.
      #
      # @response_field [String] secret_key The unique identifier for the created secret.
      # @response_field [String] secret_url The URL to access the secret.
      # @response_field [Integer] ttl The Time To Live for the secret in seconds.
      # @response_field [String] state The current state of the secret (e.g., "new").
      #
      # @error 400 Invalid parameters
      # @error 401 Unauthorized
      #
      # curl -X POST \
      #    -H "Content-Type: application/json" \
      #    -H "Authorization: Bearer APIKEY" \
      #    -d '{"ttl": 7200, "secret": "Enjoy every sandwich"}' \
      #    http://127.0.0.1:7143/api/v2/secret/create
      #
      #
      req.params[:kind] = :share
      logic = OT::Logic::CreateSecret.new(sess, cust, req.params, locale)
      logic.raise_concerns
      logic.process
      if req.get?
        res.redirect app_path(logic.redirect_uri)
      else
        secret = logic.secret
        json metadata_hsh(logic.metadata,
                          secret_ttl: secret.realttl,
                          passphrase_required: secret&.has_passphrase?)
      end
    end
  end
end
