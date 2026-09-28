# spec/unit/onetime/session/failure_code_route_coverage_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Unit (reads route tables and route modules as data; boots nothing)
# =============================================================================
#
# #4469, acceptance criterion 2: every auth and account route has a declared
# authentication requirement and failure code, and a route that exists
# without a declaration fails here.
#
# The declaration is spec/support/auth_route_failure_codes.rb. The inventories
# it is checked against are read from the app, not typed in:
#
#   - every `apps/**/routes.txt` row, parsed with Otto::RouteDefinition;
#   - the Rodauth route universe the two existing gates maintain
#     (Auth::SigninGate, Auth::RestrictTo, ADR-038), whose own specs check it
#     against the live route_hash; the full-mode integration spec
#     (spec/integration/full/auth_route_failure_code_coverage_spec.rb) reads
#     that route_hash directly;
#   - the string literals apps/web/auth/routes/*.rb dispatch on.
#
# What is NOT here: whether each route really answers its declared codes.
# That is the behaviour the surface specs cover (basicauth_fallthrough_spec,
# the middleware and strategy specs, auth_credential_failure_code_spec).
# =============================================================================

require 'spec_helper'
require 'onetime/session/failure_code'

# The two gate modules are boot-free policy tables (see their file comments).
require_relative '../../../../apps/web/auth/signin_gate'
require_relative '../../../../apps/web/auth/restrict_to'

