# frozen_string_literal: true

require_relative '../integration_spec_helper'
require_relative '../../support/customer_session_failure_matrix'

RSpec.describe 'Cross-surface customer-session failure matrix in simple mode (#4452)', type: :integration do
  include_context 'auth_rack_test'
  include CustomerSessionFailureMatrix

  let(:matrix_password) { 'Matrix-Test1234!' }
  let(:app) do
    @simple_matrix_app ||= begin
      Onetime::Application::Registry.reset!
      Onetime::Application::Registry.prepare_application_registry
      Onetime::Application::Registry.generate_rack_url_map
    end
  end

  before(:all) do
    Onetime.boot! :test
  end

  before do
    skip 'requires simple auth mode' unless Onetime.auth_config.simple_enabled?

    @matrix_customer = anonymous_probe_customer
  end

  CustomerSessionFailureMatrix::SIMPLE_MODE_STATES.each do |state|
    CustomerSessionFailureMatrix::SURFACES.each_key do |surface|
      it "records #{state} on #{surface}", :aggregate_failures do
        establish_simple_matrix_session! unless state == :missing_anonymous
        apply_matrix_state!(state)

        expectation = CustomerSessionFailureMatrix::STATES.fetch(state)
        request_id  = "simple-matrix-#{state}-#{surface}"
        observation = request_surface(surface, request_id: request_id)

        expect(observation[:request_id]).to eq(request_id)
        expect(observation[:verdict]).to eq(expectation.fetch(:verdict))
        expect(observation[:refusal_markers]).to eq(expectation.fetch(:markers).fetch(surface))

        if %i[hydrated_html bootstrap].include?(surface)
          expect_public_observation(observation, expectation.fetch(:public))
        else
          expect_protected_observation(observation, expectation.fetch(:protected), surface)
        end
      end
    end
  end

  it 'documents active-session-only states as unavailable in simple mode' do
    auth_database = defined?(Auth::Database) ? Auth::Database.connection : nil
    expect(auth_database).to be_nil
    expect(CustomerSessionFailureMatrix::FULL_MODE_ACTIVE_SESSION_STATES).to contain_exactly(
      :revoked,
      :inactive,
      :absolute_expired,
      :authentication_database_unavailable,
    )
  end

  def expect_public_observation(observation, verdict)
    expect(observation[:status]).to eq(200)
    expect(observation[:refusal_code]).to be_nil

    case verdict
    when :anonymous
      expect(observation).to include(
        authenticated: false,
        awaiting_mfa: false,
        customer_exposed: false,
        identity_exposed: false,
      )
    when :mfa_pending
      expect(observation).to include(
        authenticated: false,
        awaiting_mfa: true,
        customer_exposed: false,
        identity_exposed: false,
      )
      expect(observation.fetch(:payload)).to include(
        CustomerSessionFailureMatrix::MFA_PROTECTED_ACCOUNT_FIELDS,
      )
    when :identity_exposed
      expect(observation).to include(
        authenticated: true,
        awaiting_mfa: false,
        customer_exposed: true,
        identity_exposed: true,
      )
    else
      raise ArgumentError, "unsupported simple-mode public verdict: #{verdict}"
    end
  end

  def expect_protected_observation(observation, verdict, surface)
    case verdict
    when :refused
      expect(observation[:status]).to eq(surface == :protected_html ? 302 : 401)
      expect(observation[:refusal_code]).to eq(surface == :protected_api ? 'Authentication Required' : nil)
      expect(observation).to include(identity_exposed: false, customer_exposed: false)
    when :authenticated
      expect(observation[:status]).to eq(200)
      expect(observation[:refusal_code]).to be_nil
      expect(observation).to include(identity_exposed: true, customer_exposed: true)
    else
      raise ArgumentError, "unknown protected verdict: #{verdict}"
    end
  end
end
