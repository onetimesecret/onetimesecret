# try/integration/api/colonel/customer_admin_extid_try.rb
#
# frozen_string_literal: true

# Integration tests that exercise the colonel customer-admin endpoints by the
# customer's PUBLIC id (extid) — the identifier the users LIST actually exposes
# (list_users.rb sets `user_id: cust.extid`) and the ONLY identifier the admin
# UI ever has to route with (AdminCustomers.vue -> AdminCustomerDetail.vue).
#
#   GET    /api/colonel/users/:extid            (GetUserDetails)
#   POST   /api/colonel/users/:extid/role       { role: '...' }
#   POST   /api/colonel/users/:extid/verify
#   POST   /api/colonel/users/:extid/unverify
#   DELETE /api/colonel/users/:extid            (PurgeUser)
#
# WHY THIS EXISTS (epic #20 / ticket #22 exit gate): the sibling
# `customer_admin_try.rb` routes every call by `cust.objid`, so it passes even
# when the endpoints resolve only the internal objid. But the front end never
# sees an objid — it keys entirely off extid — so an objid-only resolver makes
# the whole "support without SSH" feature 404 in production while unit/component
# tests (which mock $api) stay green. This spec closes that gap: it fails with
# HTTP 404 unless the endpoints resolve the extid (via
# Customer.load_by_extid_or_email, matching Auth::Operations::Customers::Show).
#
# Run: try --agent try/integration/api/colonel/customer_admin_extid_try.rb

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
def post(*args);   @test.post(*args);   end
def get(*args);    @test.get(*args);    end
def delete(*args); @test.delete(*args); end
def last_response; @test.last_response; end

@ts = Familia.now.to_i

# Colonel actor (verified + role=colonel so session auth grants the role)
@colonel = Onetime::Customer.create!(email: "colonel_ext_#{@ts}@example.com")
@colonel.role     = 'colonel'
@colonel.verified = 'true'
@colonel.save

# Targets — captured by their PUBLIC id (extid), never objid.
@detail_target = Onetime::Customer.create!(email: "detail_ext_#{@ts}@example.com")
@detail_extid  = @detail_target.extid

@role_target   = Onetime::Customer.create!(email: "role_ext_#{@ts}@example.com")
@role_extid    = @role_target.extid
@role_objid    = @role_target.objid

@verify_target = Onetime::Customer.create!(email: "verify_ext_#{@ts}@example.com")
@verify_target.verified = 'false'
@verify_target.save
@verify_extid  = @verify_target.extid
@verify_objid  = @verify_target.objid

@purge_target  = Onetime::Customer.create!(email: "purge_ext_#{@ts}@example.com")
@purge_extid   = @purge_target.extid
@purge_objid   = @purge_target.objid

@colonel_session = { 'authenticated' => true, 'external_id' => @colonel.extid, 'email' => @colonel.email }
@colonel_headers = { 'rack.session' => @colonel_session, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
@colonel_get_headers = { 'rack.session' => @colonel_session, 'HTTP_ACCEPT' => 'application/json' }

# ---- Sanity: the extid is NOT the objid --------------------------------

## An extid and an objid are distinct identifiers (guards against a future
## refactor that accidentally makes them equal and hides the resolution bug).
@detail_extid == @detail_target.objid
#=> false

# ---- GET detail by extid ------------------------------------------------

## GET /users/:extid resolves the customer (200, not 404) and echoes the extid
get "/api/colonel/users/#{@detail_extid}", {}, @colonel_get_headers
@detail_resp = JSON.parse(last_response.body)
[last_response.status, @detail_resp['record']['extid']]
#=> [200, @detail_extid]

## The detail payload carries the support-view sections keyed by extid
[@detail_resp['details']['secrets']['count'], @detail_resp['details']['receipts'].is_a?(Hash)]
#=> [0, true]

# ---- Role change by extid -----------------------------------------------

## POST /users/:extid/role resolves by extid and applies the change (200)
post "/api/colonel/users/#{@role_extid}/role", { role: 'admin' }.to_json, @colonel_headers
@role_resp = JSON.parse(last_response.body)
[last_response.status, @role_resp['record']['new_role'], @role_resp['record']['old_role']]
#=> [200, "admin", "customer"]

## The role change actually persisted (resolution hit the right record)
Onetime::Customer.load(@role_objid).role
#=> "admin"

# ---- Verify / unverify by extid -----------------------------------------

## POST /users/:extid/verify resolves by extid and marks verified (200)
post "/api/colonel/users/#{@verify_extid}/verify", {}.to_json, @colonel_headers
[last_response.status, Onetime::Customer.load(@verify_objid).verified?]
#=> [200, true]

## POST /users/:extid/unverify resolves by extid and clears verified (200)
post "/api/colonel/users/#{@verify_extid}/unverify", {}.to_json, @colonel_headers
[last_response.status, Onetime::Customer.load(@verify_objid).verified?]
#=> [200, false]

# ---- Purge by extid -----------------------------------------------------

## DELETE /users/:extid resolves by extid, destroys the record (200)
delete "/api/colonel/users/#{@purge_extid}", {}, @colonel_get_headers
@purge_resp = JSON.parse(last_response.body)
[last_response.status, @purge_resp['record']['deleted'], Onetime::Customer.load(@purge_objid).nil?]
#=> [200, true, true]

# ---- 404 still holds for a genuinely unknown identifier -----------------

## An identifier that is neither a live extid nor objid still 404s
get "/api/colonel/users/urnotarealextid#{@ts}", {}, @colonel_get_headers
last_response.status
#=> 404

# ---- Teardown -----------------------------------------------------------
@colonel.destroy!       rescue nil
@detail_target.destroy! rescue nil
@role_target.destroy!   rescue nil
@verify_target.destroy! rescue nil
