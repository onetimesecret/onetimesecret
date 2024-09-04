
require 'json'
require 'base64'

require_relative 'base'
require_relative '../../app_settings'


class Onetime::App
  class APIV2
    include AppSettings
    include Onetime::App::APIV2::Base

    def status
      json status: :nominal, locale: locale
    end

    def version
      json version: OT::VERSION.to_a, locale: locale
    end

    # NOTE: Based on https://github.com/altcha-org/altcha-starter-rb
    #
    # When running externally, integrating the Altcha endpoints relies
    # on the CORS settings being amenable to the situation. Incorporating
    # the endpoints into our API avoids that.
    #
    # e.g.
    #   'Access-Control-Allow-Origin' => '*',
    #   'Access-Control-Allow-Methods' => %w[GET POST OPTIONS],
    #   'Access-Control-Allow-Headers' => '*'
    #
    def altcha_challenge
      publically do
        # The library defaults to 1_000_000, we default to 100_000 in the
        # generate method. Let's start with an even easier challenge and
        # work our way up.
        max_number = 50_000
        challenge = self.class.generate_authenticity_challenge(max_number)
        json challenge
      end
    end

    def altcha_verify
      publically do
        payload = params['authenticity_payload']
        error_response message: 'Altcha payload missing' if payload.nil?

        verified = Altcha.verify_solution(payload, self.class.secret_key)
        if verified
          json data: params
        else
          error_response message: 'Invalid Altcha payload'
        end
      end
    end

    def altcha_verify_spam
      publically do
        payload = params['authenticity_payload']
        error_response message: 'Altcha payload missing' if payload.nil?

        verified, verification_data = Altcha.verify_server_signature(
          payload,
          self.class.secret_key
        )
        fields_verified = Altcha.verify_fields_hash(
          params,
          verification_data.fields,
          verification_data.fields_hash,
          'SHA-256'
        )

        if verified && fields_verified
          { success: true, form_data: params, verification_data: verification_data }.to_json
        else
          error_response message: 'Invalid Altcha payload'
        end
      end
    end

    def self.secret_key
      OT.conf.dig(:site, :authenticity, :secret_key) # ALTCHA_HMAC_KEY
    end
  end
end
