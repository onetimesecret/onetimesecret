# apps/api/account/spec/logic/authentication/reset_password_request_spec.rb
#
# frozen_string_literal: true
#
# Unit tests for ResetPasswordRequest, covering three security/robustness
# properties (issue #3486, PR #3545 review, and #3872):
#
#  1. Email enumeration prevention (CWE-204): raise_concerns validates only the
#     email format, and #process returns the same generic success response
#     whether or not the account exists — no secret created and no email sent
#     for an unregistered address.
#  2. A fallback: :sync delivery failure must not 500 the request; the response
#     is identical whether or not delivery succeeds, so it never reveals
#     delivery status.
#  3. Reset-request rate limiting (#3872): this logic class is the SIMPLE-mode
#     (default) path for POST /auth/reset-password-request — the Rodauth hook
#     that enforces the limiter only loads in full mode — so it must enforce
#     ResetRequestRateLimiter itself, ahead of the format check and any account
#     lookup.
#
# Run with:
#   source .env.test && bundle exec rspec apps/api/account/spec/logic/authentication/reset_password_request_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'account/logic'

RSpec.describe AccountAPI::Logic::Authentication::ResetPasswordRequest do
  let(:email) { 'user@example.com' }
  let(:session) { { 'id' => 'sess-123', 'csrf' => 'csrf-token' } }
  let(:client_ip) { '203.0.113.7' }
  let(:strategy_result) do
    double('StrategyResult',
      session: session,
      user: nil, # Unauthenticated reset request
      authenticated?: false,
      auth_method: :noauth,
      metadata: { ip: client_ip })
  end
  # The submitted login is a `let` of its own so an example can vary it BEFORE
  # the logic object exists: #process_params runs in Onetime::Logic::Base's
  # constructor, so mutating `params` after `logic` has been built is a no-op
  # and any assertion about the derived @login_or_email would pass vacuously.
  let(:login_param) { email }
  let(:params) { { 'login' => login_param } }

  subject(:logic) { described_class.new(strategy_result, params) }

  let(:customer) do
    double('Customer',
      extid: 'cust-ext-1',
      objid: 'cust-obj-1',
      email: email,
      obscure_email: 'u***@example.com',
      locale: 'en')
  end

  let(:secret) { double('Secret', identifier: 'secret-id-1', shortid: 'secret-i') }

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

    # Quiet the auth logger. any_instance, NOT `allow(logic)`: touching `logic`
    # here would force construction (and therefore process_params) in the hook,
    # before an example has had a chance to override `login_param`.
    allow_any_instance_of(described_class).to receive(:auth_logger)
      .and_return(double('auth_logger').as_null_object)

    # #3872: stub the reset-request limiter so these unit examples never reach
    # Redis. The limiter defaults to ENABLED when config is absent (as it is in
    # the stubbed OT.conf above), which is the protective default we want in
    # production but would make every example here a datastore test. Its own
    # behavior is covered by try/unit/security/reset_request_rate_limiter_try.rb;
    # the wiring is asserted in the dedicated describe below, which overrides
    # this stub.
    allow_any_instance_of(described_class).to receive(:enforce_reset_request_rate_limit!)
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

  describe 'reset-request rate limiting (#3872, simple-mode parity)' do
    # Simple mode is the application default and routes
    # POST /auth/reset-password-request to this logic class via
    # Core::Controllers::Registration#request_reset_email. The Rodauth
    # before_reset_password_request_route hook that enforces the same limiter
    # lives under apps/web/auth/, which the registry only loads when
    # full_enabled? — so without the call asserted here the endpoint has no
    # throughput cap in the default configuration.
    let(:limit_exceeded) do
      Onetime::LimitExceeded.new(
        'Too many password reset requests. Please try again later.',
        retry_after: 3600,
        max_attempts: 10,
      )
    end

    it 'enforces the limiter with the strategy-metadata client IP and the submitted login' do
      allow(logic).to receive(:valid_email?).and_return(true)

      expect(logic).to receive(:enforce_reset_request_rate_limit!).with(client_ip, email)

      logic.raise_concerns
    end

    context 'when the submitted login is a case/whitespace variant' do
      let(:login_param) { '  USER@Example.COM  ' }

      it 'passes the sanitized login, so variants share one backstop bucket' do
        # Pin the sanitization itself: without this the .with(...) expectation
        # below would also be satisfied by a logic class that never sanitized,
        # since the variant only differs from `email` by what sanitize_email
        # strips.
        expect(logic.login_or_email).to eq(email)

        allow(logic).to receive(:valid_email?).and_return(true)

        # The limiter must receive the SAME string #process feeds to
        # Customer.find_by_email, so one target can never occupy two buckets.
        expect(logic).to receive(:enforce_reset_request_rate_limit!).with(client_ip, email)

        logic.raise_concerns
      end
    end

    it 'still enforces the per-login backstop when no client IP is available' do
      allow(strategy_result).to receive(:metadata).and_return({})
      allow(logic).to receive(:valid_email?).and_return(true)

      # nil IP skips the IP tier inside the limiter rather than pooling unknown
      # callers into one shared bucket; the login still reaches the backstop.
      expect(logic).to receive(:enforce_reset_request_rate_limit!).with(nil, email)

      logic.raise_concerns
    end

    it 'throttles BEFORE the email-format check, so a throttled probe never runs validation' do
      allow(logic).to receive(:enforce_reset_request_rate_limit!).and_raise(limit_exceeded)

      expect(logic).not_to receive(:valid_email?)
      expect { logic.raise_concerns }.to raise_error(Onetime::LimitExceeded)
    end

    it 'throttles BEFORE any account lookup, so a throttled probe takes no timing sample' do
      allow(logic).to receive(:enforce_reset_request_rate_limit!).and_raise(limit_exceeded)

      expect(Onetime::Customer).not_to receive(:find_by_email)
      expect(Onetime::Jobs::Publisher).not_to receive(:enqueue_email)

      expect { logic.raise_concerns }.to raise_error(Onetime::LimitExceeded)
    end

    it 'raises LimitExceeded (not FormError) so the edge renders the ADR-013 429' do
      # LimitExceeded is deliberately NOT an OT::FormError: the controller's
      # execute_with_error_handling rescues FormError into a 400/422 form
      # response, while LimitExceeded propagates to the Otto error handler
      # registered in lib/onetime/application/otto_hooks.rb (status: 429).
      allow(logic).to receive(:enforce_reset_request_rate_limit!).and_raise(limit_exceeded)

      expect(limit_exceeded).not_to be_a(OT::FormError)
      expect { logic.raise_concerns }.to raise_error(Onetime::LimitExceeded) do |ex|
        expect(ex.retry_after).to eq(3600)
        expect(ex.max_attempts).to eq(10)
      end
    end

    context 'when the submitted login is not valid UTF-8' do
      # Form params reach here UTF-8-tagged but unvalidated, and Sanitize
      # raises ArgumentError on invalid bytes. process_params runs in the
      # constructor — before raise_concerns, so before the limiter — and the
      # controller builds the logic object outside its error handling, so an
      # unhandled raise would be a 500 that consumes no limiter budget.
      let(:login_param) { +"user\xC3(@example.com".dup.force_encoding('UTF-8') }

      it 'still constructs, and the probe costs limiter budget instead of 500ing' do
        expect(login_param.valid_encoding?).to be false

        logic = nil
        expect { logic = described_class.new(strategy_result, params) }.not_to raise_error
        expect(logic.login_or_email.valid_encoding?).to be true

        expect(logic).to receive(:enforce_reset_request_rate_limit!)
          .with(client_ip, logic.login_or_email)
        allow(logic).to receive(:valid_email?).and_return(false)

        # Past the limiter it is an ordinary rejected address, not a crash.
        expect { logic.raise_concerns }.to raise_error(OT::FormError, /Invalid email address/)
      end
    end

    it 'lets an under-cap request through to the normal generic-success path' do
      allow(logic).to receive(:valid_email?).and_return(true)
      allow(Onetime::Jobs::Publisher).to receive(:enqueue_email).and_return(true)

      expect { logic.raise_concerns }.not_to raise_error
      expect(logic.process).to include(sent: true)
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

  describe '#process for a pending (unverified) account (PR #3545: nil-customer fix)' do
    before do
      allow(customer).to receive(:pending?).and_return(true)
    end

    it 'returns the same generic success response' do
      allow(logic).to receive(:send_verification_email)

      expect(logic.process).to include(sent: true)
    end

    it 'resends verification to the looked-up customer, not the nil request-context cust' do
      # Regression for the P1: send_verification_email defaults to the
      # request-context cust (nil here), so the reset flow must pass the
      # looked-up customer explicitly or it 500s.
      expect(logic).to receive(:send_verification_email).with(customer: customer)

      logic.process
    end

    it 'does not create a password-reset secret or send a reset email' do
      allow(logic).to receive(:send_verification_email)
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
