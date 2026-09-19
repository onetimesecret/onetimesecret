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
          expect_public_observation(observation, expectation)
        else
          expect_protected_observation(observation, expectation, surface)
        end
      end
    end
  end

  # The one state the matrix rows do not cover is the healthy one, and it is
  # where the two public surfaces differ (#4455, divergence D8 in the doc). Both
  # verify the same live session and expose the same identity; only the page
  # load, which a person asked for, counts as activity.
  {
    hydrated_html: :touched,
    bootstrap: :unchanged,
  }.each do |surface, activity|
    it "verifies an active session on #{surface} and leaves its active-session row #{activity}", :aggregate_failures do
      establish_matrix_session!
      before_activity = activity_snapshot

      observation, activity_writes = capture_activity_writes do
        request_surface(surface, request_id: "matrix-active-#{surface}")
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
        activity,
        before_activity,
        activity_snapshot,
        1,
        activity_count,
        activity_writes,
      )
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
