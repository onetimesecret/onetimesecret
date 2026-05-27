# apps/web/auth/spec/router_error_shape_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Unit (translator) + Wiring (stub Roda app)
# =============================================================================
#
# Regression guard for ADR-013 on the Auth Router.
#
# The Auth app runs on Roda, not Otto. Typed Onetime exceptions are mapped to
# the ADR-013 wire shape by Auth::ErrorTranslator and wired into the router
# via Roda's :error_handler plugin.
#
# This spec covers two layers:
#
#   1. ErrorTranslator (pure unit) — per-exception status + body assertions.
#   2. Wiring — a stub Roda app that mirrors production Auth::Router
#      configuration (plugin order, body encoding), exercised via Rack::Test.
#      If the wiring pattern stops working in a Roda upgrade or refactor,
#      this fails.
#
# Lives at apps/web/auth/spec/ root (not under integration/) because the
# spec needs no Valkey, no DB, and no full-mode boot — the auth spec_helper
# gates integration helpers and DB flushing on type: :integration tag.
#
# RUN:
#   pnpm run test:rspec apps/web/auth/spec/router_error_shape_spec.rb
#
# =============================================================================

require_relative 'spec_helper'
require 'rack/test'
require 'roda'
require 'json'
require_relative '../error_translator'

RSpec.describe 'Auth Router ADR-013 error shape' do
  # ---------------------------------------------------------------------------
  # ErrorTranslator unit tests
  # ---------------------------------------------------------------------------
  describe Auth::ErrorTranslator do
    it 'translates Onetime::RecordNotFound to 404 with class name' do
      status, body = described_class.translate(Onetime::RecordNotFound.new('missing'))
      expect(status).to eq(404)
      expect(body).to include(error: 'missing', error_type: 'RecordNotFound')
    end

    it 'translates Onetime::MissingSecret (subclass of RecordNotFound) to 404' do
      status, body = described_class.translate(Onetime::MissingSecret.new('gone'))
      expect(status).to eq(404)
      expect(body[:error_type]).to eq('RecordNotFound')
    end

    it 'translates Onetime::FormError to 422 carrying field and error_type' do
      ex = Onetime::FormError.new('invalid email', field: 'email', error_type: 'FormError')
      status, body = described_class.translate(ex)
      expect(status).to eq(422)
      expect(body).to include(error: 'invalid email', error_type: 'FormError', field: 'email')
    end

    it 'translates Onetime::Forbidden to 403' do
      status, body = described_class.translate(Onetime::Forbidden.new('denied'))
      expect(status).to eq(403)
      expect(body).to include(error: 'denied', error_type: 'Forbidden')
    end

    it 'translates Onetime::LimitExceeded to 429 carrying retry_after' do
      ex = Onetime::LimitExceeded.new('slow down', retry_after: 60, attempts: 5, max_attempts: 5)
      status, body = described_class.translate(ex)
      expect(status).to eq(429)
      expect(body).to include(error_type: 'LimitExceeded', retry_after: 60, attempts: 5, max_attempts: 5)
    end

    it 'translates Onetime::EntitlementRequired to 403 carrying upgrade path' do
      ex = Onetime::EntitlementRequired.new(:api_access, current_plan: 'free', upgrade_to: 'pro')
      status, body = described_class.translate(ex)
      expect(status).to eq(403)
      expect(body).to include(error_type: 'EntitlementRequired',
                              entitlement: :api_access,
                              current_plan: 'free',
                              upgrade_to: 'pro')
    end

    it 'translates Onetime::GuestRoutesDisabled to 403 carrying code' do
      ex = Onetime::GuestRoutesDisabled.new('disabled', code: 'GUEST_CONCEAL_DISABLED')
      status, body = described_class.translate(ex)
      expect(status).to eq(403)
      expect(body).to include(error_type: 'GuestRoutesDisabled', code: 'GUEST_CONCEAL_DISABLED')
    end

    it 'translates Onetime::Unauthorized to 401 using the caller message' do
      status, body = described_class.translate(Onetime::Unauthorized.new('Invalid credentials'))
      expect(status).to eq(401)
      expect(body).to eq(error: 'Invalid credentials', error_type: 'Unauthorized')
    end

    it 'translates an unknown exception to a generic 500 without leaking the message' do
      status, body = described_class.translate(StandardError.new('internal detail'))
      expect(status).to eq(500)
      # The caller message must NOT appear in the response body.
      expect(body).to eq(error: 'Internal Server Error', error_type: 'ServerError')
    end

    it 'falls back to 500 for nil-class edge cases (defensive)' do
      # Bare Exception is not a known type and falls through to the default.
      status, body = described_class.translate(Exception.new('explode'))
      expect(status).to eq(500)
      expect(body[:error_type]).to eq('ServerError')
    end
  end

  # ---------------------------------------------------------------------------
  # Wiring test
  #
  # Stub Roda app mirrors the production Auth::Router wiring of
  # `plugin :error_handler` + `Auth::ErrorTranslator.translate`. If the
  # plugin contract changes (e.g. Roda renames :error_handler) or our
  # block stops setting the response correctly, this fails.
  # ---------------------------------------------------------------------------
  describe 'Roda :error_handler plugin wiring' do
    include Rack::Test::Methods

    let(:app) do
      # Mirror Auth::Router's plugin order EXACTLY:
      #   plugin :json, parser: true     <- loaded first
      #   plugin :error_handler          <- loaded after :json
      # The error_handler block explicitly .to_json's the body so that the
      # wire shape is invariant under future Roda plugin-order changes. If
      # someone removes the manual encoding believing :json will wrap the
      # error_handler return value, the production app may silently break
      # under a Roda upgrade — this spec proves the current contract works
      # with the actual plugin layering.
      Class.new(Roda) do
        plugin :json, parser: true
        plugin :error_handler do |e|
          status, body = Auth::ErrorTranslator.translate(e)
          response.status           = status
          response['content-type']  = 'application/json'
          body.to_json
        end

        route do |r|
          r.get('record-not-found') { raise Onetime::RecordNotFound, 'missing' }
          r.get('form-error') do
            raise Onetime::FormError.new('bad email', field: 'email', error_type: 'FormError')
          end
          r.get('forbidden')   { raise Onetime::Forbidden, 'denied' }
          r.get('rate-limit')  { raise Onetime::LimitExceeded.new('slow', retry_after: 60) }
          r.get('unknown')     { raise StandardError, 'leaky internal' }
        end
      end
    end

    it 'returns 404 ADR-013 shape for a route raising RecordNotFound' do
      get '/record-not-found'
      expect(last_response.status).to eq(404)
      expect(last_response.content_type).to include('application/json')
      body = JSON.parse(last_response.body)
      expect(body).to include('error' => 'missing', 'error_type' => 'RecordNotFound')
    end

    it 'returns 422 ADR-013 shape with field for FormError' do
      get '/form-error'
      expect(last_response.status).to eq(422)
      body = JSON.parse(last_response.body)
      expect(body).to include('error' => 'bad email',
                              'error_type' => 'FormError',
                              'field' => 'email')
    end

    it 'returns 403 ADR-013 shape for Forbidden' do
      get '/forbidden'
      expect(last_response.status).to eq(403)
      body = JSON.parse(last_response.body)
      expect(body).to include('error' => 'denied', 'error_type' => 'Forbidden')
    end

    it 'returns 429 ADR-013 shape with retry_after for LimitExceeded' do
      get '/rate-limit'
      expect(last_response.status).to eq(429)
      body = JSON.parse(last_response.body)
      expect(body).to include('error_type' => 'LimitExceeded', 'retry_after' => 60)
    end

    it 'returns a generic 500 for unknown exceptions without leaking the message' do
      get '/unknown'
      expect(last_response.status).to eq(500)
      body = JSON.parse(last_response.body)
      expect(body).to eq('error' => 'Internal Server Error', 'error_type' => 'ServerError')
    end
  end

  # ---------------------------------------------------------------------------
  # Router-level 404 fallback contract
  #
  # Auth::Router has two 404 paths:
  #   - status_handler(404)            (Roda plugin entry)
  #   - route-block catch-all          (`response.status = 404; ...`)
  #
  # Both reference the same constant — Auth::ErrorTranslator::NOT_FOUND_BODY —
  # so they cannot drift apart. This spec pins the constant's shape; if a
  # future change re-inlines a literal in either site, code review catches
  # it (the constant becomes unused).
  # ---------------------------------------------------------------------------
  describe 'router-level 404 fallback constant' do
    it 'Auth::ErrorTranslator::NOT_FOUND_BODY has ADR-013 shape' do
      expect(Auth::ErrorTranslator::NOT_FOUND_BODY).to eq(
        error: 'Not Found',
        error_type: 'NotFound',
      )
    end

    it 'Auth::ErrorTranslator::NOT_FOUND_BODY is frozen (cannot be mutated by routing)' do
      expect(Auth::ErrorTranslator::NOT_FOUND_BODY).to be_frozen
    end
  end
end
