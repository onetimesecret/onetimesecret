# spec/cli/billing/test_trigger_webhook_command_spec.rb
#
# frozen_string_literal: true
#
# Regression coverage for GitHub issue onetimesecret#3498, item 3:
# "Shell command injection" in the billing test-trigger-webhook CLI command.
#
# Security property locked in here:
#   The trigger-webhook command must invoke the Stripe CLI via the ARRAY form
#   of Kernel#system  ->  system('stripe', 'trigger', event_type, ...).
#   The array (multi-argument) form of system bypasses /bin/sh entirely, so
#   shell metacharacters embedded in any argument (event_type, subscription,
#   customer) are passed through to execve() as a single literal token and are
#   NEVER interpreted by a shell. A revert to the vulnerable single-string form
#   -- system("stripe trigger #{event_type}") -- would collapse the call to a
#   single concatenated String argument and route it through /bin/sh -c, which
#   is exactly the injection vector this test must catch.
#
# Why these tests FAIL on the old (vulnerable) code:
#   The expectations below pin `system` with MULTIPLE positional String
#   arguments where the metacharacter-laden value is ONE discrete element
#   (e.g. .with('stripe', 'trigger', 'customer.created; touch /tmp/pwned')).
#   A single-string `system("stripe trigger customer.created; touch ...")`
#   call produces a one-element argument list that does NOT satisfy that
#   matcher, so the example fails. The negative example additionally asserts
#   `system` is never called with a single concatenated shell string.
#
# Production code under test:
#   apps/web/billing/cli/test_trigger_webhook_command.rb#call  (L42-57)

require_relative '../cli_spec_helper'
# stripe is `require: false` (Gemfile) and, in this command's own path, is loaded
# lazily by stripe_configured? (billing/cli/helpers.rb) — which this spec stubs
# (below). Today the full-app boot still pulls stripe in transitively (billing
# controllers/models require it), so `allow(Stripe)` resolves; but that's an
# incidental boot-order dependency. Require it explicitly so the stub target is
# guaranteed to exist regardless of what else the boot happens to load.
require 'stripe'
require_relative '../../../apps/web/billing/cli/test_trigger_webhook_command'

