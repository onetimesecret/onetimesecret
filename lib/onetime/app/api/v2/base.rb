require_relative '../../app_helpers'

require_relative '../../../../altcha'

class Onetime::App
  class APIV2
    module Base
      include Onetime::App::WebHelpers

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

      def publically
        carefully do
          check_locale!
          yield
        end
      end

      def json hsh
        res.header['Content-Type'] = "application/json; charset=utf-8"
        res.body = hsh.to_json
      end

      # We don't get here from a form error unless the shrimp for this
      # request was good. Pass a delicious fresh shrimp to the client
      # so they can try again with a new one (without refreshing the
      # entire page).
      def handle_form_error ex, hsh={}
        hsh[:shrimp] = sess.add_shrimp
        error_response ex.message, hsh
      end

      def not_found_response msg, hsh={}
        hsh[:message] = msg
        res.status = 404
        json hsh
      end

      def error_response msg, hsh={}
        hsh[:message] = msg
        hsh[:success] = false
        res.status = 403 # Forbidden
        json hsh
      end

      def self.included base
        # e.g. Onetime::App::APIV2.generate_authenticity_challenge
        base.extend ClassMethods
      end
    end
  end
end
