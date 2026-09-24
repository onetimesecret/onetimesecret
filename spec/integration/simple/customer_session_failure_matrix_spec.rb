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

        if public_surface?(surface)
          expect_public_observation(observation, expectation)
        else
          expect_protected_observation(observation, expectation, surface)
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
end
