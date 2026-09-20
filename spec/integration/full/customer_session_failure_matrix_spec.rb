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

  # RISK-2026-09-19-04: a client may declare a safe request passive
  # (X-Session-Activity). The declaration reaches the activity predicate and
  # nothing else, so every state must be decided, answered and coded exactly as
  # it is without the header.
  CustomerSessionFailureMatrix::STATES.each do |state, expectation|
    it "records #{state} on protected_api the same when the client declares the request passive", :aggregate_failures do
      establish_matrix_session! unless state == :missing_anonymous
      apply_matrix_state!(state)
      observation = nil

      with_matrix_state_dependencies(state) do
        observation = request_surface(:protected_api, request_id: "matrix-declared-#{state}", declare_passive: true)
      end

      expect(observation[:verdict]).to eq(expectation.fetch(:verdict))
      expect(observation[:refusal_markers]).to eq(expectation.fetch(:markers).fetch(:protected_api))
      expect_protected_observation(observation, expectation, :protected_api)
    end
  end

  # The one state the matrix rows do not cover is the healthy one, and it is
  # where the two public surfaces differ (#4455, divergence D8 in the doc). Both
  # verify the same live session and expose the same identity; only the page
  # load, which a person asked for, counts as activity.
  #
  # The protected API has the same two answers, chosen by the client instead
  # of the route (RISK-2026-09-19-04): a request counts unless the client
  # declared it passive.
  [
    [:hydrated_html, false, :touched],
    [:bootstrap, false, :unchanged],
    [:protected_api, false, :touched],
    [:protected_api, true, :unchanged],
  ].each do |surface, declared, activity|
    label = declared ? "#{surface} declared passive" : surface.to_s

    it "verifies an active session on #{label} and leaves its active-session row #{activity}", :aggregate_failures do
      establish_matrix_session!
      before_activity = activity_snapshot

      observation, activity_writes = capture_activity_writes do
        request_surface(surface, request_id: "matrix-active-#{surface}", declare_passive: declared)
      end

      expect(observation).to include(status: 200, verdict: :authenticated)
      if public_surface?(surface)
        expect(observation).to include(
          authenticated: true,
          awaiting_mfa: false,
          customer_exposed: true,
          identity_exposed: true,
        )
      end
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

  # RISK-2026-09-19-03. The API sent no Cache-Control at all. It now defaults
  # to private, no-store through the whole stack: a personalized 200, an
  # anonymous 200 and Otto's own 404. (A route's own policy is never
  # overwritten; spec/unit/onetime/middleware/api_cache_policy_spec.rb.)
  it 'never lets an /api response be stored', :aggregate_failures do
    establish_matrix_session!

    observation = request_surface(:protected_api, request_id: 'matrix-api-cache')
    expect(observation).to include(status: 200, cache_control: 'private, no-store')

    get '/api/v2/status', {}, { 'HTTP_ACCEPT' => 'application/json' }
    expect(last_response.headers['cache-control']).to eq('private, no-store')

    get '/api/v2/no-such-route', {}, { 'HTTP_ACCEPT' => 'application/json' }
    expect(last_response.status).to eq(404)
    expect(last_response.headers['cache-control']).to eq('private, no-store')
  end

  # #4461. The /auth app answers nothing but authentication state, so every
  # response it finishes is unstorable: a success, a refusal, and a route that
  # sets its own policy keeps a policy that is at least as strict.
  it 'never lets an /auth authentication-state response be stored', :aggregate_failures do
    establish_matrix_session!
    expect(last_response.headers['cache-control']).to eq('private, no-store') # the login itself

    header 'Accept', 'application/json'
    get '/auth/account'
    expect(last_response.status).to eq(200)
    expect(last_response.headers['cache-control']).to eq('private, no-store')
    expect(last_response.headers['content-type']).to include('application/json')

    active_session_rows.delete
    get '/auth/account'
    expect(last_response.status).to eq(401)
    expect(JSON.parse(last_response.body)).to include('code' => 'active_session_revoked')
    expect(last_response.headers['cache-control']).to eq('private, no-store')
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
