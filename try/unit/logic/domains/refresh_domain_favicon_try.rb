# try/unit/logic/domains/refresh_domain_favicon_try.rb
#
# frozen_string_literal: true

# Tests for RefreshDomainFavicon logic class + Publisher force threading (#3780).
#
# RefreshDomainFavicon is the write-path manual "refresh favicon from domain"
# endpoint. It mirrors RemoveDomainImage: includes DomainConfigAuthorization,
# requires the custom_branding entitlement, and (when jobs.favicon_fetch is
# enabled) enqueues a force: true fetch for @custom_domain.identifier.
#
# Hermetic: FetchDomainFavicon.new is stubbed with an in-memory probe so no
# real DNS/HTTP/Redis fetch runs. In :test, jobs are disabled ($rmq_channel_pool
# is nil), so the real Publisher takes its inline-fallback branch — which lets
# the same stub prove both the logic-class path AND the Publisher force
# threading end-to-end.
#
# Covers:
#   1. Valid entitled owner -> greenlit; process drives the inline fetch with
#      {domain_id: identifier, force: true} and returns the queued success_data
#   2. Feature flag OFF -> process does NOT fetch but still returns success_data
#   3. Bad extid format -> FormError 'Invalid domain identifier format'
#   4. Empty extid -> FormError 'Domain ID is required'
#   5. Missing custom_branding entitlement -> FormError (forbidden)
#   6. Cross-org actor (not a member) -> Onetime::Forbidden
#   7. jobs disabled -> Publisher threads force:true into the inline fetch
#   8. jobs enabled -> Publisher threads force:true into the published message
#   9. Backward-compatible -> omitting force publishes force:false
#
# Run:
#   bundle exec try --agent try/unit/logic/domains/refresh_domain_favicon_try.rb

require_relative '../../../support/test_helpers'
require_relative '../../../support/test_logic'
require 'securerandom'

OT.boot! :test

# Load DomainsAPI logic classes + the operation/publisher under test
require 'api/domains/logic/base'
require 'api/domains/logic/domains/refresh_domain_favicon'
require 'onetime/jobs/publisher'
require 'onetime/operations/fetch_domain_favicon'

Familia.dbclient.flushdb
OT.info 'Cleaned Redis for RefreshDomainFavicon test run'

@ts      = Familia.now.to_i
@entropy = SecureRandom.hex(4)

# --- Entitled owner fixtures (billing disabled -> standalone custom_branding) ---
@owner  = Onetime::Customer.create!(email: "favrefresh_owner_#{@ts}_#{@entropy}@test.com")
@org    = Onetime::Organization.create!("Fav Refresh Corp #{@ts}", @owner, "favrefresh_org_#{@ts}@test.com")
@org.define_singleton_method(:billing_enabled?) { false }
@domain = Onetime::CustomDomain.create!("fav-refresh-#{@ts}-#{@entropy}.example.com", @org.objid)
@extid  = @domain.extid

@strategy_result = MockStrategyResult.new(
  session: {},
  user: @owner,
  metadata: { organization_context: { organization: @org } },
)

def build_refresh(extid, strategy_result)
  DomainsAPI::Logic::Domains::RefreshDomainFavicon.new(strategy_result, { 'extid' => extid })
end

# --- Stub FetchDomainFavicon.new to record kwargs and skip the real fetch ---
# `fdf_calls` aliases @fdf_calls so appends inside the singleton block (self ==
# the operation class) are visible to the tests.
@fdf_calls = []
fdf_calls  = @fdf_calls
@fdf       = Onetime::Operations::FetchDomainFavicon
@fdf.define_singleton_method(:new) do |**kwargs|
  fdf_calls << kwargs
  probe = Object.new
  probe.define_singleton_method(:call) { nil }
  probe
end

# Force the favicon_fetch flag ON so process reaches the enqueue.
OT.conf['jobs'] ||= {}
OT.conf['jobs']['favicon_fetch'] ||= {}
@orig_flag = OT.conf['jobs']['favicon_fetch']['enabled']
OT.conf['jobs']['favicon_fetch']['enabled'] = true

## Setup verification — domain exists and is owned by the org
[@domain.exists?, @domain.owner?(@owner)]
#=> [true, true]

## Case 1a: valid entitled owner is greenlit
@logic_ok = build_refresh(@extid, @strategy_result)
@logic_ok.raise_concerns
@logic_ok.greenlighted
#=> true

## Case 1b: process drives the inline fetch with the identifier + force:true
# (jobs disabled -> Publisher inline branch -> FetchDomainFavicon.new)
@result_ok = @logic_ok.process
@fdf_calls.last
#=> { domain_id: @domain.identifier, force: true }

## Case 1c: process returns the queued success_data shape (record nil + msg)
[@result_ok[:record], @result_ok[:details][:msg]]
#=> [nil, "Favicon refresh queued for #{@domain.display_domain}"]

## Case 2: feature flag OFF -> no fetch; success_data reports "unavailable"
OT.conf['jobs']['favicon_fetch']['enabled'] = false
@count_before = @fdf_calls.size
@logic_off = build_refresh(@extid, @strategy_result)
@logic_off.raise_concerns
@off_result = @logic_off.process
[@fdf_calls.size - @count_before, @off_result[:details][:msg]]
#=> [0, 'Favicon refresh is unavailable right now']

