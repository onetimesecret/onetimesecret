# apps/api/domains/spec/integration/domain_sender_config_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration Tests for Domain Sender Config API Endpoints
# =============================================================================
#
# Issue: #2802 - Per-domain sender configuration (email)
#
# Tests the Domain Sender Config REST API endpoints:
#   GET    /api/domains/:extid/email-config
#   PUT    /api/domains/:extid/email-config
#   PATCH  /api/domains/:extid/email-config
#   DELETE /api/domains/:extid/email-config
#
# These endpoints require:
#   1. Authenticated user (session auth)
#   2. features.organizations.custom_mail_enabled feature flag
#   3. User must be organization owner (or colonel)
#   4. Organization must have custom_mail_sender entitlement
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTH_DATABASE_URL set (SQLite or PostgreSQL)
# - AUTHENTICATION_MODE=full
#
# RUN:
#   source .env.test && pnpm run test:rspec apps/api/domains/spec/integration/domain_sender_config_spec.rb
#
# =============================================================================

require_relative File.join(Onetime::HOME, 'spec', 'integration', 'integration_spec_helper')

RSpec.describe 'Domain Sender Config API', type: :integration do
  include Rack::Test::Methods
  include CsrfTestHelpers

  # Use the full Rack::URLMap so requests traverse the complete middleware
  # stack (including CSRF bypass for /api/* paths) exactly as in production.
  def app
    @rack_app ||= begin
      Onetime::Application::Registry.reset!
      Onetime::Application::Registry.prepare_application_registry
      Onetime::Application::Registry.generate_rack_url_map
    end
  end

  # ==========================================================================
  # Test Fixture Setup
  # ==========================================================================

  before(:all) do
    Onetime.boot! :test

    # Configure encryption for CustomDomain::MailerConfig (api_key is encrypted)
    key_v1 = 'test_encryption_key_32bytes_ok!!'
    key_v2 = 'another_test_key_for_testing_!!'

    Familia.configure do |config|
      config.encryption_keys = {
        v1: Base64.strict_encode64(key_v1),
        v2: Base64.strict_encode64(key_v2),
      }
      config.current_key_version = :v1
      config.encryption_personalization = 'CustomDomain::MailerConfigIntegrationTest'
    end
  end

  let(:test_run_id) { SecureRandom.hex(8) }
  let(:test_email) { "owner-#{test_run_id}@test.local" }
  let(:test_password) { 'Test123!@#' }
  let(:tenant_domain) { "mail-#{test_run_id}.acme-corp.example.com" }

  # Create owner customer
  let!(:test_owner) do
    customer = Onetime::Customer.new(email: test_email)
    customer.update_passphrase(test_password)
    customer.verified = 'true'
    customer.role = 'customer'
    customer.save
    customer
  end

  # Create non-owner customer (for authorization tests)
  let!(:test_non_owner) do
    email = "nonowner-#{test_run_id}@test.local"
    customer = Onetime::Customer.new(email: email)
    customer.update_passphrase(test_password)
    customer.verified = 'true'
    customer.role = 'customer'
    customer.save
    customer
  end

  # Create organization owned by test_owner
  # Note: In standalone/test mode (billing disabled), all orgs get
  # STANDALONE_ENTITLEMENTS which includes custom_mail_sender automatically.
  # The entitlement denial test stubs org.can? to test that code path.
  let!(:test_organization) do
    Onetime::Organization.create!(
      "Test Org #{test_run_id}",
      test_owner,
      "contact-#{test_run_id}@test.local",
    )
  end

  # Create custom domain associated with organization
  let!(:test_custom_domain) do
    domain = Onetime::CustomDomain.new(
      display_domain: tenant_domain,
      org_id: test_organization.org_id,
    )
    domain.save
    Onetime::CustomDomain.display_domains.put(tenant_domain, domain.domainid)
    domain
  end

  # Valid SES config params
  let(:valid_ses_params) do
    {
      provider: 'ses',
      from_name: 'Test Sender',
      from_address: 'noreply@acme-corp.example.com',
      reply_to: 'support@acme-corp.example.com',
      api_key: 'test-ses-api-key-abc123',
      enabled: true,
    }
  end

  # Valid SMTP config params
  let(:valid_smtp_params) do
    {
      provider: 'smtp',
      from_name: 'SMTP Sender',
      from_address: 'noreply@smtp.example.com',
      reply_to: 'help@smtp.example.com',
      api_key: 'smtp-credentials-xyz789',
      enabled: false,
    }
  end

  # Clean up after each test
  after do
    Onetime::CustomDomain::MailerConfig.delete_for_domain!(test_custom_domain.identifier) rescue nil
    Onetime::CustomDomain.display_domains.remove(tenant_domain) rescue nil
    test_custom_domain&.destroy! rescue nil
    test_organization&.destroy! rescue nil
    test_owner&.destroy! rescue nil
    test_non_owner&.destroy! rescue nil
  end

  # ==========================================================================
  # Helper Methods
  # ==========================================================================

  def enable_sender_feature_flag
    allow(OT).to receive(:conf).and_return({
      'features' => { 'organizations' => { 'custom_mail_enabled' => true } },
    })
  end

  def disable_sender_feature_flag
    allow(OT).to receive(:conf).and_return({
      'features' => { 'organizations' => { 'custom_mail_enabled' => false } },
    })
  end

  def api_path(domain_extid)
    "/api/domains/#{domain_extid}/email-config"
  end

  def login_as(customer)
    # Establish session by logging in via auth route
    reset_csrf_token
    csrf_post '/auth/login', {
      login: customer.email,
      password: test_password,
    }

    # Refresh CSRF token after login (session regeneration)
    reset_csrf_token
  end

  def json_get(path)
    header 'Accept', 'application/json'
    header 'Content-Type', nil
    get path
  end

  def json_body
    JSON.parse(last_response.body)
  end

  def csrf_patch(path, params = {})
    csrf_token = ensure_csrf_token

    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    header 'X-CSRF-Token', csrf_token if csrf_token

    patch path, JSON.generate(params.merge(shrimp: csrf_token))
  end

  # ==========================================================================
  # PUT /api/domains/:extid/email-config - Create/Replace Sender Config
  # ==========================================================================

  describe 'PUT /api/domains/:extid/email-config' do
    before do
      enable_sender_feature_flag
    end

    context 'when authenticated as organization owner with entitlement' do
      before do
        login_as(test_owner)
      end

      context 'creating new sender config' do
        it 'creates SES config and returns masked api_key' do
          csrf_put api_path(test_custom_domain.extid), valid_ses_params

          expect(last_response.status).to eq(200)

          body = json_body
          expect(body).to have_key('record')
          record = body['record']

          expect(record['provider']).to eq('ses')
          expect(record['from_name']).to eq('Test Sender')
          expect(record['from_address']).to eq('noreply@acme-corp.example.com')
          expect(record['reply_to']).to eq('support@acme-corp.example.com')
          expect(record['enabled']).to be true

          # Secret should be masked with bullet characters
          expect(record['api_key_masked']).to match(/^\u2022{8}.{4}$/)
          expect(record).not_to have_key('api_key')
        end

        it 'creates SMTP config' do
          csrf_put api_path(test_custom_domain.extid), valid_smtp_params

          expect(last_response.status).to eq(200)

          body = json_body
          record = body['record']
          expect(record['provider']).to eq('smtp')
          expect(record['from_address']).to eq('noreply@smtp.example.com')
          expect(record['enabled']).to be false
        end

        it 'creates SendGrid config' do
          params = valid_ses_params.merge(provider: 'sendgrid')
          csrf_put api_path(test_custom_domain.extid), params

          expect(last_response.status).to eq(200)

          body = json_body
          expect(body['record']['provider']).to eq('sendgrid')
        end

        it 'creates Lettermint config' do
          params = valid_ses_params.merge(provider: 'lettermint')
          csrf_put api_path(test_custom_domain.extid), params

          expect(last_response.status).to eq(200)

          body = json_body
          expect(body['record']['provider']).to eq('lettermint')
        end

        it 'returns user_id in response' do
          csrf_put api_path(test_custom_domain.extid), valid_ses_params

          body = json_body
          expect(body['user_id']).to eq(test_owner.extid)
        end

        it 'returns verification fields with default state' do
          csrf_put api_path(test_custom_domain.extid), valid_ses_params

          body = json_body
          record = body['record']

          expect(record['verification_status']).to eq('pending')
          expect(record['verified']).to be false
        end
      end

      context 'replacing existing sender config' do
        before do
          # Create initial config
          Onetime::CustomDomain::MailerConfig.create!(
            domain_id: test_custom_domain.identifier,
            provider: 'smtp',
            from_name: 'Old Sender',
            from_address: 'old@smtp.example.com',
            reply_to: 'old-reply@smtp.example.com',
            api_key: 'old-api-key',
            enabled: false,
          )
        end

        it 'replaces all fields with PUT semantics' do
          csrf_put api_path(test_custom_domain.extid), valid_ses_params

          expect(last_response.status).to eq(200)

          body = json_body
          record = body['record']

          # Provider should be replaced
          expect(record['provider']).to eq('ses')
          expect(record['from_name']).to eq('Test Sender')
          expect(record['from_address']).to eq('noreply@acme-corp.example.com')
          expect(record['reply_to']).to eq('support@acme-corp.example.com')
          expect(record['enabled']).to be true
        end

        it 'clears optional fields when empty in PUT request' do
          params = valid_ses_params.merge(from_name: '', reply_to: '')
          csrf_put api_path(test_custom_domain.extid), params

          expect(last_response.status).to eq(200)

          body = json_body
          record = body['record']

          # PUT clears fields that are empty
          expect(record['from_name']).to be_empty.or be_nil
          expect(record['reply_to']).to be_empty.or be_nil
        end
      end

      context 'validation errors' do
        it 'returns 400 for missing provider' do
          params = valid_ses_params.dup
          params.delete(:provider)

          csrf_put api_path(test_custom_domain.extid), params

          expect(last_response.status).to eq(400)
          body = json_body
          expect(body['message']).to include('Provider')
        end

        it 'returns 400 for invalid provider' do
          params = valid_ses_params.merge(provider: 'mailchimp')

          csrf_put api_path(test_custom_domain.extid), params

          expect(last_response.status).to eq(400)
          body = json_body
          expect(body['message']).to include('Invalid provider')
        end

        it 'returns 400 for missing from_address' do
          params = valid_ses_params.dup
          params.delete(:from_address)

          csrf_put api_path(test_custom_domain.extid), params

          expect(last_response.status).to eq(400)
          body = json_body
          expect(body['message']).to include('From address')
        end

        it 'returns 400 for missing api_key on PUT' do
          params = valid_ses_params.dup
          params.delete(:api_key)

          csrf_put api_path(test_custom_domain.extid), params

          expect(last_response.status).to eq(400)
          body = json_body
          expect(body['message']).to include('API key')
        end
      end
    end

    context 'authorization checks' do
      it 'returns 401 for unauthenticated requests' do
        # No login
        header 'Accept', 'application/json'
        header 'Content-Type', 'application/json'
        put api_path(test_custom_domain.extid), JSON.generate(valid_ses_params)

        expect(last_response.status).to eq(401)
      end

      it 'returns 403 when sender feature flag is disabled' do
        disable_sender_feature_flag
        login_as(test_owner)

        csrf_put api_path(test_custom_domain.extid), valid_ses_params

        expect(last_response.status).to eq(403)
        body = json_body
        expect(body['message']).to include('not enabled')
      end

      it 'returns 403 for non-owner of organization' do
        enable_sender_feature_flag
        login_as(test_non_owner)

        csrf_put api_path(test_custom_domain.extid), valid_ses_params

        expect(last_response.status).to eq(403)
        body = json_body
        expect(body['message']).to include('owner')
      end

      it 'returns 403 when organization lacks custom_mail_sender entitlement' do
        enable_sender_feature_flag
        # In integration tests with billing disabled, all orgs get STANDALONE_ENTITLEMENTS.
        # We stub can? on any org instance to test this code path.
        allow_any_instance_of(Onetime::Organization).to receive(:can?).with('custom_mail_sender').and_return(false)

        login_as(test_owner)
        csrf_put api_path(test_custom_domain.extid), valid_ses_params

        expect(last_response.status).to eq(403)
        body = json_body
        expect(body['message']).to include('custom_mail_sender')
      end

      it 'returns 404 for non-existent domain' do
        enable_sender_feature_flag
        login_as(test_owner)
        csrf_put api_path('nonexistent-domain-extid'), valid_ses_params

        expect(last_response.status).to eq(404)
        body = json_body
        expect(body['message']).to include('Domain not found')
      end
    end
  end

  # ==========================================================================
  # GET /api/domains/:extid/email-config - Retrieve Sender Config
  # ==========================================================================

  describe 'GET /api/domains/:extid/email-config' do
    before do
      enable_sender_feature_flag
    end

    context 'when sender config exists' do
      let!(:existing_config) do
        Onetime::CustomDomain::MailerConfig.create!(
          domain_id: test_custom_domain.identifier,
          provider: 'ses',
          from_name: 'Existing Sender',
          from_address: 'existing@acme-corp.example.com',
          reply_to: 'reply@acme-corp.example.com',
          api_key: 'existing-api-key-value',
          enabled: true,
        )
      end

      before do
        login_as(test_owner)
      end

      it 'returns the sender config with masked api_key' do
        json_get api_path(test_custom_domain.extid)

        expect(last_response.status).to eq(200)

        body = json_body
        expect(body).to have_key('record')
        record = body['record']

        expect(record['provider']).to eq('ses')
        expect(record['from_name']).to eq('Existing Sender')
        expect(record['from_address']).to eq('existing@acme-corp.example.com')
        expect(record['reply_to']).to eq('reply@acme-corp.example.com')
        expect(record['enabled']).to be true

        # Secret should be masked
        expect(record['api_key_masked']).to match(/^\u2022{8}/)
        expect(record).not_to have_key('api_key')
      end

      it 'returns timestamps as integers' do
        json_get api_path(test_custom_domain.extid)

        body = json_body
        record = body['record']

        expect(record['created_at']).to be_a(Integer)
        expect(record['updated_at']).to be_a(Integer)
      end

      it 'returns verification fields' do
        json_get api_path(test_custom_domain.extid)

        body = json_body
        record = body['record']

        expect(record).to have_key('verification_status')
        expect(record).to have_key('verified')
        expect(record).to have_key('dkim_record')
        expect(record).to have_key('spf_record')
      end
    end

    context 'when sender config does not exist' do
      before do
        login_as(test_owner)
      end

      it 'returns 404' do
        json_get api_path(test_custom_domain.extid)

        expect(last_response.status).to eq(404)
        body = json_body
        expect(body['message']).to include('Sender configuration not found')
      end
    end

    context 'authorization checks' do
      before do
        Onetime::CustomDomain::MailerConfig.create!(
          domain_id: test_custom_domain.identifier,
          provider: 'ses',
          from_address: 'auth-test@example.com',
          api_key: 'auth-test-key',
          enabled: true,
        )
      end

      it 'returns 401 for unauthenticated requests' do
        json_get api_path(test_custom_domain.extid)

        expect(last_response.status).to eq(401)
      end

      it 'returns 403 for non-owner' do
        login_as(test_non_owner)
        json_get api_path(test_custom_domain.extid)

        expect(last_response.status).to eq(403)
      end
    end
  end

  # ==========================================================================
  # PATCH /api/domains/:extid/email-config - Partial Update Sender Config
  # ==========================================================================

  describe 'PATCH /api/domains/:extid/email-config' do
    before do
      enable_sender_feature_flag
    end

    let!(:existing_config) do
      Onetime::CustomDomain::MailerConfig.create!(
        domain_id: test_custom_domain.identifier,
        provider: 'ses',
        from_name: 'Original Sender',
        from_address: 'original@acme-corp.example.com',
        reply_to: 'original-reply@acme-corp.example.com',
        api_key: 'original-api-key-secret',
        enabled: false,
      )
    end

    context 'when authenticated as organization owner' do
      before do
        login_as(test_owner)
      end

      it 'updates only provided fields (PATCH semantics)' do
        csrf_patch api_path(test_custom_domain.extid), {
          from_name: 'Updated Sender',
          enabled: true,
        }

        expect(last_response.status).to eq(200)

        body = json_body
        record = body['record']

        # Updated fields
        expect(record['from_name']).to eq('Updated Sender')
        expect(record['enabled']).to be true

        # Preserved fields
        expect(record['provider']).to eq('ses')
        expect(record['from_address']).to eq('original@acme-corp.example.com')
        expect(record['reply_to']).to eq('original-reply@acme-corp.example.com')
      end

      it 'preserves api_key when not provided' do
        csrf_patch api_path(test_custom_domain.extid), {
          from_name: 'Updated Again',
        }

        expect(last_response.status).to eq(200)

        body = json_body
        record = body['record']

        # Secret should still be masked (meaning it was preserved)
        expect(record['api_key_masked']).to match(/^\u2022{8}/)
      end

      it 'updates api_key when provided' do
        csrf_patch api_path(test_custom_domain.extid), {
          api_key: 'new-secret-value',
        }

        expect(last_response.status).to eq(200)

        body = json_body
        record = body['record']

        # Secret should show new masked value (last 4 chars of 'new-secret-value')
        expect(record['api_key_masked']).to eq("\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022alue")
      end

      it 'updates reply_to only' do
        csrf_patch api_path(test_custom_domain.extid), {
          reply_to: 'new-reply@acme-corp.example.com',
        }

        expect(last_response.status).to eq(200)

        body = json_body
        record = body['record']

        expect(record['reply_to']).to eq('new-reply@acme-corp.example.com')
        # Other fields preserved
        expect(record['from_name']).to eq('Original Sender')
        expect(record['provider']).to eq('ses')
      end

      it 'resets verification status when from_address changes' do
        # First mark as verified
        existing_config.verification_status = 'verified'
        existing_config.verified_at = Familia.now.to_i.to_s
        existing_config.save

        csrf_patch api_path(test_custom_domain.extid), {
          from_address: 'changed@acme-corp.example.com',
        }

        expect(last_response.status).to eq(200)

        body = json_body
        record = body['record']

        expect(record['from_address']).to eq('changed@acme-corp.example.com')
        expect(record['verification_status']).to eq('pending')
        expect(record['verified']).to be false
      end

      it 'preserves verification status when from_address is not changed' do
        # Mark as verified
        existing_config.verification_status = 'verified'
        existing_config.verified_at = Familia.now.to_i.to_s
        existing_config.save

        csrf_patch api_path(test_custom_domain.extid), {
          from_name: 'New Name Only',
        }

        expect(last_response.status).to eq(200)

        body = json_body
        record = body['record']

        expect(record['from_name']).to eq('New Name Only')
        expect(record['verification_status']).to eq('verified')
        expect(record['verified']).to be true
      end

      it 'switches provider while preserving other fields' do
        csrf_patch api_path(test_custom_domain.extid), {
          provider: 'sendgrid',
        }

        expect(last_response.status).to eq(200)

        body = json_body
        record = body['record']

        expect(record['provider']).to eq('sendgrid')
        # Other fields preserved
        expect(record['from_address']).to eq('original@acme-corp.example.com')
        expect(record['from_name']).to eq('Original Sender')
      end
    end

    context 'when no existing config' do
      before do
        # Remove the existing config
        Onetime::CustomDomain::MailerConfig.delete_for_domain!(test_custom_domain.identifier)
        login_as(test_owner)
      end

      it 'creates new config when providing all required fields' do
        csrf_patch api_path(test_custom_domain.extid), valid_ses_params

        expect(last_response.status).to eq(200)

        body = json_body
        record = body['record']
        expect(record['provider']).to eq('ses')
        expect(record['from_address']).to eq('noreply@acme-corp.example.com')
      end

      it 'returns 400 when required fields missing for creation' do
        csrf_patch api_path(test_custom_domain.extid), {
          from_name: 'Incomplete Config',
        }

        expect(last_response.status).to eq(400)
        body = json_body
        expect(body['message']).to include('required')
      end
    end
  end

  # ==========================================================================
  # DELETE /api/domains/:extid/email-config - Delete Sender Config
  # ==========================================================================

  describe 'DELETE /api/domains/:extid/email-config' do
    before do
      enable_sender_feature_flag
    end

    context 'when sender config exists' do
      before do
        Onetime::CustomDomain::MailerConfig.create!(
          domain_id: test_custom_domain.identifier,
          provider: 'ses',
          from_address: 'delete-test@example.com',
          api_key: 'delete-test-key',
          enabled: true,
        )
        login_as(test_owner)
      end

      it 'deletes the sender config and returns confirmation' do
        csrf_delete api_path(test_custom_domain.extid)

        expect(last_response.status).to eq(200)

        body = json_body
        expect(body['success']).to be true
        expect(body['message']).to include('deleted')

        # Verify deletion
        config = Onetime::CustomDomain::MailerConfig.find_by_domain_id(test_custom_domain.identifier)
        expect(config).to be_nil
      end
    end

    context 'when sender config does not exist' do
      before do
        login_as(test_owner)
      end

      it 'returns 404' do
        csrf_delete api_path(test_custom_domain.extid)

        expect(last_response.status).to eq(404)
        body = json_body
        expect(body['message']).to include('Sender configuration not found')
      end
    end

    context 'authorization checks' do
      before do
        Onetime::CustomDomain::MailerConfig.create!(
          domain_id: test_custom_domain.identifier,
          provider: 'ses',
          from_address: 'auth-test@example.com',
          api_key: 'auth-test-key',
          enabled: true,
        )
      end

      it 'returns 403 for non-owner' do
        login_as(test_non_owner)
        csrf_delete api_path(test_custom_domain.extid)

        expect(last_response.status).to eq(403)
      end
    end
  end

  # ==========================================================================
  # Response Serialization Tests
  # ==========================================================================

  describe 'response serialization' do
    before do
      enable_sender_feature_flag
      login_as(test_owner)
    end

    let!(:config_with_all_fields) do
      Onetime::CustomDomain::MailerConfig.create!(
        domain_id: test_custom_domain.identifier,
        provider: 'ses',
        from_name: 'Full Config Test',
        from_address: 'full@acme-corp.example.com',
        reply_to: 'full-reply@acme-corp.example.com',
        api_key: 'full-secret-value-here',
        enabled: true,
      )
    end

    it 'serializes all expected fields' do
      json_get api_path(test_custom_domain.extid)

      expect(last_response.status).to eq(200)

      body = json_body
      record = body['record']

      expected_keys = %w[
        domain_id
        provider
        from_name
        from_address
        reply_to
        enabled
        verification_status
        verified
        dkim_record
        spf_record
        api_key_masked
        created_at
        updated_at
      ]

      expected_keys.each do |key|
        expect(record).to have_key(key), "Expected record to have key '#{key}'"
      end
    end

    it 'masks api_key correctly for various lengths' do
      # Test short key
      config_with_all_fields.api_key = 'ab'
      config_with_all_fields.save

      json_get api_path(test_custom_domain.extid)
      body = json_body
      record = body['record']

      # Short secrets should still be masked (8 bullet chars, no trailing)
      expect(record['api_key_masked']).to eq("\u2022" * 8)
    end

    it 'returns JSON content type' do
      json_get api_path(test_custom_domain.extid)

      expect(last_response.content_type).to include('application/json')
    end

    it 'does not expose raw api_key in any response field' do
      json_get api_path(test_custom_domain.extid)

      body_text = last_response.body
      # The raw key value should never appear in the response
      expect(body_text).not_to include('full-secret-value-here')
    end
  end
end
