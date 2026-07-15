# try/integration/api/colonel/bfla_colonel_authz_try.rb
#
# frozen_string_literal: true

# BFLA (Broken Function-Level Authorization) hardening tryout for the Colonel
# admin API — part of the cutover & hardening slice
# (docs/specs/colonel-ui/50-cutover-hardening.md, issue #50).
#
# This is the perimeter guard for the ENTIRE `/api/colonel/*` surface. Rather
# than trust a hand-maintained list, it enumerates every route directly from
# `apps/api/colonel/routes.txt` and, for each one:
#
#   1. Fires a STANDARD (non-colonel, verified) user's session at it and asserts
#      the response is 403 or 404 — never 200/2xx and never a 500. A standard
#      user must be able to reach NOTHING on the admin surface.
#   2. Fires an anonymous request at it and asserts 401 or 404.
#
# It also asserts the TWO-LAYER AUTHZ INVARIANT holds statically for every
# route (both layers must be present — belt and braces):
#
#   Layer 1 (router): every `/api/colonel` route line in routes.txt declares
#           `role=colonel` and `scope=internal`.
#   Layer 2 (logic):  every referenced logic class calls
#           `verify_one_of_roles!(colonel: true)` in its `raise_concerns`.
#
# If a new admin route is added without both layers, or without the role gate,
# this tryout fails — the enumeration is derived from the routes file, so it
# cannot silently drift.
#
# Run: try --agent try/integration/api/colonel/bfla_colonel_authz_try.rb

require 'rack/test'
require_relative '../../../support/test_helpers'

OT.boot! :test

require 'onetime/application/registry'
Onetime::Application::Registry.prepare_application_registry

@test = Object.new
@test.extend Rack::Test::Methods
def @test.app
  Onetime::Application::Registry.generate_rack_url_map
end
def get(*args);    @test.get(*args);    end
def post(*args);   @test.post(*args);   end
def delete(*args); @test.delete(*args); end
def put(*args);    @test.put(*args);    end
def patch(*args);  @test.patch(*args);  end
def last_response; @test.last_response; end

@root         = File.expand_path('../../../../', __dir__)
@routes_file  = File.join(@root, 'apps/api/colonel/routes.txt')
@logic_dir    = File.join(@root, 'apps/api/colonel/logic/colonel')
@uri_prefix   = '/api/colonel'

# ---- Parse routes.txt --------------------------------------------------

# Each entry: { method:, path:, logic:, line: } for non-comment route lines.
@routes = []
File.foreach(@routes_file) do |raw|
  line = raw.strip
  next if line.empty? || line.start_with?('#')

  # METHOD  /path  Logic::Class  key=val key=val ...
  parts  = line.split(/\s+/)
  method = parts[0]
  path   = parts[1]
  logic  = parts[2]
  next unless %w[GET POST PUT PATCH DELETE].include?(method)

  @routes << { method: method, path: path, logic: logic, attrs: parts[3..] || [], line: line }
end

# Substitute a concrete-but-harmless value for every `:param` segment so the
# router matches the route (we want to hit the role gate, not a 404 for an
# unmatched path). A leading `:` marks a dynamic segment.
def concretize(path)
  path.split('/').map { |seg| seg.start_with?(':') ? 'bfla-probe' : seg }.join('/')
end

# ---- Test principals ---------------------------------------------------

@ts = Familia.now.to_i

# STANDARD user: authenticated + verified, but NOT a colonel. The strongest
# BFLA subject — even a fully-verified ordinary account must be denied.
@regular = Onetime::Customer.create!(email: "bfla_regular_#{@ts}@example.com")
@regular.verified = 'true'
@regular.save

@regular_session = {
  'authenticated' => true,
  'external_id'   => @regular.extid,
  'email'         => @regular.email,
}

# Build the request env. CONTENT_TYPE is set ONLY for body methods — a GET/DELETE
# carrying `Content-Type: application/json` with no body makes the rack-parser
# middleware try to read a nil rack.input (a harness artifact, not an app authz
# signal). `session` is nil for the anonymous principal.
def headers_for(method, session)
  h = { 'HTTP_ACCEPT' => 'application/json' }
  h['rack.session'] = session if session
  h['CONTENT_TYPE'] = 'application/json' if %w[POST PUT PATCH].include?(method)
  h
