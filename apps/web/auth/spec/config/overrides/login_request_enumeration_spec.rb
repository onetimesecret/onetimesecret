# apps/web/auth/spec/config/overrides/login_request_enumeration_spec.rb
#
# frozen_string_literal: true

# One answer per login-request route, whatever the account state
# (issue #3857, RISK-2026-08-14-M03).
#
# The integration lanes only boot email_auth and verify_account in full-mfa,
# so this builds a Rodauth app with all three routes on and the production
# override applied, and compares each account state's response with an
# unknown login's. Mail is recorded, not sent. The `without the override`
# examples show the oracle on stock Rodauth, so the comparisons are not
# vacuous.
#
# Reference: apps/web/auth/config/overrides/login_request_enumeration.rb
# Integration twins: integration/full/reset_password_request_enumeration_spec.rb,
# integration/full_mfa/{email_login_request,verify_account_resend}_enumeration_spec.rb

require_relative '../../spec_helper'

# Namespace shim (the pattern of spec/config/hooks/*_spec.rb): the override
# file reopens Auth::Config without booting the app.
module Auth; end
Auth.const_set(:Config, Class.new(Rodauth::Auth)) unless defined?(Auth::Config)

require_relative '../../../lib/logging' # the overrides log each neutralised branch
require_relative '../../../config/overrides/login_request_enumeration'