RSpec.describe 'auth and account route failure-code coverage (#4469)' do
  let(:declaration) { AuthRouteFailureCodes }

  # ---------------------------------------------------------------------------
  # Otto surfaces
  # ---------------------------------------------------------------------------
  describe 'Otto route tables' do
    let(:routes) { declaration.otto_routes }

    it 'reads a non-trivial inventory (guards against a vacuous pass)' do
      expect(routes.size).to be > 200
      expect(routes.map(&:table).uniq).to include(
        'apps/api/account/routes.txt', 'apps/web/core/routes.txt', 'apps/api/colonel/routes.txt',
      )
    end

    it 'declares a code set for every strategy any route names' do
      unknown = routes.reject { |route| declaration.codes_for(route) }

      expect(unknown.map(&:label)).to be_empty,
        "routes naming a strategy with no declared failure codes: #{unknown.map(&:label).inspect}\n" \
        'Add the strategy to AuthRouteFailureCodes::STRATEGY_CODES with the codes its refusal carries.'
    end

    it 'declares every route that has no auth= option as anonymous, with its reason' do
      undeclared = routes.select(&:anonymous_by_default?).reject { |route| declaration.declared_anonymous?(route) }

      expect(undeclared.map(&:label)).to be_empty,
        "routes with no auth= option and no declaration: #{undeclared.map(&:label).inspect}\n" \
        'Give the row an auth= option, or declare it in AuthRouteFailureCodes::ANONYMOUS_OTTO_ROUTES ' \
        'with the reason it needs none.'
    end

    it 'names only routes that exist in ANONYMOUS_OTTO_ROUTES and HANDLER_CODES (no stale declarations)' do
      by_table = routes.group_by(&:table)

      declaration::ANONYMOUS_OTTO_ROUTES.each do |table, rows|
        expect(by_table).to have_key(table), "#{table} is declared but no such route table exists"
        next if rows == :all

        auth_less = by_table.fetch(table).select(&:anonymous_by_default?).map(&:row)
        stale     = rows - auth_less
        expect(stale).to be_empty,
          "#{table} declares anonymous rows that do not exist or now carry auth=: #{stale.inspect}"
      end

      declaration::HANDLER_CODES.each_key do |(table, verb, path)|
        found = by_table.fetch(table, []).any? { |route| route.verb == verb && route.path == path }
        expect(found).to be(true), "HANDLER_CODES names #{verb} #{path} in #{table}, which does not exist"
      end
    end

    it 'gives a session-protected route the session codes and a Basic auth route the API key codes' do
      account = routes.find { |route| route.table == 'apps/api/account/routes.txt' && route.path == '/' }
      expect(account.auth).to eq(%w[sessionauth basicauth])
      expect(declaration.codes_for(account)).to match_array(
        declaration::SESSION_CODES + %i[api_key_invalid suspended_credentials],
      )
    end

    it 'gives the simple-mode sign-in its handler-owned credential codes' do
      login = routes.find do |route|
        route.table == 'apps/web/core/routes.txt' && route.verb == 'POST' && route.path == '/auth/login'
      end
      expect(login.auth).to eq(%w[noauth])
      expect(declaration.codes_for(login)).to contain_exactly(:invalid_credentials, :suspended_credentials)
    end

    it 'uses only codes from the one vocabulary' do
      every_code = declaration::STRATEGY_CODES.values.flatten + declaration::HANDLER_CODES.values.flatten
      expect(every_code.uniq - Onetime::SessionFailureCode::CODES.keys).to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # Rodauth routes
  # ---------------------------------------------------------------------------
  describe 'Rodauth routes' do
    # The universe both gates classify exhaustively (their specs fail on a
    # mounted route they do not know).
    let(:known_routes) do
      (Auth::SigninGate::GATED_ROUTES + Auth::SigninGate::UNGATED_ROUTES +
        Auth::RestrictTo::PRE_AUTH_ROUTES.keys + Auth::RestrictTo::UNGATED_ROUTES).uniq
    end

    it 'reads a non-trivial universe (guards against a vacuous pass)' do
      expect(known_routes).to include(:login, :logout, :change_password, :otp_auth)
      expect(known_routes.size).to be >= 30
    end

    it 'declares a requirement and codes for every route the gates know' do
      undeclared = known_routes - declaration::RODAUTH_ROUTES.keys

      expect(undeclared).to be_empty,
        "Rodauth routes with no failure-code declaration: #{undeclared.inspect}\n" \
        'Add each to AuthRouteFailureCodes::RODAUTH_ROUTES with its requirement ' \
        '(:anonymous / :login_required / :mfa_pending) and whether it checks a credential.'
    end

    it 'declares no route the gates have never heard of' do
      stale = declaration::RODAUTH_ROUTES.keys - known_routes

      expect(stale).to be_empty,
        "declared here but unknown to Auth::SigninGate and Auth::RestrictTo: #{stale.inspect}"
    end

    it 'agrees with the gates on which routes are served without a login' do
      # Everything RestrictTo gates is a pre-auth (anonymous) route.
      Auth::RestrictTo::PRE_AUTH_ROUTES.each_key do |route|
        expect(declaration::RODAUTH_ROUTES.fetch(route).fetch(:requirement)).to eq(:anonymous),
          "#{route} is a pre-auth route for restrict_to but not declared :anonymous here"
      end
      # The second-factor ceremony is exactly RestrictTo's exemption for it.
      mfa_pending = declaration::RODAUTH_ROUTES.select { |_r, d| d[:requirement] == :mfa_pending }.keys
      expect(mfa_pending).to include(*Auth::RestrictTo::SECOND_FACTOR_ROUTES.keys)
    end

    it 'derives a code set from every declaration' do
      declaration::RODAUTH_ROUTES.each do |route, entry|
        codes = declaration.codes_for_declaration(entry)
        expect(codes - Onetime::SessionFailureCode::CODES.keys).to be_empty, "#{route} declares an unknown code"
        expect(codes).to include(:invalid_credentials) if entry[:credential]
        expect(codes).to include(:session_missing) unless entry[:requirement] == :anonymous
      end
    end

    it 'declares the login as a credential route that never carries a session code of its own' do
      expect(declaration.codes_for_declaration(declaration::RODAUTH_ROUTES.fetch(:login)))
        .to contain_exactly(:invalid_credentials)
    end
  end

  # ---------------------------------------------------------------------------
  # Custom Roda routes
  # ---------------------------------------------------------------------------
  describe 'custom /auth routes' do
    let(:literals) { declaration.custom_auth_route_literals }

    it 'reads a non-trivial inventory (guards against a vacuous pass)' do
      expect(literals.keys).to include('account', 'reauth', 'link-sso', 'active-sessions')
    end

    it 'declares a requirement and codes for every literal the route modules dispatch on' do
      undeclared = literals.reject { |literal, _where| declaration::CUSTOM_AUTH_ROUTES.key?(literal) }

      expect(undeclared).to be_empty,
        "custom /auth routes with no failure-code declaration: #{undeclared.inspect}\n" \
        'Add each to AuthRouteFailureCodes::CUSTOM_AUTH_ROUTES.'
    end

    it 'declares no literal the route modules no longer dispatch on' do
      stale = declaration::CUSTOM_AUTH_ROUTES.keys - literals.keys

      expect(stale).to be_empty, "declared but not dispatched on by apps/web/auth/routes/*.rb: #{stale.inspect}"
    end

    it 'derives a code set from every declaration' do
      declaration::CUSTOM_AUTH_ROUTES.each do |route, entry|
        codes = declaration.codes_for_declaration(entry)
        expect(codes - Onetime::SessionFailureCode::CODES.keys).to be_empty, "#{route} declares an unknown code"
      end
    end
  end
end
