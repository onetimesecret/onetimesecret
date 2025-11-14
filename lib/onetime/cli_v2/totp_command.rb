# lib/onetime/cli_v2/totp_command.rb
#
# frozen_string_literal: true

require 'onetime/utils/totp'

module Onetime
  module CLI
    module V2
      class TotpCommand < Dry::CLI::Command
        desc 'Generate or verify TOTP codes for MFA testing'

        argument :secret, type: :string, required: false, desc: 'Base32-encoded TOTP secret'

        option :verify, type: :string, aliases: ['v'], desc: 'Verify a 6-digit code against the secret'
        option :compute_hmac, type: :boolean, default: false, aliases: ['c'], desc: 'Compute HMAC version of raw secret'
        option :raw, type: :string, aliases: ['r'], desc: 'Raw secret for HMAC computation'

        def call(secret: nil, verify: nil, compute_hmac: false, raw: nil, **)
          if compute_hmac
            unless raw
              puts "Error: --raw SECRET required when using --compute-hmac"
              exit 1
            end

            begin
              hmac_secret = Onetime::Utils::TOTP.compute_hmac(raw)
              puts "Raw secret:  #{raw}"
              puts "HMAC secret: #{hmac_secret}"
              puts ""
              puts "Use the HMAC secret in your authenticator app."
            rescue => e
              puts "Error: #{e.message}"
              exit 1
            end
          elsif verify
            unless secret
              puts "Error: SECRET required"
              exit 1
            end

            result = Onetime::Utils::TOTP.verify(secret, verify)
            puts "Secret:        #{result[:secret_sample]}"
            puts "Code:          #{result[:code]}"
            puts "Expected:      #{result[:expected_code]}"
            puts "Valid:         #{result[:valid] ? 'YES' : 'NO'}"
            puts "Match:         #{result[:match] ? 'YES' : 'NO'}"

            exit(result[:valid] ? 0 : 1)
          else
            unless secret
              puts "Error: SECRET required"
              puts "Usage: ots totp <secret>"
              exit 1
            end

            result = Onetime::Utils::TOTP.generate(secret)
            puts "Secret:        #{result[:secret_sample]}"
            puts "Issuer:        #{result[:issuer]}"
            puts ""
            puts "Current Code:  #{result[:current_code]}"
            puts "Previous Code: #{result[:previous_code]}"
            puts "Next Code:     #{result[:next_code]}"
            puts ""
            puts "Valid for:     #{result[:valid_for]} seconds"
            puts "Time:          #{Time.at(result[:current_time]).strftime('%Y-%m-%d %H:%M:%S %Z')}"
          end
        end
      end

      # Register the command
      register 'totp', TotpCommand
    end
  end
end
