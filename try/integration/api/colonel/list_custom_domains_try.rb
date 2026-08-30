# try/integration/api/colonel/list_custom_domains_try.rb
#
# frozen_string_literal: true

# Integration tests for the index-backed colonel domains LIST:
#
#   GET /api/colonel/domains
#
# The endpoint used to load EVERY CustomDomain (load_multi of the whole
# instances set) on every request — including each debounced keystroke of the
# admin search box — which is the load pattern that pinned the web workers.
# It now reads only bounded sets per path (epic #20 / #2211):
#
# - unfiltered: one ZREVRANGE page off CustomDomain.instances
# - search:     bounded HSCAN over display_domain_index + exact extid/objid
# - org_id:     the org's own domains participation set
# - status:     a bounded newest-first window with a `capped` signal
#
# Covers:
# - unfiltered pagination envelope (total_count off ZCARD, capped false)
# - search: substring over display_domain, exact extid, exact objid (domain_id)
# - status + org_id filters (org by extid AND by objid), composition with search
# - filters echo
# - GET /domains/:extid resolves by objid too (DomainResolver)
#
# Run: try --agent try/integration/api/colonel/list_custom_domains_try.rb

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

@colonel = Onetime::Customer.create!(email: "colonel_lcd_#{@timestamp}@example.com")
@colonel.role     = 'colonel'
@colonel.verified = 'true'
@colonel.save

@owner = Onetime::Customer.create!(email: "owner_lcd_#{@timestamp}@example.com")
@owner.verified = 'true'
@owner.save

@org_a = Onetime::Organization.create!(
  "Domains Org A #{@timestamp}", @owner, "orga_lcd_#{@timestamp}@example.com"
)
@org_b = Onetime::Organization.create!(
  "Domains Org B #{@timestamp}", @owner, "orgb_lcd_#{@timestamp}@example.com"
)

# Distinctive FQDNs so substring search can isolate exactly these rows.
@fqdn_a1 = "alpha-lcd-#{@timestamp}.example.com"
@fqdn_a2 = "beta-lcd-#{@timestamp}.example.com"
@fqdn_b1 = "gamma-lcd-#{@timestamp}.example.org"

@domain_a1 = Onetime::CustomDomain.create!(@fqdn_a1, @org_a.objid)
@domain_a2 = Onetime::CustomDomain.create!(@fqdn_a2, @org_a.objid)
@domain_b1 = Onetime::CustomDomain.create!(@fqdn_b1, @org_b.objid)

@colonel_session = {
  'authenticated' => true,
  'external_id'   => @colonel.extid,
  'email'         => @colonel.email,
}

def colonel_headers
  { 'rack.session' => @colonel_session, 'HTTP_ACCEPT' => 'application/json' }
end

def list(params = {})
  get '/api/colonel/domains', params, colonel_headers
  JSON.parse(last_response.body)['details']
end

def listed_fqdns(params = {})
  list(params)['domains'].map { |d| d['display_domain'] }
end

# ----------------------------------------------------------------
# Unfiltered: index-backed page
# ----------------------------------------------------------------

## Unfiltered read returns 200 with the pagination envelope off the index
@details    = list
@pagination = @details['pagination']
[
  last_response.status,
  @pagination['page'],
  @pagination['capped'],
  @pagination['total_count'] >= 3,
  @details['domains'].size <= @pagination['per_page'],
]
#=> [200, 1, false, true, true]

## Unfiltered total_count matches the instances registry cardinality (ZCARD)
list['pagination']['total_count'] == Onetime::CustomDomain.instances.count
#=> true

## The three seeded domains are all present on page one (newest-first order)
@page_fqdns = listed_fqdns('per_page' => 100)
[@fqdn_a1, @fqdn_a2, @fqdn_b1].all? { |fqdn| @page_fqdns.include?(fqdn) }
#=> true

## per_page=1 returns exactly one row and echoes the clamp
@details_one = list('per_page' => 1)
[@details_one['domains'].size, @details_one['pagination']['per_page']]
#=> [1, 1]

## per_page=0 clamps to the default instead of revrange(0, -1) — the whole
## set — and a ZeroDivisionError-shaped total_pages
@details_zero = list('per_page' => 0)
[last_response.status, @details_zero['pagination']['per_page']]
#=> [200, 50]

## A negative per_page clamps the same way (revrange(0, -2) would silently
## return all-but-one of the population)
@details_neg = list('per_page' => -1)
[last_response.status, @details_neg['pagination']['per_page']]
#=> [200, 50]

# ----------------------------------------------------------------
# Search: bounded HSCAN + exact identifier arms
# ----------------------------------------------------------------

