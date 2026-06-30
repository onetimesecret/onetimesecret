# apps/api/account/spec/logic/authentication/reset_password_request_spec.rb
#
# frozen_string_literal: true
#
# Unit tests for ResetPasswordRequest, covering two security/robustness
# properties (issue #3486 and PR #3545 review):
#
#  1. Email enumeration prevention (CWE-204): raise_concerns validates only the
#     email format, and #process returns the same generic success response
#     whether or not the account exists — no secret created and no email sent
#     for an unregistered address.
#  2. A fallback: :sync delivery failure must not 500 the request; the response
#     is identical whether or not delivery succeeds, so it never reveals
#     delivery status.
#
# Run with:
#   source .env.test && bundle exec rspec apps/api/account/spec/logic/authentication/reset_password_request_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'account/logic'

RSpec.describe AccountAPI::Logic::Authentication::ResetPasswordRequest do
  let(:email) { 'user@example.com' }
  let(:session) { { 'id' => 'sess-123', 'csrf' => 'csrf-token' } }
  let(:strategy_result) do
    double('StrategyResult',
      session: session,
      user: nil, # Unauthenticated reset request
      authenticated?: false,
      auth_method: :noauth,
      metadata: {})
  end
  let(:params) { { 'login' => email } }

  subject(:logic) { described_class.new(strategy_result, params) }

  let(:customer) do
    double('Customer',
      extid: 'cust-ext-1',
      objid: 'cust-obj-1',
      email: email,
      obscure_email: 'u***@example.com',
      locale: 'en')
  end

  let(:secret) { double('Secret', identifier: 'secret-id-1') }

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    allow(OT).to receive(:default_locale).and_return('en')
    allow(OT).to receive(:conf).and_return({
      'site' => { 'authentication' => {} },
      'features' => {},
    })

    # Customer lookup: default to an existing, non-pending (normal reset) account
    allow(Onetime::Customer).to receive(:find_by_email).with(email).and_return(customer)
    allow(customer).to receive(:pending?).and_return(false)
    allow(customer).to receive(:reset_secret=)

    # Verification secret creation
    allow(Onetime::Secret).to receive(:create!).and_return(secret)
    allow(secret).to receive(:default_expiration=)
    allow(secret).to receive(:verification=)
    allow(secret).to receive(:save)

    # Quiet the auth logger
    allow(logic).to receive(:auth_logger).and_return(double('auth_logger').as_null_object)
  end

  describe '#raise_concerns (CWE-204 enumeration prevention)' do
    it 'does not raise for a well-formed but unregistered email' do
      allow(logic).to receive(:valid_email?).and_return(true)

      expect { logic.raise_concerns }.not_to raise_error
    end

    it 'raises only on an invalid email format' do
      allow(logic).to receive(:valid_email?).and_return(false)

      expect { logic.raise_concerns }.to raise_error(OT::FormError, /Invalid email address/)
    end

    it 'never checks account existence in the validation layer' do
      allow(logic).to receive(:valid_email?).and_return(true)

      expect(Onetime::Customer).not_to receive(:find_by_email)
      expect(Onetime::Customer).not_to receive(:exists?)

      logic.raise_concerns
    end
  end

  describe '#process for an unregistered email (CWE-204 enumeration prevention)' do
    before do
      allow(Onetime::Customer).to receive(:find_by_email).with(email).and_return(nil)
    end

    it 'returns the same generic success response as a registered account' do
      expect(logic.process).to include(sent: true)
    end

    it 'creates no reset secret and sends no email' do
      expect(Onetime::Secret).not_to receive(:create!)
      expect(Onetime::Jobs::Publisher).not_to receive(:enqueue_email)

      logic.process
    end
  end

  describe '#process email delivery (issue #3486)' do
    it 'enqueues the reset email with fallback: :sync' do
      expect(Onetime::Jobs::Publisher).to receive(:enqueue_email).with(
        :password_request,
        hash_including(email_address: email, secret: secret),
        fallback: :sync,
      )

      logic.process
    end

    it 'returns a generic success response' do
      allow(Onetime::Jobs::Publisher).to receive(:enqueue_email)

      expect(logic.process).to include(sent: true)
    end

    it 'does not raise or change the response when sync delivery fails' do
      # The publisher swallows/reports a :sync delivery failure (returns false)
      # rather than raising, so the request still succeeds — the reset secret is
      # already persisted and the user can request another.
      allow(Onetime::Jobs::Publisher).to receive(:enqueue_email).and_return(false)

      result = nil
      expect { result = logic.process }.not_to raise_error
      expect(result).to include(sent: true)
    end
  end
end
