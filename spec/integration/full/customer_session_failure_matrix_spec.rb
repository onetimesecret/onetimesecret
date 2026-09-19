# frozen_string_literal: true

require 'spec_helper'
require_relative '../../support/customer_session_failure_matrix'

RSpec.describe 'Cross-surface customer-session failure matrix (#4452)', type: :integration do
  include_context 'auth_rack_test'
  include CustomerSessionFailureMatrix

  let(:matrix_password) { 'Matrix-Test1234!' }

  before do
    @matrix_customer = anonymous_probe_customer
  end

  CustomerSessionFailureMatrix::STATES.each do |state, expectation|
    CustomerSessionFailureMatrix::SURFACES.each_key do |surface|
      it "records #{state} on #{surface}", :aggregate_failures do
        establish_matrix_session! unless state == :missing_anonymous
        apply_matrix_state!(state)

        before_activity = activity_snapshot
        before_count    = activity_count
        request_id      = "matrix-#{state}-#{surface}"
        observation     = nil

        with_matrix_state_dependencies(state) do
          observation, activity_writes = capture_activity_writes do
            request_surface(surface, request_id: request_id)
          end
          after_activity = activity_snapshot
          after_count    = activity_count

          expect_activity(
            expectation.fetch(:activity).fetch(surface),
            before_activity,
            after_activity,
            before_count,
            after_count,
            activity_writes,
          )
        end

        expect(observation[:request_id]).to eq(request_id)
        expect(observation[:verdict]).to eq(expectation.fetch(:verdict))
        expect(observation[:refusal_markers]).to eq(expectation.fetch(:markers).fetch(surface))

        if public_surface?(surface)
          expect_public_observation(observation, expectation.fetch(:public))
        else
          expect_protected_observation(observation, expectation.fetch(:protected), surface)
        end
      end
    end
  end

  it 'keeps hydrated HTML on the current active-session activity policy pending #4455', :aggregate_failures do
    establish_matrix_session!
    before_activity = activity_snapshot

    observation, activity_writes = capture_activity_writes do
      request_surface(:hydrated_html, request_id: 'matrix-active-hydrated-html')
    end

    expect(observation).to include(
      status: 200,
      verdict: :authenticated,
      authenticated: true,
      awaiting_mfa: false,
      customer_exposed: true,
      identity_exposed: true,
    )
    expect_activity(
      :touched,
      before_activity,
      activity_snapshot,
      1,
      activity_count,
      activity_writes,
    )
  end

  def public_surface?(surface)
    %i[hydrated_html bootstrap].include?(surface)
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
      raise ArgumentError, "unknown public verdict: #{verdict}"
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

  def expect_activity(expected, before_activity, after_activity, before_count, after_count, writes)
    inserts = writes.grep(/\bINSERT\b/i)
    updates = writes.grep(/\bUPDATE\b/i)
    deletes = writes.grep(/\bDELETE\b/i)

    expect(inserts).to be_empty

    case expected
    when :not_applicable
      expect(before_count).to eq(0)
      expect(after_count).to eq(0)
      expect(after_activity).to be_nil
      expect(writes).to be_empty
    when :unchanged
      expect(before_count).to eq(1)
      expect(after_count).to eq(1)
      expect(after_activity).to eq(before_activity)
      expect(writes).to be_empty
    when :deleted
      expect(before_count).to eq(1)
      expect(after_count).to eq(0)
      expect(after_activity).to be_nil
      expect(deletes).not_to be_empty
      expect(updates).to be_empty
    when :touched
      expect(before_count).to eq(1)
      expect(after_count).to eq(1)
      expect(after_activity.fetch(:created_at)).to eq(before_activity.fetch(:created_at))
      expect(after_activity.fetch(:last_use)).to be > before_activity.fetch(:last_use)
      expect(updates).not_to be_empty
      expect(deletes).to be_empty
    else
      raise ArgumentError, "unknown activity expectation: #{expected}"
    end
  end
end
