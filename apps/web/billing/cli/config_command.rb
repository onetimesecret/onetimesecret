# apps/web/billing/cli/config_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Display Stripe configuration information (API key and webhook secret)
    class BillingConfigCommand < Command
      include BillingHelpers

      desc 'Display Stripe configuration information (securely masked)'

      def call(**)
        boot_application!

        puts 'Stripe Connection Information'
        puts '=' * 60
        puts

        # Billing enabled check
        if OT.billing_config.enabled?
          puts '✓ Billing: Enabled'
        else
          puts '✗ Billing: Disabled (check etc/billing.yaml)'
          puts
          return
        end

        puts

        # Fetch account name from Stripe API
        stripe_key   = OT.billing_config.stripe_key
        account_info = fetch_account_info(stripe_key)

        if account_info
          mode = stripe_key.start_with?('sk_test_', 'rk_test_') ? 'Test' : 'Live'
          puts "Account: #{account_info[:name]}"
          puts "Mode: #{mode}"
          puts
        end

        # Environment Variables (first - most abstract)
        puts 'Environment Variables:'
        display_env_status('STRIPE_KEY', ENV.fetch('STRIPE_KEY', nil))
        display_env_status('STRIPE_WEBHOOK_SIGNING_SECRET', ENV.fetch('STRIPE_WEBHOOK_SIGNING_SECRET', nil))

        puts
        puts 'Configuration Source:'
        puts "  etc/billing.yaml (exists: #{File.exist?('etc/billing.yaml')})"
        puts '  etc/examples/billing.example.yaml (template)'

        puts

        # Actual Configuration Values (last - most concrete)
        display_credential('Stripe API Key', stripe_key, :stripe_key)

        puts

        webhook_secret = OT.billing_config.webhook_signing_secret
        display_credential('Webhook Signing Secret', webhook_secret, :webhook_secret)

        puts
        puts 'Key Format Reference:'
        puts '  Secret keys:      sk_test_*  (test)  /  sk_live_*  (live)'
        puts '  Restricted keys:  rk_test_*  (test)  /  rk_live_*  (live)'
        puts '  Publishable keys: pk_test_*  (test)  /  pk_live_*  (live)  [client-side]'
        puts '  Webhook secrets:  whsec_*    (mode determined by API key)'
        puts
        puts 'Security:'
        puts '  • Keys are masked (showing only first/last 4 characters)'
      end

      private

      # Fetch account information from Stripe API
      #
      # @param api_key [String] Stripe API key
      # @return [Hash, nil] Account info with :name, or nil if fetch fails
      def fetch_account_info(api_key)
        return nil if api_key.nil? || api_key.to_s.strip.empty?
        return nil if api_key == 'nostripekey'

        Stripe.api_key = api_key
        account        = Stripe::Account.retrieve
        {
          name: account.settings.dashboard.display_name || account.business_profile&.name || 'Unknown',
          id: account.id,
        }
      rescue Stripe::StripeError
        # Silently fail - connection info will still show without account name
        nil
      end

      # Display a credential with secure masking
      #
      # @param label [String] Human-readable label
      # @param value [String, nil] The credential value
      # @param type [Symbol] Credential type (:stripe_key or :webhook_secret)
      def display_credential(label, value, type)
        puts "#{label}:"

        if value.nil? || value.to_s.strip.empty?
          puts '  Status: ✗ Not configured'
          return
        end

        # Check for placeholder values
        if %w[nostripekey nosigningsecret].include?(value)
          puts '  Status: ✗ Using placeholder value (not configured)'
          return
        end

        # Validate format
        case type
        when :stripe_key
          unless value.start_with?('sk_test_', 'sk_live_', 'rk_test_', 'rk_live_')
            puts '  Status: ⚠ Invalid format (should start with sk_test_, sk_live_, etc.)'
            puts "  Masked: #{mask_credential(value)}"
            return
          end
        when :webhook_secret
          unless value.start_with?('whsec_')
            puts '  Status: ⚠ Invalid format (should start with whsec_)'
            puts "  Masked: #{mask_credential(value)}"
            return
          end
        end

        # Determine environment
        # Note: Webhook secrets (whsec_*) don't contain test/live indicators
        # Only API keys have sk_test_/sk_live_ prefixes
        environment = case value
                      when /^sk_test_/, /^rk_test_/
                        'Test Mode'
                      when /^sk_live_/, /^rk_live_/
                        'Live Mode'
                      when /^whsec_/
                        # Webhook secrets are environment-agnostic
                        # The mode is determined by which API key is used with the endpoint
                        'N/A (determined by API key)'
                      else
                        'Unknown'
                      end

        puts '  Status: ✓ Configured'
        puts "  Mode: #{environment}"
        puts "  Masked: #{mask_credential(value)}"
        puts "  Length: #{value.length} characters"
      end

      # Mask a credential showing only first and last 4 characters
      #
      # @param value [String] The credential to mask
      # @return [String] Masked credential
      def mask_credential(value)
        return 'nil' if value.nil?
        return '(empty)' if value.strip.empty?

        # For very short values, mask everything
        return '*' * value.length if value.length < 12

        # Show first 4 and last 4 characters
        prefix        = value[0..3]
        suffix        = value[-4..]
        masked_length = value.length - 8

        "#{prefix}#{'*' * masked_length}#{suffix}"
      end

      # Display environment variable status
      #
      # @param var_name [String] Environment variable name
      # @param value [String, nil] Environment variable value
      def display_env_status(var_name, value)
        if value.nil? || value.to_s.strip.empty?
          puts "  #{var_name}: ✗ Not set"
        else
          puts "  #{var_name}: ✓ Set (#{mask_credential(value)})"
        end
      end
    end
  end
end

Onetime::CLI.register 'billing config', Onetime::CLI::BillingConfigCommand
