# spec/integration/full/auth_route_failure_code_coverage_spec.rb
#
# frozen_string_literal: true

# #4469, acceptance criterion 2, against the LIVE Rodauth route set.
#
# Rodauth freezes route_hash in post_configure, so this reads the mounted
# routes rather than a transcription of them (the pattern of
# apps/web/auth/spec/integration/full/signin_gate_enforcement_spec.rb). A
# feature enabled tomorrow adds its routes here and fails until
# AuthRouteFailureCodes::RODAUTH_ROUTES declares them. The unit spec
# (spec/unit/onetime/session/failure_code_route_coverage_spec.rb) checks the
# same declaration against the gates' route universe in every lane.
#
# Also pins the two router constants that decide how the router's own
# refusals reach a route (anonymous routes continue as anonymous, MFA-pending
# routes are the only ones a half-authenticated session may reach) to the
# same declaration, so the three cannot drift apart.

require 'spec_helper'

RSpec.describe 'auth route failure-code coverage against the mounted Rodauth routes (#4469)', type: :integration do
  include_context 'auth_rack_test'

  before do
    skip 'requires full auth mode' unless Onetime.auth_config.full_enabled?
    app # mount, so Auth::Config is configured
  end

  def mounted_route_names
    Auth::Config.route_hash.values.map { |meth| meth.to_s.delete_prefix('handle_').to_sym }
  end

  def rodauth_routes(names)
    names.reject { |name| AuthRouteFailureCodes.omniauth_route?(name) }
  end

  it 'reads a non-trivial route set (guards against a vacuous pass)' do
    expect(mounted_route_names).to include(:login, :logout)
    expect(mounted_route_names.size).to be >= 8
  end

  it 'declares a requirement and failure codes for every mounted Rodauth route' do
    undeclared = rodauth_routes(mounted_route_names) - AuthRouteFailureCodes::RODAUTH_ROUTES.keys

    expect(undeclared).to be_empty,
      "mounted Rodauth routes with no failure-code declaration: #{undeclared.inspect}\n" \
      'Add each to AuthRouteFailureCodes::RODAUTH_ROUTES (spec/support/auth_route_failure_codes.rb).'
  end

  it 'agrees with the router on which mounted routes are served without a login' do
    anonymous = AuthRouteFailureCodes::RODAUTH_ROUTES.select { |_r, d| d[:requirement] == :anonymous }.keys
    mounted   = rodauth_routes(mounted_route_names)

    Auth::Router::ANONYMOUS_RODAUTH_ROUTES.each do |route|
      next unless mounted.include?(route)

      expect(anonymous).to include(route),
        "#{route} continues as anonymous in Auth::Router but is not declared :anonymous"
    end
  end

  it 'agrees with the router on which mounted routes an MFA-pending session may reach' do
    mfa_pending = AuthRouteFailureCodes::RODAUTH_ROUTES.select { |_r, d| d[:requirement] == :mfa_pending }.keys
    mounted     = rodauth_routes(mounted_route_names)

    Auth::Router::MFA_PENDING_RODAUTH_ROUTES.each do |route|
      next unless mounted.include?(route)

      expect(mfa_pending).to include(route),
        "#{route} is an MFA-pending route in Auth::Router but not declared :mfa_pending"
    end
  end
end
