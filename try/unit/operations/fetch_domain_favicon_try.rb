# try/unit/operations/fetch_domain_favicon_try.rb
#
# frozen_string_literal: true

# Unit coverage for Onetime::Operations::FetchDomainFavicon (#3780).
#
# Hermetic: SafeFetch (network) and CustomDomain (Redis) are both stubbed via
# lightweight in-memory doubles injected through the operation's `fetcher:` and
# `custom_domain:` seams, so NO real network, Redis, or encryption is touched.
# Requiring 'onetime' through the support helper is enough to define the model
# namespace, Familia.now, and the SafeFetch error hierarchy.
#
# Proves: direct /favicon.ico success writes the full icon shape + auto_fetch
# tag and drops the stale cache; HTML <link rel=icon> discovery fallback; the
# overwrite guard protects user_upload AND legacy untagged icons; no-favicon is
# COMPLETED-false (success, not FAILED); force re-fetches an existing auto_fetch
# icon; a transient FetchTimeout is re-raised (retriable) leaving PROCESSING; an
# unexpected error records FAILED and re-raises; a missing domain returns a
# permanent-miss Result without raising.

require_relative '../../support/test_helpers'
require_relative '../../../lib/onetime/operations/fetch_domain_favicon'

FDF = Onetime::Operations::FetchDomainFavicon
SF  = Onetime::Net::SafeFetch

# The terminal recorders now dig jobs.favicon_backfill for the backoff curve
# (#3780 Phase 3). These tryouts don't boot, so OT.conf is nil — stub the subtree
# the recorders read and restore it at the end so sibling tryouts are unaffected.
@orig_conf = OT.instance_variable_get(:@conf)
OT.instance_variable_set(:@conf, {
  'jobs' => {
    'favicon_backfill' => { 'base_days' => 1, 'cap_days' => 30, 'max_attempts' => 6 },
  },
})

# Valid 16x16 PNG header (FastImage sniffs :png, size [16, 16]) and a 16x16 ICO.
PNG_BYTES = ("\x89PNG\r\n\x1a\n".b + "\x00\x00\x00\rIHDR".b +
             "\x00\x00\x00\x10\x00\x00\x00\x10\x08\x06\x00\x00\x00".b + "\x1f\xf3\xffa".b).freeze
ICO_BYTES = ("\x00\x00\x01\x00\x01\x00\x10\x10\x00\x00\x01\x00\x20\x00".b + ("\x00" * 32).b).freeze

# In-memory stand-in for a Familia hashkey (icon). Stores string-keyed values
# verbatim; implements only what the operation touches.
class FakeIcon
  def initialize(seed = {})
    @h                            = {}
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

  def hgetall
    @h.dup
  end
end

# In-memory stand-in for CustomDomain. Records save_fields calls so tests can
# assert whether (and which) status fields were persisted.
class FakeDomain
  attr_accessor :favicon_fetch_status, :favicon_fetched, :favicon_fetch_error, :favicon_fetch_completed_at,
                :favicon_fetch_attempts, :favicon_fetch_next_at
  attr_reader :icon, :display_domain, :saved_fields

  def initialize(display_domain:, icon: {}, favicon_fetched: nil)
    @display_domain  = display_domain
    @icon            = FakeIcon.new(icon)
    @favicon_fetched = favicon_fetched
    @saved_fields    = []
  end

  def save_fields(*fields, **_opts)
    @saved_fields.concat(fields)
    self
  end
end

# SafeFetch double routing by exact URL. A value that is an Exception is raised
# (a SafeFetch::Error means "no icon here"; a FetchTimeout is retriable; any
# other exception is an unexpected failure). The default for an unrouted image
# URL is a base SafeFetch::Error (mirrors a 404 on /favicon.ico).
class RouteFetcher
  def initialize(images: {}, html: {})
    @images = images
    @html   = html
  end

  def get_image(url)
    value = @images.fetch(url) { SF::Error.new("no icon at #{url}") }
    raise value if value.is_a?(Exception)

    value
  end

  def get_html(url)
    value = @html.fetch(url) { SF::Error.new("no html at #{url}") }
    raise value if value.is_a?(Exception)

    value.to_s
  end
end

def png_result(url = 'https://a.test/favicon.ico')
  SF::Result.new(body: PNG_BYTES, content_type: 'image/png', final_url: url)
