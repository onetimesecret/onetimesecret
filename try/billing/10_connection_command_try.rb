# try/billing/10_connection_command_try.rb
#
# Test the billing connection command that displays Stripe credentials securely
#

## Test: Connection command runs without error
@exit_code = system('bin/ots billing connection > /dev/null 2>&1')
@exit_code
#=> true

## Test: Shows billing enabled status
@output = `bin/ots billing connection 2>&1`
@output.include?('Billing: Enabled') || @output.include?('Billing: Disabled')
#=> true

## Test: Shows Stripe API Key status
@output.include?('Stripe API Key:')
#=> true

## Test: Shows Webhook Signing Secret status
@output.include?('Webhook Signing Secret:')
#=> true

## Test: Shows environment variable status
@output.include?('Environment Variables:')
#=> true

## Test: Shows configuration source
@output.include?('Configuration Source:')
#=> true

## Test: Shows key format reference
@output.include?('Key Format Reference:') || @output.include?('Security:')
#=> true

## Test: Masks credentials appropriately (placeholder values)
@output.include?('placeholder value') || @output.include?('Not configured')
#=> true

## Test: Command with mock test credentials masks properly
ENV['STRIPE_KEY'] = 'sk_test_1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJ'
ENV['STRIPE_WEBHOOK_SIGNING_SECRET'] = 'whsec_test_abcdefghijklmnopqrstuvwxyz1234567890'
@output_with_creds = `bin/ots billing connection 2>&1`

# Should show masked credentials
@output_with_creds.include?('sk_t****') && @output_with_creds.include?('GHIJ')
#=> true

## Test: Detects test mode credentials
@output_with_creds.include?('Test Mode')
#=> true

## Test: Shows credential length
@output_with_creds.include?('Length:') && @output_with_creds.include?('characters')
#=> true

## Test: Environment variables are shown as set
@output_with_creds.include?('STRIPE_KEY: ✓ Set')
#=> true

## Teardown: Clean up test environment variables
ENV.delete('STRIPE_KEY')
ENV.delete('STRIPE_WEBHOOK_SIGNING_SECRET')
true
#=> true
