module Onetime::App
  class APIV2

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
  end
end
