# try/integration/api/colonel/last_colonel_interlock_try.rb
#
# frozen_string_literal: true

# Self-target and last-colonel interlocks (#4328) over a REAL Rack stack and a
# REAL role index. The unit specs prove each guard in isolation; this proves the
# guards are actually WIRED — including the ordering that keeps them from being
# an information oracle.
#
# ## What is reachable over HTTP, and what is not
#
# `verify_one_of_roles!` routes through `has_system_role?`, which requires
# `verified? && role == 'colonel'`. So the ACTING colonel is, by construction,
# always a member of `RoleSupport.active_colonels`. That makes the LAST-COLONEL
# refusals unreachable over HTTP for a target that is not the caller — there are
# always at least two active colonels in that scenario — and it is the
# SELF-target arm that fires when an install's only colonel tries to strip their
# own powers. The last-colonel arm is the CLI's (`bin/ots customers role demote`,
# covered in spec/cli/customers_command_role_spec.rb) and the op-level backstop.
# That asymmetry is the whole reason both arms exist; asserting it here keeps a
# future refactor from "simplifying" one of them away.
#
# Covers:
# - demoting your own colonel account          -> 422, field user_id, role unchanged
# - promoting yourself is still allowed        -> 200 (only demotion is a lockout)
# - unverifying your own account               -> 422, field user_id, still verified
# - both 422s are reachable ONLY after the confirmation gate (M-2 oracle guard):
#   with no X-OTS-Confirm header the answer is 403 confirmation_required
# - a SECOND colonel can be promoted and verified, and colonel A can then demote
#   and unverify colonel B normally
# - revoking your OWN session through the global console -> 422 (sign out instead)
# - revoke-all against your OWN account -> 200, and the session you are working
#   in survives (the containment path, deliberately NOT refused)
#
# Run: try --agent try/integration/api/colonel/last_colonel_interlock_try.rb

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

def get(*args);    @test.get(*args);              end
def post(*args);   @test.post(*with_csrf(args));  end
def delete(*args); @test.delete(*with_csrf(args)); end
def last_response; @test.last_response; end
def body; JSON.parse(last_response.body); end

@timestamp = Familia.now.to_i

@colonel = Onetime::Customer.create!(email: "colonel_lci_#{@timestamp}@example.com")
@colonel.role     = 'colonel'
@colonel.verified = 'true'
@colonel.save

@second = Onetime::Customer.create!(email: "second_lci_#{@timestamp}@example.com")
@second.verified = 'true'
@second.save

@colonel_session = {
  'authenticated' => true,
  'external_id'   => @colonel.extid,
  'email'         => @colonel.email,
}

# `confirm` is the percent-encoded token, exactly as the console sends it.
def colonel_headers(confirm = nil)
  headers = { 'rack.session' => @colonel_session, 'HTTP_ACCEPT' => 'application/json' }
  headers['HTTP_X_OTS_CONFIRM'] = confirm if confirm
  headers
end

def confirming(customer)
  colonel_headers(Rack::Utils.escape(customer.email))
end

@self_role_url     = "/api/colonel/users/#{@colonel.extid}/role"
@self_unverify_url = "/api/colonel/users/#{@colonel.extid}/unverify"

## Demoting your own colonel account is refused, naming the field to highlight
post @self_role_url, { 'role' => 'customer' }, confirming(@colonel)
[last_response.status, body['field']]
#=> [422, "user_id"]

## ...and the refusal names the CLI remediation, because nobody else can do it
body['error'].include?('bin/ots customers role demote')
#=> true

## ...and the role really is unchanged
Onetime::Customer.load(@colonel.objid).role.to_s
#=> "colonel"

## M-2: with NO confirmation header the answer is the 403, never the 422 —
## the interlock must not tell a cookie holder whether an account is their own
post @self_role_url, { 'role' => 'customer' }, colonel_headers
[last_response.status, body['error_code']]
#=> [403, "confirmation_required"]

## Unverifying your own account is refused too (it strips colonel eligibility)
post @self_unverify_url, {}, confirming(@colonel)
[last_response.status, body['field']]
#=> [422, "user_id"]

## ...and the account is still verified
Onetime::Customer.load(@colonel.objid).verified?
#=> true

## M-2 again on the unverify arm
post @self_unverify_url, {}, colonel_headers
[last_response.status, body['error_code']]
#=> [403, "confirmation_required"]

## Promoting YOURSELF is not a lockout, so it is still allowed
post @self_role_url, { 'role' => 'colonel' }, confirming(@colonel)
[last_response.status, body['details']['changed']]
#=> [200, false]

## An EMAIL identifier now resolves (sanitize_identifier used to strip @ and .)
post "/api/colonel/users/#{Rack::Utils.escape(@second.email)}/role",
  { 'role' => 'colonel' }, confirming(@second)
[last_response.status, Onetime::Customer.load(@second.objid).role.to_s]
#=> [200, "colonel"]

## With a second verified colonel in place, colonel A can unverify colonel B
post "/api/colonel/users/#{@second.extid}/unverify", {}, confirming(@second)
[last_response.status, Onetime::Customer.load(@second.objid).verified?]
#=> [200, false]

## ...and re-verify, then demote them, both normally
post "/api/colonel/users/#{@second.extid}/verify", {}, colonel_headers
last_response.status
#=> 200

## Demoting the OTHER colonel succeeds — only the caller's own account is barred
post "/api/colonel/users/#{@second.extid}/role", { 'role' => 'customer' }, confirming(@second)
[last_response.status, Onetime::Customer.load(@second.objid).role.to_s]
#=> [200, "customer"]

## The global sessions console names the caller's OWN row by handle
get '/api/colonel/sessions', {}, colonel_headers
@own_handle = body['details']['current_session_handle']
@own_handle.is_a?(String) && !@own_handle.empty?
#=> true

## Revoking that row is refused — sign out instead of self-revoking
delete "/api/colonel/sessions/#{@own_handle}", {}, confirming(@colonel)
[last_response.status, body['field']]
#=> [422, "session_handle"]

## ...and the caller is still authenticated afterwards
get '/api/colonel/sessions', {}, colonel_headers
last_response.status
#=> 200

## Revoke-all against your OWN account is SUPPORTED, not refused: it is the
## first containment step for a leaked colonel cookie
post "/api/colonel/users/#{@colonel.extid}/sessions/revoke-all", {}, confirming(@colonel)
[last_response.status, body['details']['message']]
#=> [200, "Revoked all of your other sessions; this one was kept."]

## ...and the session it was issued from still works
get '/api/colonel/sessions', {}, colonel_headers
last_response.status
#=> 200

## Revoke-all against an unknown identifier is now a 404, not a silent zero
post '/api/colonel/users/ur_does_not_exist_lci/sessions/revoke-all', {},
  colonel_headers(Rack::Utils.escape('nobody@example.com'))
last_response.status
#=> 404

# Teardown.
@second.destroy! if @second.exists?
@colonel.destroy! if @colonel.exists?