end

def ico_result(url = 'https://a.test/favicon.ico')
  SF::Result.new(body: ICO_BYTES, content_type: 'image/x-icon', final_url: url)
end

# The not-found case exercises the real Onetime::CustomDomain.load seam; stub it
# to consult an (empty) registry so an unknown id resolves to nil hermetically.
FAVICON_FAKES = {}
Onetime::CustomDomain.define_singleton_method(:load) { |id| FAVICON_FAKES[id] }

## Direct /favicon.ico success writes the icon and returns a COMPLETED Result
@ok_dom = FakeDomain.new(display_domain: 'a.test')
@ok_res = FDF.new(
  domain_id: 'd-ok',
  custom_domain: @ok_dom,
  fetcher: RouteFetcher.new(images: { 'https://a.test/favicon.ico' => png_result }),
).call
[@ok_res.favicon_fetched, @ok_res.status, @ok_res.content_type, @ok_res.favicon_source,
 @ok_res.success?, @ok_dom.favicon_fetch_status, @ok_dom.favicon_fetched]
#=> [true, 'completed', 'image/png', 'auto_fetch', true, 'completed', true]

## The written icon carries the full UpdateDomainImage shape and drops the stale cache
@shape_dom = FakeDomain.new(display_domain: 'a.test', icon: { 'encoded_favicon' => 'stale-cache' })
FDF.new(
  domain_id: 'd-shape',
  custom_domain: @shape_dom,
  fetcher: RouteFetcher.new(images: { 'https://a.test/favicon.ico' => png_result }),
).call
[@shape_dom.icon.hgetall.keys.sort, @shape_dom.icon['favicon_source'], @shape_dom.icon['encoded_favicon'].nil?]
#=> [['bytes', 'content_type', 'encoded', 'favicon_source', 'filename', 'height', 'ratio', 'width'], 'auto_fetch', true]

## PNG dimensions are measured via FastImage (16x16 header → ratio 1.0)
[@shape_dom.icon['width'], @shape_dom.icon['height'], @shape_dom.icon['ratio'], @shape_dom.icon['filename']]
#=> [16, 16, 1.0, 'favicon.png']

## The encoded bytes and byte count round-trip from the fetched body
[Base64.strict_decode64(@shape_dom.icon['encoded']) == PNG_BYTES, @shape_dom.icon['bytes']]
#=> [true, PNG_BYTES.bytesize]

## ICO fetch stores content_type image/x-icon verbatim (passthrough, no resize)
@ico_dom = FakeDomain.new(display_domain: 'a.test')
@ico_res = FDF.new(
  domain_id: 'd-ico',
  custom_domain: @ico_dom,
  fetcher: RouteFetcher.new(images: { 'https://a.test/favicon.ico' => ico_result }),
).call
[@ico_res.content_type, @ico_dom.icon['content_type'], @ico_dom.icon['filename'], @ico_dom.icon['favicon_source']]
#=> ['image/x-icon', 'image/x-icon', 'favicon.ico', 'auto_fetch']

## HTML <link rel=icon> discovery: /favicon.ico misses, root HTML yields a candidate
@disc_dom = FakeDomain.new(display_domain: 'a.test')
@disc_res = FDF.new(
  domain_id: 'd-disc',
  custom_domain: @disc_dom,
  fetcher: RouteFetcher.new(
    images: { 'https://a.test/icon.png' => png_result('https://a.test/icon.png') },
    html: { 'https://a.test/' => '<html><head><link rel="shortcut icon" href="/icon.png"></head></html>' },
  ),
).call
[@disc_res.favicon_fetched, @disc_res.final_url, @disc_dom.icon['favicon_source']]
#=> [true, 'https://a.test/icon.png', 'auto_fetch']

## Overwrite guard: a user_upload icon is never fetched over (no write, no save)
@up_dom = FakeDomain.new(
  display_domain: 'a.test',
  icon: { 'filename' => 'logo.png', 'favicon_source' => 'user_upload' },
  favicon_fetched: false,
)
@up_res = FDF.new(
  domain_id: 'd-up',
  custom_domain: @up_dom,
  fetcher: RouteFetcher.new(images: { 'https://a.test/favicon.ico' => png_result }),
).call
[@up_res.skipped, @up_res.favicon_fetched, @up_dom.icon['favicon_source'],
 @up_dom.icon['filename'], @up_dom.saved_fields.empty?]
