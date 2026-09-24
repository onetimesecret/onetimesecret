# try/integration/api/colonel/list_organizations_search_try.rb
#
# frozen_string_literal: true

# Integration tests for the BOUNDED search/filter paths on the colonel
# organizations LIST:
#
#   GET /api/colonel/organizations?search=…&status=…&sync_status=…
#
# The previous implementation loaded the whole fleet (plus one owner load per
# org) behind a size-capped cache that never engaged in production, so every
# search request replayed the full walk. These tests pin the replacement:
# exact-id lookups, the contact-email and owner-email index scans, the
# newest-first window for display_name, the filters, the `capped` flag and
# the absence of any roster cache key.
#
# Run: try --agent try/integration/api/colonel/list_organizations_search_try.rb

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
def last_response; @test.last_response; end

# ----------------------------------------------------------------
# Test data setup
# ----------------------------------------------------------------

@timestamp = Familia.now.to_i

@colonel = Onetime::Customer.create!(email: "colonel_los_#{@timestamp}@example.com")
@colonel.role     = 'colonel'
@colonel.verified = 'true'
@colonel.save

@owner = Onetime::Customer.create!(email: "owner_los_#{@timestamp}@example.com")
@owner.verified = 'true'
@owner.save

# Free plan, no subscription -> compute_sync_status == 'synced'
@synced_org = Onetime::Organization.create!(
  "Synced Org #{@timestamp}", @owner, "synced_los_#{@timestamp}@example.com"
)
@synced_org.planid = 'free_v1'
@synced_org.save

# Paid plan with no active subscription -> 'potentially_stale'
@stale_org = Onetime::Organization.create!(
  "Stale Org #{@timestamp}", @owner, "Stale_LOS_#{@timestamp}@Example.com"
)
@stale_org.planid              = 'identity_plus_v1'
@stale_org.subscription_status = 'canceled'
@stale_org.save

@colonel_session = {
  'authenticated' => true,
  'external_id'   => @colonel.extid,
  'email'         => @colonel.email,
}

def colonel_headers
  { 'rack.session' => @colonel_session, 'HTTP_ACCEPT' => 'application/json' }
end

def details_for(params = {})
  get '/api/colonel/organizations', params, colonel_headers
  JSON.parse(last_response.body)['details']
end

def extids_for(params = {})
  details_for(params)['organizations'].map { |r| r['extid'] }
end

# ----------------------------------------------------------------
# Search paths
# ----------------------------------------------------------------

## Exact extid search resolves exactly one row
@found = details_for('search' => @synced_org.extid)
[last_response.status, @found['organizations'].size, @found['organizations'].first['extid']]
#=> [200, 1, @synced_org.extid]

## Exact objid search resolves the same row
extids_for('search' => @synced_org.objid)
#=> [@synced_org.extid]

## Contact-email substring resolves through the contact_email index
extids_for('search' => "synced_los_#{@timestamp}").include?(@synced_org.extid)
#=> true

## Contact-email search is case-insensitive even though the index keeps case
extids_for('search' => "stale_los_#{@timestamp}@example.com")
#=> [@stale_org.extid]

## Owner-email search resolves every org that customer OWNS
extids_for('search' => "owner_los_#{@timestamp}@example.com").sort ==
  [@stale_org.extid, @synced_org.extid].sort
#=> true

## Display-name search matches within the newest-first window
extids_for('search' => "stale org #{@timestamp}")
#=> [@stale_org.extid]

## Filtered rows are ordered created-descending
@created = details_for('search' => "los_#{@timestamp}")['organizations'].map { |r| r['created'] }
[@created.size >= 2, @created == @created.sort.reverse]
#=> [true, true]

## Rows carry the hydrated owner email (page-only hydration still fills it)
details_for('search' => @synced_org.extid)['organizations'].first['owner_email']
#=> @owner.email

## A no-match term returns an empty page, not an error
@none = details_for('search' => "nobody_los_#{@timestamp}_zzz")
[last_response.status, @none['organizations'], @none['pagination']['total_count']]
#=> [200, [], 0]

## Glob metacharacters in the term are escaped, not interpreted
extids_for('search' => "*_los_#{@timestamp}*")
#=> []

# ----------------------------------------------------------------
# Filters
# ----------------------------------------------------------------

## sync_status filter selects only the stale org among ours
@stale = extids_for('sync_status' => 'potentially_stale', 'search' => "los_#{@timestamp}")
[@stale.include?(@stale_org.extid), @stale.include?(@synced_org.extid)]
#=> [true, false]

## status filter composes with search
extids_for('status' => 'canceled', 'search' => "los_#{@timestamp}")
#=> [@stale_org.extid]

## Pagination reflects the FILTERED count
details_for('search' => @synced_org.extid)['pagination']['total_count']
#=> 1

# ----------------------------------------------------------------
# Bounds + envelope
# ----------------------------------------------------------------

## The test population fits the window, so nothing is capped
@pg = details_for('search' => "los_#{@timestamp}")['pagination']
[@pg.key?('capped'), @pg['capped']]
#=> [true, false]

## The envelope carries the filter echo and no roster-cache block
@d = details_for('search' => "los_#{@timestamp}")
[@d.key?('cache'), @d['filters']['search']]
#=> [false, "los_#{@timestamp}"]

## No roster cache key is written by a filtered read
Familia.dbclient.keys('colonel:organizations:list:*')
#=> []

## The legacy refresh param is still accepted
get '/api/colonel/organizations', { 'search' => @synced_org.extid, 'refresh' => '1' }, colonel_headers
last_response.status
#=> 200

## A mutation is visible on the very next read (nothing is cached)
@synced_org.display_name = "Renamed Org #{@timestamp}"
@synced_org.save
details_for('search' => @synced_org.extid)['organizations'].first['display_name']
#=> "Renamed Org #{@timestamp}"

## Anonymous still gets 401
@test.clear_cookies
get '/api/colonel/organizations', { 'search' => 'x' }, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 401

# ----------------------------------------------------------------
# Teardown
# ----------------------------------------------------------------
@synced_org.destroy! rescue nil
@stale_org.destroy!  rescue nil
@owner.destroy!      rescue nil
@colonel.destroy!    rescue nil