RSpec.describe Onetime::CLI::BillingTestTriggerWebhookCommand, type: :cli do
  subject(:cmd) { described_class.new }

  # The fixed literal probe the command runs first to confirm the Stripe CLI is
  # installed. It carries no attacker-controlled input, so it is not an
  # injection vector; we stub it true so execution proceeds to the real exec.
  let(:which_probe) { 'which stripe > /dev/null 2>&1' }

  # A value carrying a classic shell metacharacter chain. If this ever reaches
  # /bin/sh, the `; touch /tmp/pwned` clause would execute as a second command.
  let(:malicious_event) { 'customer.created; touch /tmp/pwned' }

  before do
    # Don't boot the real application or touch real config/Redis.
    allow(cmd).to receive(:boot_application!)
    allow(cmd).to receive(:stripe_configured?).and_return(true)

    # The sk_test_ guard at L31 needs Stripe.api_key to be a real test key.
    # Stripe is a loadable gem in this environment; stub its api_key.
    allow(Stripe).to receive(:api_key).and_return('sk_test_x')

    # First system call is the fixed-literal availability probe. Stub it true
    # so control flow reaches the real (array-form) exec call.
    allow(cmd).to receive(:system).with(which_probe).and_return(true)
  end

  describe '#call (array-form system / shell-injection regression)' do
    context 'with a shell metacharacter in event_type (malicious, neutralised)' do
      it 'passes the metacharacter-laden event_type as ONE literal array element' do
        # CORE REGRESSION GUARD. The metacharacter value is a single discrete
        # positional argument -- never concatenated into a shell string.
        # A revert to system("stripe trigger #{event_type}") would make this
        # expectation fail (single-element arg list does not match).
        expect(cmd).to receive(:system)
          .with('stripe', 'trigger', malicious_event)
          .and_return(true)

        cmd.call(event_type: malicious_event)
      end

      it 'NEVER invokes system with a single concatenated shell string' do
        # Negative proof: the vulnerable form would call system() with one
        # String arg that contains "stripe trigger customer.created; touch ...".
        # Pin that this never happens.
        expect(cmd).not_to receive(:system)
          .with(a_string_matching(%r{stripe trigger customer\.created; touch}))

        # Still allow the legitimate array-form call so the command can run.
        allow(cmd).to receive(:system)
          .with('stripe', 'trigger', malicious_event)
          .and_return(true)

        cmd.call(event_type: malicious_event)
      end
    end

    context 'with a legitimate event_type (positive case)' do
      it 'invokes the Stripe CLI in array form with the event_type as its own element' do
        expect(cmd).to receive(:system)
          .with('stripe', 'trigger', 'customer.subscription.updated')
          .and_return(true)

        cmd.call(event_type: 'customer.subscription.updated')
      end
    end

    context 'with --subscription provided' do
      it 'appends --subscription and its value as separate literal array elements' do
        expect(cmd).to receive(:system)
          .with('stripe', 'trigger', 'evt', '--subscription', 'sub_123')
          .and_return(true)

        cmd.call(event_type: 'evt', subscription: 'sub_123')
      end

      it 'keeps a metacharacter-laden subscription value as one literal element' do
        expect(cmd).to receive(:system)
          .with('stripe', 'trigger', 'evt', '--subscription', 'sub_1; rm -rf /')
          .and_return(true)

        cmd.call(event_type: 'evt', subscription: 'sub_1; rm -rf /')
      end
    end

    context 'with --customer provided' do
      it 'appends --customer and its value as separate literal array elements' do
        expect(cmd).to receive(:system)
          .with('stripe', 'trigger', 'evt', '--customer', 'cust_123')
          .and_return(true)

        cmd.call(event_type: 'evt', customer: 'cust_123')
      end
    end

    context 'with both --subscription and --customer provided' do
      it 'appends all six trailing tokens in order as discrete elements' do
        expect(cmd).to receive(:system)
          .with('stripe', 'trigger', 'evt',
                '--subscription', 'sub_123',
                '--customer', 'cust_123')
          .and_return(true)

        cmd.call(event_type: 'evt', subscription: 'sub_123', customer: 'cust_123')
      end
    end

    context 'with subscription: nil and customer: nil (guard preserved)' do
      it 'builds exactly [stripe, trigger, event_type] with no --subscription/--customer tokens' do
        # The `if subscription` / `if customer` guards must drop nils so no
        # empty/blank tokens are appended.
        expect(cmd).to receive(:system)
          .with('stripe', 'trigger', 'evt')
          .and_return(true)

        cmd.call(event_type: 'evt', subscription: nil, customer: nil)
      end
    end
  end

  describe '#call (control-flow guards)' do
    context 'when the which-stripe probe returns false' do
      it 'prints "Stripe CLI not found" and NEVER runs the real stripe trigger' do
        allow(cmd).to receive(:system).with(which_probe).and_return(false)

        # The real array-form exec must never be reached.
        expect(cmd).not_to receive(:system).with('stripe', 'trigger', anything)
        expect(cmd).not_to receive(:system)
          .with('stripe', 'trigger', anything, anything, anything)

        output = capture_output { cmd.call(event_type: malicious_event) }
        expect(output[:stdout]).to include('Stripe CLI not found')
      end
    end

    context 'when Stripe.api_key is not a test key (sk_test_ guard)' do
      it 'prints the test-key error and NEVER calls system at all' do
        allow(Stripe).to receive(:api_key).and_return('sk_live_dangerous')

        # No system call whatsoever on a live key -- not even the probe.
        expect(cmd).not_to receive(:system)

        output = capture_output { cmd.call(event_type: malicious_event) }
        expect(output[:stdout]).to include('Can only trigger test events with test API keys')
      end
    end
  end
end
