# try/api/v1/v1_routes_auth_attribute_try.rb
#
# frozen_string_literal: true

# Tests that V1 routes use openapi_auth= instead of auth= in routes.txt.
#
# V1 uses controller-level auth (authorized(true|false)), NOT Otto's
# route-level auth strategies. If V1 routes declare auth= attributes,
# Otto's RouteAuthWrapper will try to enforce strategies that V1 never
# registered — causing 401 errors on every request.
#
# The fix renames auth= to openapi_auth= so:
#   - Otto ignores it (RouteAuthWrapper reads option(:auth) only)
#   - The OpenAPI parser still reads auth metadata via openapi_auth=
#
# These tests prevent regression if someone adds a new V1 route with
# the wrong attribute name.

require 'otto'

@v1_routes_path = File.expand_path('../../../apps/api/v1/routes.txt', __dir__)
@route_lines = File.readlines(@v1_routes_path)
                    .map(&:strip)
                    .reject { |line| line.empty? || line.start_with?('#') }

# Parse each route line into its parts for structured assertions.
# Each entry: { verb:, path:, definition:, params: { key => value } }
@parsed_routes = @route_lines.map do |line|
  parts = line.split(/\s+/, 3)
  verb = parts[0]
  path = parts[1]
  definition = parts[2]

  # Extract key=value params from the definition tail
  def_parts = definition.split(/\s+/)
  target = def_parts.shift
  params = {}
  def_parts.each do |part|
    key, value = part.split('=', 2)
    params[key] = value if key && value
  end

  { verb: verb, path: path, target: target, definition: definition, params: params }
end

# -----------------------------------------------------------------------
# TEST: No V1 route declares Otto-enforced auth= attribute
# -----------------------------------------------------------------------

## TC-1: routes.txt contains at least one route (sanity check)
@parsed_routes.size
#=:> Integer
#==> @parsed_routes.size > 0

## TC-2: No V1 route has an auth= param (Otto would enforce it)
routes_with_auth = @parsed_routes.select { |r| r[:params].key?('auth') }
routes_with_auth.map { |r| "#{r[:verb]} #{r[:path]}" }
#=> []

## TC-3: Every V1 route has openapi_auth= (OpenAPI metadata preserved)
routes_without_openapi_auth = @parsed_routes.reject { |r| r[:params].key?('openapi_auth') }
routes_without_openapi_auth.map { |r| "#{r[:verb]} #{r[:path]}" }
#=> []

## TC-4: openapi_auth values are non-empty on every route
routes_with_empty_auth = @parsed_routes.select { |r| r[:params]['openapi_auth'].to_s.strip.empty? }
routes_with_empty_auth.map { |r| "#{r[:verb]} #{r[:path]}" }
#=> []

# -----------------------------------------------------------------------
# TEST: Otto RouteDefinition sees no auth requirements for V1 routes
# -----------------------------------------------------------------------

## TC-5: RouteDefinition.auth_requirements is empty for a V1 route with openapi_auth
# This confirms Otto's RouteAuthWrapper will skip auth enforcement.
rd = Otto::RouteDefinition.new('GET', '/status', 'V1::Controllers::Index#status openapi_auth=basic,anonymous response=json')
rd.auth_requirements
#=> []

## TC-6: RouteDefinition.auth_requirements would be non-empty with auth= (contrast)
rd_with_auth = Otto::RouteDefinition.new('GET', '/status', 'V1::Controllers::Index#status auth=basic,anonymous response=json')
rd_with_auth.auth_requirements
#=> ['basic', 'anonymous']

## TC-7: RouteDefinition sees openapi_auth as a custom option
rd = Otto::RouteDefinition.new('GET', '/status', 'V1::Controllers::Index#status openapi_auth=basic,anonymous response=json')
rd.option(:openapi_auth)
#=> 'basic,anonymous'

## TC-8: RouteDefinition has no :auth option for V1-style routes
rd = Otto::RouteDefinition.new('POST', '/share', 'V1::Controllers::Index#share openapi_auth=basic,anonymous content=form response=json')
rd.has_option?(:auth)
#=> false

## TC-9: All parsed V1 routes produce empty auth_requirements via RouteDefinition
failing_routes = @parsed_routes.select do |r|
  rd = Otto::RouteDefinition.new(r[:verb], r[:path], r[:definition])
  !rd.auth_requirements.empty?
end
failing_routes.map { |r| "#{r[:verb]} #{r[:path]}" }
#=> []

# -----------------------------------------------------------------------
# TEST: V1 route auth metadata values are valid
# -----------------------------------------------------------------------

## TC-10: All openapi_auth values use only known auth schemes
known_schemes = %w[basic anonymous]
invalid_routes = @parsed_routes.reject do |r|
  schemes = r[:params]['openapi_auth'].to_s.split(',')
  schemes.all? { |s| known_schemes.include?(s) }
end
invalid_routes.map { |r| "#{r[:verb]} #{r[:path]} openapi_auth=#{r[:params]['openapi_auth']}" }
#=> []

## TC-11: Status endpoint allows anonymous access
status_route = @parsed_routes.find { |r| r[:verb] == 'GET' && r[:path] == '/status' }
status_route[:params]['openapi_auth'].split(',').include?('anonymous')
#=> true

## TC-12: Authcheck endpoint requires basic auth only (no anonymous)
authcheck_route = @parsed_routes.find { |r| r[:verb] == 'GET' && r[:path] == '/authcheck' }
authcheck_route[:params]['openapi_auth']
#=> 'basic'

## TC-13: Every V1 route has response=json
routes_without_json = @parsed_routes.reject { |r| r[:params]['response'] == 'json' }
routes_without_json.map { |r| "#{r[:verb]} #{r[:path]}" }
#=> []