## Substring search over display_domain isolates the one matching row
listed_fqdns('search' => "alpha-lcd-#{@timestamp}")
#=> [@fqdn_a1]

## Search matches are counted post-filter (total_count reflects the filtered set)
list('search' => "-lcd-#{@timestamp}")['pagination']['total_count']
#=> 3

## Search is case-insensitive (the index stores lowercased FQDNs)
listed_fqdns('search' => "ALPHA-LCD-#{@timestamp}")
#=> [@fqdn_a1]

## Exact extid search finds the domain (identifier arm, not the HSCAN)
listed_fqdns('search' => @domain_a2.extid)
#=> [@fqdn_a2]

## Exact objid (domain_id) search finds the domain
listed_fqdns('search' => @domain_a2.domainid)
#=> [@fqdn_a2]

## A no-match term returns an empty page, not an error
@no_match = list('search' => "zzz-no-such-domain-#{@timestamp}")
[last_response.status, @no_match['domains'], @no_match['pagination']['total_count']]
#=> [200, [], 0]

# ----------------------------------------------------------------
# Status + org filters
# ----------------------------------------------------------------

## Fresh domains are 'pending'; the status filter finds them (bounded window)
@pending = list('status' => 'pending', 'per_page' => 100)
[@fqdn_a1, @fqdn_a2, @fqdn_b1].all? do |fqdn|
  @pending['domains'].any? { |d| d['display_domain'] == fqdn }
end
#=> true

## A status matching nothing returns an empty set
list('status' => 'verified', 'search' => "-lcd-#{@timestamp}")['domains']
#=> []

## org_id filter by org EXTID returns only that org's domains
listed_fqdns('org_id' => @org_a.extid, 'per_page' => 100).sort
#=> [@fqdn_a1, @fqdn_a2].sort

## org_id filter by org OBJID returns the same set
listed_fqdns('org_id' => @org_a.objid, 'per_page' => 100).sort
#=> [@fqdn_a1, @fqdn_a2].sort

## DRIFT: a domain whose org_id points at the org but which is MISSING from
## the org's domains participation set (create!'s set-add is conditional on
## the org loading; doctor models the state as repairable) is still listed
## by the org filter, via the bounded owners-index union
@domain_a1.remove_from_organization_domains(@org_a)
listed_fqdns('org_id' => @org_a.extid, 'per_page' => 100).include?(@fqdn_a1)
#=> true

## ...and the org-only filter agrees with the org+search composition on the
## drifted domain (the two candidate sources must not disagree on membership)
listed_fqdns('org_id' => @org_a.extid, 'search' => @fqdn_a1).include?(@fqdn_a1)
#=> true

## Restore the participation for the remaining cases
@domain_a1.add_to_organization_domains(@org_a)
listed_fqdns('org_id' => @org_a.extid, 'per_page' => 100).sort ==
  [@fqdn_a1, @fqdn_a2].sort
#=> true

## org filter composes with search
listed_fqdns('org_id' => @org_a.extid, 'search' => 'beta-lcd')
#=> [@fqdn_a2]

## The applied filters are echoed back
list('search' => 'alpha', 'status' => 'pending', 'org_id' => @org_a.extid)['filters']
#=> { 'search' => 'alpha', 'status' => 'pending', 'org_id' => @org_a.extid }

# ----------------------------------------------------------------
# Detail resolution (DomainResolver: extid OR objid)
# ----------------------------------------------------------------

## GET /domains/:extid still resolves by extid
get "/api/colonel/domains/#{@domain_a1.extid}", {}, colonel_headers
[last_response.status, JSON.parse(last_response.body)['record']['domain_id']]
#=> [200, @domain_a1.domainid]

## GET /domains/:id now ALSO resolves by internal objid (domain_id)
get "/api/colonel/domains/#{@domain_a1.domainid}", {}, colonel_headers
[last_response.status, JSON.parse(last_response.body)['record']['extid']]
#=> [200, @domain_a1.extid]

## An unknown identifier still 404s
get "/api/colonel/domains/cd_does_not_exist_#{@timestamp}", {}, colonel_headers
last_response.status
#=> 404

# ----------------------------------------------------------------
# Teardown
# ----------------------------------------------------------------

[@domain_a1, @domain_a2, @domain_b1].each do |domain|
  domain.destroy!
rescue StandardError
  nil
end
[@org_a, @org_b].each do |org|
  org.destroy!
rescue StandardError
  nil
end
[@colonel, @owner].each do |cust|
  cust.destroy!
rescue StandardError
  nil
end