# rubocop:disable-next RSpec/SpecFilePathFormat -- auth config specs follow the lane-owned directory
RSpec.describe Auth::Config::Overrides::LoginRequestEnumeration, :aggregate_failures do
  include Rack::Test::Methods

  let(:db) { create_test_database }
  let(:mails) { [] }
  let(:all_features) { [:base, :json, :login, :reset_password, :email_auth, :verify_account] }
  let(:app) { build_app(with_override: true) }

  def build_app(with_override:, features: all_features)
    sent = mails
    create_rodauth_app(db: db, features: features) do
      only_json? true
      require_mail? false
      # The test schema's deadline columns are NOT NULL; production writes
      # them through its own insert hashes (features/email_auth.rb).
      set_deadline_values? true
      send_reset_password_email { sent << [:reset_password, account[:email]] } if features.include?(:reset_password)
      send_email_auth_email { sent << [:email_auth, account[:email]] } if features.include?(:email_auth)
      send_verify_account_email { sent << [:verify_account, account[:email]] } if features.include?(:verify_account)
      Auth::Config::Overrides::LoginRequestEnumeration.configure(self) if with_override
    end.tap { |klass| klass.plugin :json_parser } # the helper app has no body parser
  end

  def probe(path, login)
    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    post path, JSON.generate(login: login)
    [last_response.status, JSON.parse(last_response.body)]
  end

  def seed(email, status_id)
    db[:accounts].insert(email: email, status_id: status_id)
  end

  def seed_key(table, account_id, email_last_sent:)
    row            = { id: account_id, key: SecureRandom.hex(16), email_last_sent: email_last_sent }
    row[:deadline] = Time.now + 3600 unless table == :account_verification_keys
    db[table].insert(row)
  end

  def unknown(path)
    probe(path, "nobody-#{SecureRandom.hex(4)}@example.com")
  end

  describe 'POST /email-auth-request' do
    let(:path) { '/email-auth-request' }

    it 'answers an open account (the real send) and an unknown login identically' do
      seed('open@example.com', AuthTestConstants::STATUS_VERIFIED)

      sent = probe(path, 'open@example.com')

      expect(sent.first).to eq(200)
      expect(sent).to eq(unknown(path))
      expect(mails).to eq([[:email_auth, 'open@example.com']])
    end

    {
      'an unverified account' => AuthTestConstants::STATUS_UNVERIFIED,
      'a closed account' => AuthTestConstants::STATUS_CLOSED,
    }.each do |label, status_id|
      it "answers #{label} like an unknown login and mails nothing" do
        seed('state@example.com', status_id)

        expect(probe(path, 'state@example.com')).to eq(unknown(path))
        expect(mails).to be_empty
      end
    end

    it 'answers a recently emailed account like an unknown login, without resending' do
      id = seed('recent@example.com', AuthTestConstants::STATUS_VERIFIED)
      seed_key(:account_email_auth_keys, id, email_last_sent: Time.now)

      expect(probe(path, 'recent@example.com')).to eq(unknown(path))
      expect(mails).to be_empty
    end
  end

  describe 'POST /verify-account-resend' do
    let(:path) { '/verify-account-resend' }

    it 'answers an unverified account (the real resend) and an unknown login identically' do
      id = seed('pending@example.com', AuthTestConstants::STATUS_UNVERIFIED)
      seed_key(:account_verification_keys, id, email_last_sent: Time.now - 3600)

      sent = probe(path, 'pending@example.com')

      expect(sent.first).to eq(200)
      expect(sent).to eq(unknown(path))
      expect(mails).to eq([[:verify_account, 'pending@example.com']])
    end

    {
      'a verified account' => AuthTestConstants::STATUS_VERIFIED,
      'a closed account' => AuthTestConstants::STATUS_CLOSED,
      'an unverified account with no key row' => AuthTestConstants::STATUS_UNVERIFIED,
    }.each do |label, status_id|
      it "answers #{label} like an unknown login and mails nothing" do
        seed('state@example.com', status_id)

        expect(probe(path, 'state@example.com')).to eq(unknown(path))
        expect(mails).to be_empty
      end
    end

    it 'answers a recently emailed account like an unknown login, without resending' do
      id = seed('recent@example.com', AuthTestConstants::STATUS_UNVERIFIED)
      seed_key(:account_verification_keys, id, email_last_sent: Time.now)

      expect(probe(path, 'recent@example.com')).to eq(unknown(path))
      expect(mails).to be_empty
    end
  end

  describe 'POST /reset-password-request (unchanged by the generalisation)' do
    let(:path) { '/reset-password-request' }

    it 'answers an open account and an unknown login identically, mailing only the account' do
      seed('open@example.com', AuthTestConstants::STATUS_VERIFIED)

      expect(probe(path, 'open@example.com')).to eq(unknown(path))
      expect(mails).to eq([[:reset_password, 'open@example.com']])
    end

    it 'answers an unverified and a recently emailed account like an unknown login' do
      seed('unverified@example.com', AuthTestConstants::STATUS_UNVERIFIED)
      id = seed('recent@example.com', AuthTestConstants::STATUS_VERIFIED)
      seed_key(:account_password_reset_keys, id, email_last_sent: Time.now)

      expect(probe(path, 'unverified@example.com')).to eq(unknown(path))
      expect(probe(path, 'recent@example.com')).to eq(unknown(path))
      expect(mails).to be_empty
    end
  end

  # Verified on the baseline: stock Rodauth tells the states apart, which is
  # what the override removes.
  context 'without the override' do
    let(:app) { build_app(with_override: false) }

    it 'answers an unknown login on email-auth-request with 401, unlike an open account' do
      seed('open@example.com', AuthTestConstants::STATUS_VERIFIED)

      expect(unknown('/email-auth-request').first).to eq(401)
      expect(probe('/email-auth-request', 'open@example.com').first).to eq(200)
    end

    it 'answers an unknown login on verify-account-resend with 401, unlike a pending account' do
      id = seed('pending@example.com', AuthTestConstants::STATUS_UNVERIFIED)
      seed_key(:account_verification_keys, id, email_last_sent: Time.now - 3600)

      expect(unknown('/verify-account-resend').first).to eq(401)
      expect(probe('/verify-account-resend', 'pending@example.com').first).to eq(200)
    end
  end

  describe 'feature guards' do
    it 'installs no predicate override for a feature that is not enabled' do
      klass = build_app(with_override: true, features: [:base, :json, :login, :reset_password]).rodauth

      defined = ->(meth) { klass.method_defined?(meth) || klass.private_method_defined?(meth) }

      expect(klass.instance_method(:reset_password_email_recently_sent?).owner).to eq(klass)
      expect(defined.call(:email_auth_email_recently_sent?)).to be(false)
      expect(defined.call(:verify_account_email_resend)).to be(false)
    end

    it 'overrides every enabled feature on the auth class itself' do
      klass = app.rodauth

      [:account_from_login, :reset_password_email_recently_sent?, :email_auth_email_recently_sent?, :verify_account_email_recently_sent?, :verify_account_email_resend].each do |meth|
        expect(klass.instance_method(meth).owner).to eq(klass), "#{meth} is not overridden"
      end
    end

    # The guards read the features enabled SO FAR, so production must call
    # configure after every block that can enable one (config.rb).
    # The recipient-origin guards (config/overrides/public_base_url.rb) gate
    # on features the same way.
    it 'is configured after every conditional feature block in config.rb' do
      source   = File.read(File.expand_path('../../../config.rb', __dir__))
      features = %w[Features::EmailAuth.configure Features::WebAuthn.configure Features::OmniAuth.configure]

      %w[Overrides::LoginRequestEnumeration.configure(self) Overrides::PublicBaseUrl.configure_recipient_origins(self)]
        .each do |late_call|
          expect(source.index(late_call)).not_to be_nil, "#{late_call} is not called in config.rb"
          features.each { |call| expect(source.index(call)).to be < source.index(late_call).to_i }
        end
    end
  end
end
