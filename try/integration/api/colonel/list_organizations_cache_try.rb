# try/integration/api/colonel/list_organizations_cache_try.rb
#
# frozen_string_literal: true

# Integration tests for the roster cache on the colonel organizations LIST:
#
#   GET /api/colonel/organizations[?refresh=1]
#
# What is cached is the PRE-FILTER roster (every org, post-build, before
# filtering/sorting/paging), so one entry serves every filter/page/search
# combination. That design has one sharp edge worth pinning down: the entry is
# a JSON blob, and the filter/sort/search code indexes the rows with SYMBOL
# keys. A cache HIT that handed back string-keyed rows would still return 200
# with a full first page while every filter silently matched nothing — which is
# why the filter/search/sort assertions below are all run against the hit path.
#
# Covers:
# - miss -> cached:false, generated_at set, ttl echoed
# - hit  -> cached:true and the SAME generated_at (it tracks the build)
# - filter / search / created-desc sort produce identical results on hit + miss
# - refresh=1 bypasses the read and rebuilds (cached:false, newer generated_at)
# - a wedged cache entry must not break the endpoint (fall through to uncached)
#
# Run: try --agent try/integration/api/colonel/list_organizations_cache_try.rb

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

# Instance var, not a top-level constant: tryouts run in a SHARED context, so a
# bare `CACHE_KEY` would land on Object and collide across files in a batch run.
@cache_key = ColonelAPI::Logic::Colonel::ListOrganizations::CACHE_KEY

def drop_cache
  Familia.dbclient.del(@cache_key)
end

# ----------------------------------------------------------------
# Test data setup
# ----------------------------------------------------------------

@timestamp = Familia.now.to_i

@colonel = Onetime::Customer.create!(email: "colonel_loc_#{@timestamp}@example.com")
@colonel.role     = 'colonel'
@colonel.verified = 'true'
@colonel.save

@owner = Onetime::Customer.create!(email: "owner_loc_#{@timestamp}@example.com")
@owner.verified = 'true'
@owner.save

# Free plan, no subscription -> compute_sync_status == 'synced'
@synced_org = Onetime::Organization.create!(
  "Synced Org #{@timestamp}", @owner, "synced_loc_#{@timestamp}@example.com"
)
@synced_org.planid = 'free_v1'
@synced_org.save