# Re-enable the flag for the remaining cases (they raise before process anyway).
OT.conf['jobs']['favicon_fetch']['enabled'] = true

## Case 3: bad extid format -> FormError (sanitize keeps A-Za-z0-9_-, lowercase regex rejects)
@logic_bad = build_refresh('BAD-ID', @strategy_result)
begin
  @logic_bad.raise_concerns
  'unexpected_success'
rescue Onetime::FormError => ex
  ex.message
end
#=> 'Invalid domain identifier format'

## Case 4: empty extid -> FormError 'Domain ID is required'
@logic_empty = build_refresh('!!!', @strategy_result)
begin
  @logic_empty.raise_concerns
  'unexpected_success'
rescue Onetime::FormError => ex
  ex.message
end
#=> 'Domain ID is required'

## Case 5: missing custom_branding entitlement -> authorization denied
# Standalone orgs fail open on can?, so override Organization#can? to deny only
# custom_branding. manage_org is checked on the MEMBERSHIP (different class), so
# authorize_domain_config! reaches verify_config_entitlement and raises there.
@orig_can = Onetime::Organization.instance_method(:can?)
orig_can  = @orig_can
Onetime::Organization.send(:define_method, :can?) do |entitlement|
  entitlement.to_s == 'custom_branding' ? false : orig_can.bind(self).call(entitlement)
end
@logic_nb = build_refresh(@extid, @strategy_result)
@nb_message =
  begin
    @logic_nb.raise_concerns
    'unexpected_success'
  rescue Onetime::FormError => ex
    ex.message
  end
Onetime::Organization.send(:define_method, :can?, @orig_can) # restore
@nb_message
#=> 'Custom branding requires the custom_branding entitlement. Please upgrade your plan.'

## Case 6: cross-org actor (not a member of the domain's org) -> Forbidden
@owner_x = Onetime::Customer.create!(email: "favrefresh_x_#{@ts}_#{@entropy}@test.com")
@org_x   = Onetime::Organization.create!("Fav X Corp #{@ts}", @owner_x, "favrefresh_x_org_#{@ts}@test.com")
@org_x.define_singleton_method(:billing_enabled?) { false }
@sr_x = MockStrategyResult.new(
  session: {},
  user: @owner_x,
  metadata: { organization_context: { organization: @org_x } },
)
@logic_cross = build_refresh(@extid, @sr_x)
begin
  @logic_cross.raise_concerns
  'unexpected_success'
rescue Onetime::Forbidden => ex
  ex.is_a?(Onetime::Forbidden)
end
#=> true

## Case 7: jobs disabled -> Publisher threads force:true into the inline fetch
@count7 = @fdf_calls.size
Onetime::Jobs::Publisher.enqueue_favicon_fetch('domforce123', force: true)
[@fdf_calls.size - @count7, @fdf_calls.last]
#=> [1, { domain_id: 'domforce123', force: true }]

## Case 8: jobs enabled -> Publisher includes force:true in the published message hash
@pub          = Onetime::Jobs::Publisher.new
@msg_captured = {}
msg_cap       = @msg_captured
@pub.define_singleton_method(:jobs_enabled?) { true }
@pub.define_singleton_method(:publish) do |queue, payload, **_opts|
  msg_cap[:queue]   = queue
  msg_cap[:payload] = payload
  'msg-id-xyz'
end
@pub.enqueue_favicon_fetch('domforce456', force: true)
[@msg_captured[:queue], @msg_captured[:payload][:domain_id], @msg_captured[:payload][:force]]
#=> ['domain.favicon.fetch', 'domforce456', true]

## Case 9: backward-compatible — omitting force publishes force:false
@pub2   = Onetime::Jobs::Publisher.new
@msg2   = {}
msg2cap = @msg2
@pub2.define_singleton_method(:jobs_enabled?) { true }
@pub2.define_singleton_method(:publish) do |_queue, payload, **_opts|
  msg2cap[:payload] = payload
  'mid'
end
@pub2.enqueue_favicon_fetch('domdefault')
@msg2[:payload][:force]
#=> false

## Case 10: an inline enqueue failure must NOT escape process as a 500 (#3782
## review). Swap the stub to raise; RefreshDomainFavicon#process rescues it and
## returns success_data reporting "unavailable" rather than propagating the error.
# (flag is still ON from Case 2's re-enable; run last so the raising stub can't
# leak into the force-threading cases above.)
@fdf.define_singleton_method(:new) do |**_kwargs|
  probe = Object.new
  probe.define_singleton_method(:call) { raise Onetime::Http::SafeFetch::FetchTimeout, 'inline timeout' }
  probe
end
@logic_raise  = build_refresh(@extid, @strategy_result)
@logic_raise.raise_concerns
@raise_result = @logic_raise.process
[@raise_result[:record], @raise_result[:details][:msg]]
#=> [nil, 'Favicon refresh is unavailable right now']

# --- Cleanup ---
@fdf.singleton_class.send(:remove_method, :new) # restore inherited Class#new
OT.conf['jobs']['favicon_fetch']['enabled'] = @orig_flag
@domain.destroy! if @domain&.exists?
@org_x.destroy! if @org_x&.exists?
@org.destroy! if @org&.exists?
@owner_x.destroy! if @owner_x&.exists?
@owner.destroy! if @owner&.exists?
Familia.dbclient.flushdb
OT.info 'Cleaned Redis after RefreshDomainFavicon test run'
