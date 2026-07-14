# try/unit/operations/fetch_domain_favicon_backoff_try.rb
#
# frozen_string_literal: true

# Backoff bookkeeping for Onetime::Operations::FetchDomainFavicon (#3780 Phase 3).
#
# Hermetic: a lightweight CustomDomain double + injected fetcher exercise the
# terminal recorders with NO Redis/network/encryption. OT.conf is stubbed to the
# jobs.favicon_backfill defaults so the curve (base_days=1, cap_days=30,
# max_attempts=6) is deterministic; the ivar is restored at the end so sibling
# tryouts sharing this process are unaffected.
#
# Proves: record_none_found increments favicon_fetch_attempts and schedules
# favicon_fetch_next_at at 1d, 2d, 4d, 8d, 16d, then permanently STOPS at the
# attempt cap (next_at left untouched); compute_next_favicon_fetch_at caps the
# per-attempt delay at cap_days; record_failure advances the same curve; and
# record_success clears the backoff. Persistence is asserted via save_fields
# (hermetic double records the field list) rather than a real reload, matching
# the sibling fetch_domain_favicon_try.rb pattern.

require_relative '../../support/test_helpers'
require_relative '../../../lib/onetime/operations/fetch_domain_favicon'

FetchOp = Onetime::Operations::FetchDomainFavicon
Safe    = Onetime::Http::SafeFetch
DAY_S   = 86_400

# Stub OT.conf (attr_reader :conf) with only the subtree the backoff helpers dig.
@orig_conf = OT.instance_variable_get(:@conf)
OT.instance_variable_set(:@conf, {
  'jobs' => {
    'favicon_backfill' => { 'base_days' => 1, 'cap_days' => 30, 'max_attempts' => 6 },
  },
})

# In-memory stand-in for the icon hashkey (only what the operation touches).
class BackoffIcon
  def initialize(seed = {})
    @h = {}
    seed.each { |k, v| @h[k.to_s] = v }
  end

  def [](field)
    @h[field.to_s]
  end

  def []=(field, val)
    @h[field.to_s] = val
  end

  def update(hsh)
    hsh.each { |k, v| @h[k.to_s] = v }
    self
  end

  def remove_field(field)
    @h.delete(field.to_s) ? 1 : 0
  end
end

# CustomDomain double exposing the backoff fields as accessors and recording the
# save_fields lists so tests can assert which fields were persisted.
class BackoffDomain
  attr_accessor :favicon_fetch_status, :favicon_fetched, :favicon_fetch_error,
                :favicon_fetch_completed_at, :favicon_fetch_started_at,
                :favicon_fetch_attempts, :favicon_fetch_next_at
  attr_reader :icon, :display_domain, :saved_fields

  def initialize(display_domain: 'a.test', icon: {})
    @display_domain = display_domain
    @icon           = BackoffIcon.new(icon)
    @saved_fields   = []
  end

  def save_fields(*fields, **_opts)
    @saved_fields.concat(fields)
    self
  end
end

# Never yields an icon -> drives record_none_found.
class NoIconFetcher
  def get_image(url)
    raise Safe::Error, "no icon at #{url}"
  end

  def get_html(_url)
    '<html><head></head></html>'
  end
end

# Raises a non-timeout error -> drives record_failure.
class BoomFetcher
  def get_image(_url)
    raise 'boom'
  end

  def get_html(_url)
    ''
  end
end

# Valid 16x16 PNG header (FastImage sniffs :png, size [16, 16]) -> record_success.
PNG16 = ("\x89PNG\r\n\x1a\n".b + "\x00\x00\x00\rIHDR".b +
         "\x00\x00\x00\x10\x00\x00\x00\x10\x08\x06\x00\x00\x00".b + "\x1f\xf3\xffa".b).freeze
class PngFetcher
  def get_image(url)
    Safe::Result.new(body: PNG16, content_type: 'image/png', final_url: url)
  end

  def get_html(_url)
    ''
  end
end

def run_none_found(dom)
  FetchOp.new(domain_id: 'd-backoff', custom_domain: dom, fetcher: NoIconFetcher.new).call
end

# Whole days between a scheduled next_at and the now captured just before the
# call. The operation adds K*86400 to Familia.now.to_i (>= t0), so integer
# division recovers exactly K despite sub-second drift.
def offset_days(next_at, t0)
  (next_at - t0) / DAY_S
end

## First none-found: attempts=1, next_at ~ now+1d, both backoff fields persisted
@dom = BackoffDomain.new
@t0  = Familia.now.to_i
run_none_found(@dom)
[@dom.favicon_fetch_attempts, offset_days(@dom.favicon_fetch_next_at, @t0),
 @dom.saved_fields.include?(:favicon_fetch_attempts),
 @dom.saved_fields.include?(:favicon_fetch_next_at)]
#=> [1, 1, true, true]

## Second none-found doubles the backoff to ~2d (attempts=2)
@t0 = Familia.now.to_i
run_none_found(@dom)
[@dom.favicon_fetch_attempts, offset_days(@dom.favicon_fetch_next_at, @t0)]
#=> [2, 2]

## The curve keeps doubling: attempts 3,4,5 => 4d, 8d, 16d
@offsets = (3..5).map do
  t0 = Familia.now.to_i
  run_none_found(@dom)
  offset_days(@dom.favicon_fetch_next_at, t0)
end
[@dom.favicon_fetch_attempts, @offsets]
#=> [5, [4, 8, 16]]

## Attempt 6 reaches the cap => permanent stop: attempts advances, next_at frozen
@frozen_next_at = @dom.favicon_fetch_next_at
run_none_found(@dom)
[@dom.favicon_fetch_attempts, @dom.favicon_fetch_next_at == @frozen_next_at]
#=> [6, true]

## compute_next_favicon_fetch_at caps the per-attempt delay at cap_days (30d)
@t0     = Familia.now.to_i
@capped = FetchOp.new(domain_id: 'x').send(:compute_next_favicon_fetch_at, 9)
offset_days(@capped, @t0)
#=> 30

## record_failure advances the same curve and persists the backoff fields
@fail = BackoffDomain.new
@t0   = Familia.now.to_i
begin
  FetchOp.new(domain_id: 'd-fail', custom_domain: @fail, fetcher: BoomFetcher.new).call
rescue StandardError
  :raised
end
[@fail.favicon_fetch_status, @fail.favicon_fetch_attempts,
 offset_days(@fail.favicon_fetch_next_at, @t0),
 @fail.saved_fields.include?(:favicon_fetch_next_at)]
#=> ['failed', 1, 1, true]

## record_success clears the backoff (attempts=0, next_at=nil) and persists both
@ok = BackoffDomain.new
@ok.favicon_fetch_attempts = 4
@ok.favicon_fetch_next_at  = Familia.now.to_i + 99 * DAY_S
FetchOp.new(domain_id: 'd-ok', custom_domain: @ok, fetcher: PngFetcher.new).call
[@ok.favicon_fetch_attempts, @ok.favicon_fetch_next_at,
 @ok.saved_fields.include?(:favicon_fetch_attempts),
 @ok.saved_fields.include?(:favicon_fetch_next_at)]
#=> [0, nil, true, true]

## Restore the process-global OT.conf for sibling tryouts
OT.instance_variable_set(:@conf, @orig_conf)
OT.instance_variable_get(:@conf).equal?(@orig_conf)
#=> true