#=> [true, false, 'user_upload', 'logo.png', true]

## Overwrite guard: a legacy filename-only icon (no favicon_source) is also protected
@legacy_dom = FakeDomain.new(display_domain: 'a.test', icon: { 'filename' => 'old.png' })
@legacy_res = FDF.new(
  domain_id: 'd-legacy',
  custom_domain: @legacy_dom,
  fetcher: RouteFetcher.new(images: { 'https://a.test/favicon.ico' => png_result }),
).call
[@legacy_res.skipped, @legacy_dom.icon['filename'], @legacy_dom.saved_fields.empty?]
#=> [true, 'old.png', true]

## No favicon found anywhere → COMPLETED with favicon_fetched=false (success, not FAILED)
@none_dom = FakeDomain.new(display_domain: 'a.test')
@none_res = FDF.new(
  domain_id: 'd-none',
  custom_domain: @none_dom,
  fetcher: RouteFetcher.new(html: { 'https://a.test/' => '<html><head></head></html>' }),
).call
[@none_res.favicon_fetched, @none_res.status, @none_res.success?,
 @none_dom.favicon_fetch_status, @none_dom.favicon_fetched]
#=> [false, 'completed', true, 'completed', false]

## An existing auto_fetch icon is skipped without force
@auto_dom = FakeDomain.new(
  display_domain: 'a.test',
  icon: { 'filename' => 'favicon.png', 'favicon_source' => 'auto_fetch' },
  favicon_fetched: true,
)
@auto_res = FDF.new(
  domain_id: 'd-auto',
  custom_domain: @auto_dom,
  force: false,
  fetcher: RouteFetcher.new(images: { 'https://a.test/favicon.ico' => png_result }),
).call
[@auto_res.skipped, @auto_dom.saved_fields.empty?]
#=> [true, true]

## force:true re-fetches over an existing auto_fetch icon
@force_dom = FakeDomain.new(
  display_domain: 'a.test',
  icon: { 'filename' => 'favicon.png', 'favicon_source' => 'auto_fetch' },
  favicon_fetched: true,
)
@force_res = FDF.new(
  domain_id: 'd-force',
  custom_domain: @force_dom,
  force: true,
  fetcher: RouteFetcher.new(images: { 'https://a.test/favicon.ico' => ico_result }),
).call
[@force_res.skipped, @force_res.favicon_fetched, @force_res.content_type, @force_dom.icon['content_type']]
#=> [false, true, 'image/x-icon', 'image/x-icon']

## A transient FetchTimeout is re-raised (retriable) and leaves the lifecycle at PROCESSING
@to_dom     = FakeDomain.new(display_domain: 'a.test')
@to_outcome = begin
  FDF.new(
    domain_id: 'd-to',
    custom_domain: @to_dom,
    fetcher: RouteFetcher.new(images: { 'https://a.test/favicon.ico' => SF::FetchTimeout.new('slow') }),
  ).call
  :no_raise
rescue SF::FetchTimeout
  :fetch_timeout
end
[@to_outcome, @to_dom.favicon_fetch_status]
#=> [:fetch_timeout, 'processing']

## An unexpected error records FAILED + favicon_fetch_error and re-raises
@err_dom     = FakeDomain.new(display_domain: 'a.test')
@err_outcome = begin
  FDF.new(
    domain_id: 'd-err',
    custom_domain: @err_dom,
    fetcher: RouteFetcher.new(images: { 'https://a.test/favicon.ico' => RuntimeError.new('boom') }),
  ).call
  :no_raise
rescue RuntimeError => ex
  ex.message
end
[@err_outcome, @err_dom.favicon_fetch_status, @err_dom.favicon_fetch_error]
#=> ['boom', 'failed', 'boom']

## A missing CustomDomain returns a permanent-miss Result without raising
@missing_res = FDF.new(domain_id: 'nonexistent-id').call
[@missing_res.not_found, @missing_res.success?, @missing_res.status, @missing_res.favicon_fetched]
#=> [true, true, nil, nil]

## Restore the process-global OT.conf for sibling tryouts
OT.instance_variable_set(:@conf, @orig_conf)
OT.instance_variable_get(:@conf).equal?(@orig_conf)
#=> true