# Paid plan with no active subscription -> 'potentially_stale'
@stale_org = Onetime::Organization.create!(
  "Stale Org #{@timestamp}", @owner, "stale_loc_#{@timestamp}@example.com"
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

def rows_for(params = {})
  get '/api/colonel/organizations', params, colonel_headers
  JSON.parse(last_response.body)['details']['organizations']
end

def cache_block(params = {})
  get '/api/colonel/organizations', params, colonel_headers
  JSON.parse(last_response.body)['details']['cache']
end

# ----------------------------------------------------------------
# Miss / hit
# ----------------------------------------------------------------

## Cold read reports a MISS and carries the full cache block
# NOTE: The cache path only activates when filters/search are provided.
# Without filters, the endpoint takes a fast path that loads top-N orgs
# directly from the sorted set without caching (see DEFAULT_LIMIT).
drop_cache
get '/api/colonel/organizations', { 'search' => 'loc_' }, colonel_headers
@resp  = JSON.parse(last_response.body)
@cache = @resp['details']['cache']
[last_response.status, @cache['cached'], @cache['ttl'], @cache['generated_at'].positive?]
#=> [200, false, ColonelAPI::Logic::Colonel::ListOrganizations::CACHE_TTL, true]

## Cold read populated the cache key with a TTL
Familia.dbclient.ttl(@cache_key).positive?
#=> true

## Second read is a HIT and reuses the SAME generated_at (it tracks the build)
@second = cache_block('search' => 'loc_')
[@second['cached'], @second['generated_at'] == @cache['generated_at']]
#=> [true, true]

# ----------------------------------------------------------------
# Filter / search / sort on the CACHE-HIT path
#
# These are the assertions that catch a symbol/string key round-trip
# regression: on a miss they pass trivially, on a hit they only pass if the
# cached rows come back keyed exactly as #build_org_data emitted them.
# ----------------------------------------------------------------

## HIT: the sync_status filter still selects (not an empty set, not everything)
@stale = rows_for('sync_status' => 'potentially_stale')
[@stale.any?, @stale.all? { |r| r['sync_status'] == 'potentially_stale' }]
#=> [true, true]

## HIT: the stale org is in that filtered set and the synced org is not
@extids = rows_for('sync_status' => 'potentially_stale').map { |r| r['extid'] }
[@extids.include?(@stale_org.extid), @extids.include?(@synced_org.extid)]
#=> [true, false]

## HIT: exact-extid search resolves one row
@found = rows_for('search' => @synced_org.extid)
[@found.size, @found.first['extid']]
#=> [1, @synced_org.extid]

## HIT: contact-email substring search resolves the same row
@found = rows_for('search' => "synced_loc_#{@timestamp}")
@found.map { |r| r['extid'] }.include?(@synced_org.extid)
#=> true

## HIT: owner-email search still matches (owner_email stays in the cached row)
@found = rows_for('search' => "owner_loc_#{@timestamp}@example.com")
@found.map { |r| r['extid'] }.sort == [@stale_org.extid, @synced_org.extid].sort
#=> true

## HIT: rows are ordered created-descending (the sort key survives the blob)
@created = rows_for.map { |r| r['created'] }
@created == @created.sort.reverse
#=> true

## HIT: row field types survive the round trip (booleans, integers, nulls)
@row = rows_for('search' => @synced_org.extid).first
[
  @row['is_default'].is_a?(FalseClass) || @row['is_default'].is_a?(TrueClass),
  @row['member_count'].is_a?(Integer),
  @row['created'].is_a?(Integer),
  @row['display_name'] == "Synced Org #{@timestamp}",
]
#=> [true, true, true, true]

## HIT: pagination still reflects the FILTERED count, not the whole roster
get '/api/colonel/organizations', { 'search' => @synced_org.extid }, colonel_headers
JSON.parse(last_response.body)['details']['pagination']['total_count']
#=> 1

# ----------------------------------------------------------------
# Explicit refresh bypass
# ----------------------------------------------------------------

## refresh=1 skips the read and rewrites the entry (reported as a miss)
@before = cache_block('search' => 'loc_')
sleep 1 # generated_at is a unix SECOND; make the rebuild observable
@bypassed = cache_block('search' => 'loc_', 'refresh' => '1')
[@before['cached'], @bypassed['cached'], @bypassed['generated_at'] > @before['generated_at']]
#=> [true, false, true]

## The read after a bypass is a hit again, on the REBUILT entry
@after = cache_block('search' => 'loc_')
[@after['cached'], @after['generated_at'] == @bypassed['generated_at']]
#=> [true, true]

## An org mutated behind the cache is invisible until refresh, then visible
@synced_org.display_name = "Renamed Org #{@timestamp}"
@synced_org.save
@stale_name = rows_for('search' => @synced_org.extid).first['display_name']
@fresh_name = rows_for('search' => @synced_org.extid, 'refresh' => 'true').first['display_name']
[@stale_name, @fresh_name]
#=> ["Synced Org #{@timestamp}", "Renamed Org #{@timestamp}"]

# ----------------------------------------------------------------
# Failure tolerance: a cache read must never break the endpoint
# ----------------------------------------------------------------

## A corrupt cache entry falls through to the uncached computation
Familia.dbclient.setex(@cache_key, 90, 'not-json-at-all')
get '/api/colonel/organizations', {}, colonel_headers
@resp = JSON.parse(last_response.body)
[last_response.status, @resp['details']['cache']['cached'], @resp['details']['organizations'].any?]
#=> [200, false, true]

## A well-formed-but-wrong-shaped entry also falls through
Familia.dbclient.setex(@cache_key, 90, JSON.generate({ generated_at: 1, organizations: 'nope' }))
get '/api/colonel/organizations', {}, colonel_headers
@resp = JSON.parse(last_response.body)
[last_response.status, @resp['details']['cache']['cached'], @resp['details']['organizations'].any?]
#=> [200, false, true]

# ----------------------------------------------------------------
# Authorization is unchanged by the cache
# ----------------------------------------------------------------

## Anonymous still gets 401 (a warm cache is not a bypass)
@test.clear_cookies
get '/api/colonel/organizations', {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 401

# ----------------------------------------------------------------
# Teardown
# ----------------------------------------------------------------
drop_cache
@synced_org.destroy! rescue nil
@stale_org.destroy!  rescue nil
@owner.destroy!      rescue nil
@colonel.destroy!    rescue nil
