# apps/api/v2/controllers/challenges.rb

require 'json'
require 'base64'

require 'altcha'
require_relative 'base'
require_relative 'settings'


module V2
  module Controllers
    class Challenges
      include V2::ControllerSettings
      include V2::ControllerBase

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
          payload = req.params['authenticity_payload']
          error_response message: 'Altcha payload missing' if payload.nil?

          verified = Altcha.verify_solution(payload, self.class.secret_key)
          if verified
            json data: req.params
          else
            error_response message: 'Invalid Altcha payload'
          end
        end
      end

      def altcha_verify_spam
        publically do
          payload = req.params['authenticity_payload']
          error_response message: 'Altcha payload missing' if payload.nil?

          # When verified=false, verification_data can be nil
          verified, verification_data = Altcha.verify_server_signature(
            payload,
            self.class.secret_key,
          )


          return error_response message: 'Bad Altcha payload' unless verified

          fields_verified = Altcha.verify_fields_hash(
            req.params,
            verification_data.fields,
            verification_data.fields_hash,
            'SHA-256',
          )

          if fields_verified
            { success: true, form_data: req.params, verification_data: verification_data }.to_json
          else
            error_response message: 'Invalid Altcha payload'
          end
        end
      end

      def self.secret_key
        OT.conf.dig(:site, :authenticity, :secret_key) # ALTCHA_HMAC_KEY
      end

      module ClassMethods
        def secret_key
          OT.conf.dig(:site, :authenticity, :secret_key)
        end

        # This challenge is then serializd into a JSON string and base64 encoded
        # by the AltchaChallenge and then resubmitted with the solution
        # number for verification (aka the "payload")
        def generate_authenticity_challenge(max_number=100_000)
          options = Altcha::ChallengeOptions.new
          options.max_number = max_number # 1m is the lib default
          options.hmac_key = secret_key
          Altcha.create_challenge(options)
        end

        # See: https://github.com/altcha-org/altcha-lib-rb
        def solve_authenticity_challenge(challenge, salt, algorithm, max, start)
          # Solves a challenge by iterating over possible solutions.
          # @param challenge [String] The challenge to solve.
          # @param salt [String] The salt used in the challenge.
          # @param algorithm [String] The hashing algorithm used.
          # @param max [Integer] The maximum number to try.
          # @param start [Integer] The starting number to try.
          # @return [Solution, nil] The solution if found, or nil if not.
          Altcha.solve_challenge(challenge, salt, algorithm, max, start)
        end

        def verify_authenticity_challenge(challenge, number, check_expires)
          hmac_key = secret_key
          payload = _authenticity_challenge_payload(challenge, number)
          Altcha.verify_solution(payload, hmac_key, check_expires)
        end

        # Like the challenge, this hash is serialized to JSON and base64
        # encoded. This payload is then ready to be verified by the server.
        def _authenticity_challenge_payload(challenge, number)
          {
            algorithm: challenge.algorithm,
            challenge: challenge.challenge,
            number: number,
            salt: challenge.salt,
            signature: challenge.signature
          }
        end
      end

      extend ClassMethods
    end
  end
end
