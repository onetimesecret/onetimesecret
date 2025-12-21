# lib/onetime/cli/totp_command.rb
#
# frozen_string_literal: true

module Onetime
  module CLI
    # Generate or verify TOTP codes for MFA testing
    class TotpCommand < Command
      desc 'Generate or verify TOTP codes for MFA testing'

      argument :secret, type: :string, required: false,
        desc: 'Base32-encoded TOTP secret'

      option :verify, type: :string, aliases: ['v'],
        desc: 'Verify a 6-digit code against the secret'

      option :compute_hmac, type: :boolean, aliases: ['c'],
        desc: 'Compute HMAC secret from raw secret'

      option :raw, type: :string, aliases: ['r'],
        desc: 'Raw secret for HMAC computation'

      def call(secret: nil, verify: nil, compute_hmac: false, raw: nil, **)
        require 'onetime/utils/totp'

        if compute_hmac
          handle_compute_hmac(raw)
        elsif verify
          handle_verify(secret, verify)
        else
          handle_generate(secret)
        end
      end

      private

      def handle_compute_hmac(raw)
        unless raw
          puts 'Error: --raw SECRET required when using --compute-hmac'
          exit 1
        end

        hmac_secret = Onetime::Utils::TOTP.compute_hmac(raw)
        puts "Raw secret:  #{raw}"
        puts "HMAC secret: #{hmac_secret}"
        puts ''
        puts 'Use the HMAC secret in your authenticator app.'
      rescue StandardError => e
        puts "Error: #{e.message}"
        exit 1
      end

      def handle_verify(secret, code)
        unless secret
          puts 'Error: SECRET required'
          exit 1
        end

        result = Onetime::Utils::TOTP.verify(secret, code)
        puts "Secret:        #{result[:secret_sample]}"
        puts "Code:          #{result[:code]}"
        puts "Expected:      #{result[:expected_code]}"
        puts "Valid:         #{result[:valid] ? 'YES' : 'NO'}"
        puts "Match:         #{result[:match] ? 'YES' : 'NO'}"

        exit(result[:valid] ? 0 : 1)
      end

      def handle_generate(secret)
        unless secret
          puts 'Error: SECRET required'
          puts 'Usage: ots totp <secret>'
          puts ''
          puts 'Examples:'
          puts '  ots totp JBSWY3DPEHPK3PXP'
          puts '  ots totp JBSWY3DPEHPK3PXP --verify 123456'
          puts '  ots totp --compute-hmac --raw omidgappklu267g756mo2l4q2pq5m4rz'
          exit 1
        end

        result = Onetime::Utils::TOTP.generate(secret)
        puts "Secret:        #{result[:secret_sample]}"
        puts "Issuer:        #{result[:issuer]}"
        puts ''
        puts "Current Code:  #{result[:current_code]}"
        puts "Previous Code: #{result[:previous_code]}"
        puts "Next Code:     #{result[:next_code]}"
        puts ''
        puts "Valid for:     #{result[:valid_for]} seconds"
        puts "Time:          #{Time.at(result[:current_time]).strftime('%Y-%m-%d %H:%M:%S %Z')}"
      end
    end

    register 'totp', TotpCommand
  end
end
