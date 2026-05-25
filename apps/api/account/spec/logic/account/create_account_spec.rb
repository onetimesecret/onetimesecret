# apps/api/account/spec/logic/account/create_account_spec.rb
#
# frozen_string_literal: true

# Unit tests for CreateAccount logic, focused on per-domain signup validation.
#
# Run with:
#   source .env.test && bundle exec rspec apps/api/account/spec/logic/account/create_account_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'account/logic'

RSpec.describe AccountAPI::Logic::Account::CreateAccount do
  let(:email) { 'newuser@example.com' }
  let(:password) { 'securepassword123' }
  let(:custom_domain_name) { 'secrets.acme.com' }

  let(:session) do
    {
      'id' => 'test-session-123',
      'csrf' => 'test-csrf-token',
    }
  end

  let(:strategy_result) do
    double('StrategyResult',
      session: session,
      user: nil, # Anonymous - creating new account
      authenticated?: false,
      auth_method: :noauth,
      metadata: metadata
    )
  end

  let(:metadata) { {} }
  let(:params) { { 'login' => email, 'password' => password } }

  subject(:logic) { described_class.new(strategy_result, params) }

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    allow(OT).to receive(:conf).and_return({
      'site' => {
        'authentication' => {
          'autoverify' => 'false',
          'allowed_signup_domains' => nil,
        },
      },
      'features' => {},
    })
    # Stub Truemail validation
    allow(Truemail).to receive(:validate).and_return(
      double(result: double(valid?: true), as_json: '{}')
    )
  end

  describe '#allowed_signup_domain?' do
    context 'when no display_domain is provided' do
      let(:metadata) { { display_domain: nil } }

      it 'delegates to SignupValidation with nil display_domain' do
        expect(Onetime::SignupValidation).to receive(:valid_signup_email?)
          .with(email, display_domain: nil)
          .and_return(true)

        # Trigger the validation through raise_concerns
        allow(Onetime::Customer).to receive(:find_by_email).and_return(nil)
        expect { logic.raise_concerns }.not_to raise_error
      end
    end

    context 'when display_domain is provided' do
      let(:metadata) { { display_domain: custom_domain_name } }

      it 'delegates to SignupValidation with the display_domain' do
        expect(Onetime::SignupValidation).to receive(:valid_signup_email?)
          .with(email, display_domain: custom_domain_name)
          .and_return(true)

        allow(Onetime::Customer).to receive(:find_by_email).and_return(nil)
        expect { logic.raise_concerns }.not_to raise_error
      end

      it 'raises FormError when domain validation fails' do
        expect(Onetime::SignupValidation).to receive(:valid_signup_email?)
          .with(email, display_domain: custom_domain_name)
          .and_return(false)

        expect { logic.raise_concerns }.to raise_error(
          Onetime::FormError, /Is that a valid email address?/
        )
      end
    end

    context 'when per-domain config allows the email' do
      let(:metadata) { { display_domain: custom_domain_name } }
      let(:email) { 'user@acme.com' }

      it 'passes validation when email matches domain allowlist' do
        # SignupValidation handles the full resolution chain
        expect(Onetime::SignupValidation).to receive(:valid_signup_email?)
          .with(email, display_domain: custom_domain_name)
          .and_return(true)

        allow(Onetime::Customer).to receive(:find_by_email).and_return(nil)
        expect { logic.raise_concerns }.not_to raise_error
      end
    end

    context 'fallback to global config' do
      let(:metadata) { { display_domain: 'unknown-domain.com' } }

      before do
        allow(OT).to receive(:conf).and_return({
          'site' => {
            'authentication' => {
              'autoverify' => 'false',
              'allowed_signup_domains' => ['globally-allowed.com'],
            },
          },
          'features' => {},
        })
      end

      it 'uses global config when SignupConfig is not found' do
        # The validation should fall through to global config
        expect(Onetime::SignupValidation).to receive(:valid_signup_email?)
          .with(email, display_domain: 'unknown-domain.com')
          .and_call_original

        # Global config only allows globally-allowed.com
        allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(nil)

        expect { logic.raise_concerns }.to raise_error(Onetime::FormError)
      end
    end
  end

  describe '#process' do
    let(:new_customer) do
      instance_double(
        Onetime::Customer,
        objid: 'cust-123',
        extid: 'cust-123',
        custid: 'cust-123',
        email: email,
        obscure_email: 'n***r@example.com',
        role: 'customer',
        verified: false,
        'verified=': nil,
        'verified_by=': nil,
        'role=': nil,
        'signup_domain_id=': nil,
        'provisioning_origin=': nil,
        save: true,
        update_passphrase: true
      )
    end

    let(:custom_domain) do
      instance_double(
        Onetime::CustomDomain,
        identifier: 'domain-abc123',
        display_domain: custom_domain_name
      )
    end

    before do
      allow(Onetime::SignupValidation).to receive(:valid_signup_email?).and_return(true)
      allow(Onetime::Customer).to receive(:find_by_email).and_return(nil)
      allow(Onetime::Customer).to receive(:create!).and_return(new_customer)
      allow(logic).to receive(:send_verification_email)
      allow(I18n).to receive(:t).and_return('Check your email')
    end

    context 'when display_domain is provided and CustomDomain exists' do
      let(:metadata) { { display_domain: custom_domain_name } }

      it 'captures signup_domain_id on new customer' do
        allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
          .with(custom_domain_name)
          .and_return(custom_domain)

        expect(new_customer).to receive(:signup_domain_id=).with('domain-abc123')

        logic.raise_concerns
        logic.process
      end
    end

    context 'when display_domain is provided but CustomDomain does not exist' do
      let(:metadata) { { display_domain: 'nonexistent.example.com' } }

      it 'does not set signup_domain_id' do
        allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
          .with('nonexistent.example.com')
          .and_return(nil)

        expect(new_customer).not_to receive(:signup_domain_id=)

        logic.raise_concerns
        logic.process
      end
    end

    context 'when no display_domain is provided' do
      let(:metadata) { { display_domain: nil } }

      it 'does not attempt to capture signup_domain_id' do
        expect(Onetime::CustomDomain).not_to receive(:load_by_display_domain)
        expect(new_customer).not_to receive(:signup_domain_id=)

        logic.raise_concerns
        logic.process
      end
    end

    context 'when account already exists' do
      let(:existing_customer) do
        instance_double(
          Onetime::Customer,
          objid: 'existing-cust-123',
          extid: 'existing-cust-123',
          obscure_email: 'e***g@example.com',
          role: 'customer',
          verified: true
        )
      end

      let(:metadata) { { display_domain: custom_domain_name } }

      it 'does not capture signup_domain_id for existing accounts' do
        allow(Onetime::Customer).to receive(:find_by_email).and_return(existing_customer)

        # Should not interact with CustomDomain for existing accounts
        expect(Onetime::CustomDomain).not_to receive(:load_by_display_domain)

        logic.raise_concerns
        logic.process
      end
    end
  end

  describe 'integration with SignupValidation' do
    # These tests verify the contract between CreateAccount and SignupValidation

    it 'passes display_domain from metadata to validation' do
      metadata[:display_domain] = 'test.example.com'
      logic = described_class.new(strategy_result, params)

      expect(Onetime::SignupValidation).to receive(:valid_signup_email?)
        .with(email, display_domain: 'test.example.com')
        .and_return(true)

      allow(Onetime::Customer).to receive(:find_by_email).and_return(nil)
      logic.raise_concerns
    end

    it 'uses nil display_domain when metadata is empty' do
      metadata.clear
      logic = described_class.new(strategy_result, params)

      expect(Onetime::SignupValidation).to receive(:valid_signup_email?)
        .with(email, display_domain: nil)
        .and_return(true)

      allow(Onetime::Customer).to receive(:find_by_email).and_return(nil)
      logic.raise_concerns
    end
  end
end