end

# Fire one request. Empty params are enough: the router role gate rejects a
# non-colonel BEFORE any body parsing, which is exactly what we are asserting.
# An exception (an unexpected 500-class fault reaching the handler) is itself an
# authorization offender, so surface it as a synthetic status.
def fire(method, url, session)
  headers = headers_for(method, session)
  case method
  when 'GET'    then get    url, {}, headers
  when 'DELETE' then delete url, {}, headers
  when 'POST'   then post   url, {}, headers
  when 'PUT'    then put    url, {}, headers
  when 'PATCH'  then patch  url, {}, headers
  end
  last_response.status
rescue StandardError => e
  "raised:#{e.class}: #{e.message}"
end

# ---- Collect offenders (computed once, asserted below) -----------------

@standard_offenders = [] # standard user reached something it shouldn't (not 403/404)
@anon_offenders     = [] # anonymous got an unexpected status (not 401/404)

@routes.each do |r|
  url = "#{@uri_prefix}#{concretize(r[:path])}"

  @test.clear_cookies
  status = fire(r[:method], url, @regular_session)
  @standard_offenders << "#{r[:method]} #{r[:path]} -> #{status}" unless [403, 404].include?(status)

  @test.clear_cookies
  status = fire(r[:method], url, nil)
  @anon_offenders << "#{r[:method]} #{r[:path]} -> #{status}" unless [401, 404].include?(status)
end

# Layer 1: router-level role gate present on every route line.
@layer1_offenders = @routes.reject do |r|
  r[:attrs].include?('role=colonel') && r[:attrs].include?('scope=internal')
end.map { |r| r[:line] }

# Layer 2: each referenced logic class enforces verify_one_of_roles!(colonel:
# true) in its raise_concerns. We resolve the ACTUAL `raise_concerns` method's
# source location (via reflection), so inheritance is handled correctly — e.g.
# VerifyUser/UnverifyUser inherit the guard from SetUserVerificationBase, and a
# filename guess would give a false failure. Then we read just that method body
# (from its `def` line to the matching `end` at the same indentation) and require
# the colonel guard inside it.
def raise_concerns_body(klass)
  meth = klass.instance_method(:raise_concerns)
  file, line = meth.source_location
  return nil unless file && line

  lines  = File.readlines(file)
  start  = line - 1
  indent = lines[start][/\A\s*/]
  body   = lines[start].dup
  lines[(start + 1)..].each do |l|
    body << l
    break if l =~ /\A#{Regexp.escape(indent)}end\b/
  end
  body
end

@layer2_offenders = []
@routes.map { |r| r[:logic] }.uniq.each do |klass_name|
  klass =
    begin
      Object.const_get(klass_name)
    rescue NameError
      @layer2_offenders << "#{klass_name} (class not loaded)"
      next
    end

  unless klass.instance_methods(true).include?(:raise_concerns) ||
         klass.private_instance_methods(true).include?(:raise_concerns)
    @layer2_offenders << "#{klass_name} (no raise_concerns)"
    next
  end

  body = raise_concerns_body(klass)
  unless body && body.match?(/verify_one_of_roles!\([^)]*colonel:\s*true/)
    @layer2_offenders << "#{klass_name} (raise_concerns missing verify_one_of_roles!(colonel: true))"
  end
end

# TRYOUTS

## Sanity: routes.txt yielded a non-trivial set of admin routes to probe
@routes.length > 30
#=> true

## Every /api/colonel route declares the router role gate (Layer 1: role=colonel scope=internal)
@layer1_offenders
#=> []

## Every colonel logic class enforces verify_one_of_roles!(colonel: true) (Layer 2)
@layer2_offenders
#=> []

## BFLA: a STANDARD (verified, non-colonel) user is denied (403/404) on EVERY admin route
@standard_offenders
#=> []

## A standard user cannot reach a single admin route successfully (no 2xx anywhere)
@standard_offenders.select { |o| o =~ /-> 2\d\d$/ }
#=> []

## Anonymous requests are rejected (401/404) on EVERY admin route
@anon_offenders
#=> []
