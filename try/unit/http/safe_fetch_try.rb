# try/unit/http/safe_fetch_try.rb
#
# frozen_string_literal: true

# SSRF-guard unit coverage for Onetime::Http::SafeFetch (#3780).
#
# Hermetic: DNS (Resolv) and transport (Net::HTTP) are stubbed via subclass
# seams, so NO real network is touched and no OT.boot! / Redis / encryption is
# required (requiring 'onetime' through the support helper is enough to define
# Onetime::Problem, the error base).
#
# Proves: metadata/loopback/link-local blocked (incl. v4-mapped and via
# redirect), fail-closed on mixed RRsets and unparseable/encoded addresses,
# https+443-only, redirect cap, timeout mapping, streamed + declared size caps,
# SVG/foreign-type rejection, PNG/ICO acceptance with magic-byte sniffing, and
# IPv4-first address ordering with connect-level fallback through the validated
# address list (broken dual-stack: EHOSTUNREACH on one family, not the other).
#
# Relied-on runtime: Ruby 3.4.9 (IPAddr rejects decimal/octal/hex-encoded IPv4
# with InvalidAddressError → our rescue treats them as blocked); FastImage 2.4.1
# (magic-byte type sniff from a StringIO).

require_relative '../../support/test_helpers'
require_relative '../../../lib/onetime/http/safe_fetch'

SF = Onetime::Http::SafeFetch

# Sample payloads (verified magic-byte families: :png, :ico, :svg, :gif).
PNG_BYTES = ("\x89PNG\r\n\x1a\n".b + "\x00\x00\x00\rIHDR".b +
             "\x00\x00\x00\x10\x00\x00\x00\x10\x08\x06\x00\x00\x00".b + "\x1f\xf3\xffa".b).freeze
ICO_BYTES = ("\x00\x00\x01\x00\x01\x00\x10\x10\x00\x00\x01\x00\x20\x00".b + ("\x00" * 32).b).freeze
SVG_BYTES = %(<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg"></svg>).b.freeze
GIF_BYTES = ('GIF89a'.b + ("\x00" * 20).b).freeze

# Minimal stand-in for Net::HTTPResponse: exposes only what interpret_response
# and read_capped_body consume. content_length: :auto == honest byte count;
# pass an Integer to fake a lying Content-Length, or nil to omit it.
class FakeResponse
  attr_reader :code, :content_length

  def initialize(code:, headers: {}, chunks: [], content_length: :auto)
    @code           = code.to_s
    @headers        = headers.transform_keys { |k| k.to_s.downcase }
    @chunks         = chunks
    @content_length = content_length == :auto ? chunks.sum(&:bytesize) : content_length
  end

  def [](name)
    @headers[name.to_s.downcase]
  end

  def content_type
    @headers['content-type']
  end

  def read_body(&)
    @chunks.each(&)
  end
end

# SafeFetch with DNS + transport stubbed. dns maps host => [ip strings];
# responses is a per-hop queue. A :timeout sentinel raises a real
# Net::OpenTimeout so #fetch's real timeout→FetchTimeout mapping is exercised.
# unreachable lists IPs whose dial raises Errno::EHOSTUNREACH (before touching
# the response queue), and dialed records every pinned connect attempt in order.
class StubFetch < SF
  DEFAULTS = {
    timeout: 5,
    max_bytes: 102_400,
    max_redirects: 3,
    allowed_content_types: %w[image/x-icon image/vnd.microsoft.icon image/png],
  }.freeze

  attr_reader :dialed

  def initialize(dns:, responses:, unreachable: [], **opts)
    super(**DEFAULTS.merge(opts))
    @dns         = dns
    @responses   = Array(responses)
    @unreachable = Array(unreachable)
    @dialed      = []
  end

  def resolve_addresses(host)
    @dns.fetch(host) { [] }
  end

  def with_pinned_response(_uri, validated_ip)
    @dialed << validated_ip
    raise Errno::EHOSTUNREACH, "stubbed no route to #{validated_ip}" if @unreachable.include?(validated_ip)

    item = @responses.shift
    raise ::Net::OpenTimeout, 'stubbed connect timeout' if item == :timeout
    raise 'no stubbed response queued' if item.nil?

    yield item
  end
end

# StubFetch with a scripted monotonic clock, to exercise the wall-clock deadline
# without real time. new_deadline consumes the first tick; each check_deadline!
# consumes the next. total_budget = timeout * (max_redirects + 1) = 5 * 4 = 20.
class ClockFetch < StubFetch
  def initialize(clock:, **)
    super(**)
    @clock = clock
  end

  def monotonic_now
    @clock.shift || 1_000_000.0
  end
end

# Classify whatever a fetch raises into a stable symbol for assertions.
def classify
  yield
  :no_raise
rescue SF::BlockedTarget
  :blocked_target
rescue SF::TooManyRedirects
  :too_many_redirects
rescue SF::ResponseTooLarge
  :response_too_large
rescue SF::DisallowedContentType
  :disallowed_content_type
rescue SF::FetchTimeout
  :fetch_timeout
rescue SF::Error
  :error
rescue StandardError => ex
  "unexpected:#{ex.class}"
end

def image_response(chunks:, content_type: 'application/octet-stream', **)
  FakeResponse.new(code: 200, headers: { 'content-type' => content_type }, chunks: chunks, **)
end

def redirect_to(location, code: 302)
  FakeResponse.new(code: code, headers: { 'location' => location })
end

## SafeFetch and its error hierarchy are defined under Onetime::Problem
[SF::BlockedTarget, SF::TooManyRedirects, SF::ResponseTooLarge,
 SF::DisallowedContentType, SF::FetchTimeout].all? { |k| k < SF::Error && k < Onetime::Problem }
#=> true

## Cloud metadata IP (169.254.169.254) is blocked
classify { StubFetch.new(dns: { 'meta.test' => ['169.254.169.254'] }, responses: []).get_image('https://meta.test/favicon.ico') }
#=> :blocked_target

## Loopback (127.0.0.1) is blocked
classify { StubFetch.new(dns: { 'lo.test' => ['127.0.0.1'] }, responses: []).get_image('https://lo.test/favicon.ico') }
#=> :blocked_target

## IPv4-mapped IPv6 loopback (::ffff:127.0.0.1) is unwrapped and blocked
classify { StubFetch.new(dns: { 'v6.test' => ['::ffff:127.0.0.1'] }, responses: []).get_image('https://v6.test/favicon.ico') }
#=> :blocked_target

## IPv6 loopback (::1) is blocked
classify { StubFetch.new(dns: { 'v6.test' => ['::1'] }, responses: []).get_image('https://v6.test/favicon.ico') }
#=> :blocked_target

## Private RFC1918 (10.0.0.5) is blocked
classify { StubFetch.new(dns: { 'p.test' => ['10.0.0.5'] }, responses: []).get_image('https://p.test/favicon.ico') }
#=> :blocked_target

## Fail-closed: a mixed RRset (one public + one private) is rejected
classify { StubFetch.new(dns: { 'mix.test' => ['93.184.216.34', '127.0.0.1'] }, responses: []).get_image('https://mix.test/favicon.ico') }
#=> :blocked_target

## No A/AAAA records → blocked (empty resolution is not fetchable)
classify { StubFetch.new(dns: { 'nx.test' => [] }, responses: []).get_image('https://nx.test/favicon.ico') }
#=> :blocked_target

## Non-https scheme is rejected before any resolution
classify { StubFetch.new(dns: { 'a.test' => ['93.184.216.34'] }, responses: []).get_image('http://a.test/favicon.ico') }
#=> :blocked_target

## Non-443 port is rejected
classify { StubFetch.new(dns: { 'a.test' => ['93.184.216.34'] }, responses: []).get_image('https://a.test:8443/favicon.ico') }
#=> :blocked_target

## Redirect to a metadata host is blocked at re-validation of the new hop
classify do
  StubFetch.new(
    dns: { 'start.test' => ['93.184.216.34'], 'meta.test' => ['169.254.169.254'] },
    responses: [redirect_to('https://meta.test/')],
  ).get_image('https://start.test/favicon.ico')
end
#=> :blocked_target

## Redirect that downgrades scheme (Location: http://) is blocked at re-check
classify do
  StubFetch.new(
    dns: { 'start.test' => ['93.184.216.34'] },
    responses: [redirect_to('http://evil.test/')],
  ).get_image('https://start.test/favicon.ico')
end
#=> :blocked_target

## Redirect cap is enforced (max_redirects: 1, two redirects queued)
classify do
  StubFetch.new(
    dns: { 'a.test' => ['93.184.216.34'], 'b.test' => ['93.184.216.34'] },
    responses: [redirect_to('https://b.test/'), redirect_to('https://c.test/')],
    max_redirects: 1,
  ).get_image('https://a.test/favicon.ico')
end
#=> :too_many_redirects

## Connect/read timeout is mapped to the retriable FetchTimeout
classify { StubFetch.new(dns: { 'a.test' => ['93.184.216.34'] }, responses: [:timeout]).get_image('https://a.test/favicon.ico') }
#=> :fetch_timeout

## Declared Content-Length over the cap is rejected before reading the body
classify do
  StubFetch.new(
    dns: { 'a.test' => ['93.184.216.34'] },
    responses: [image_response(chunks: ['x'], content_type: 'image/png', content_length: 99_999)],
    max_bytes: 10,
  ).get_image('https://a.test/favicon.ico')
end
#=> :response_too_large

## Streamed body over the cap is rejected mid-read (absent/lying Content-Length)
classify do
  StubFetch.new(
    dns: { 'a.test' => ['93.184.216.34'] },
    responses: [image_response(chunks: %w[aaaaaa bbbbbb], content_type: 'image/png', content_length: nil)],
    max_bytes: 10,
  ).get_image('https://a.test/favicon.ico')
end
#=> :response_too_large

## SVG payload is rejected (textual guard, before magic-byte sniff)
classify do
  StubFetch.new(
    dns: { 'a.test' => ['93.184.216.34'] },
    responses: [image_response(chunks: [SVG_BYTES], content_type: 'image/svg+xml')],
  ).get_image('https://a.test/favicon.svg')
end
#=> :disallowed_content_type

## A foreign image type (GIF) is rejected by magic-byte sniff
classify do
  StubFetch.new(
    dns: { 'a.test' => ['93.184.216.34'] },
    responses: [image_response(chunks: [GIF_BYTES], content_type: 'image/gif')],
  ).get_image('https://a.test/favicon.gif')
end
#=> :disallowed_content_type

## Valid PNG is accepted; content_type is the SNIFFED mime, body is byte-exact
@png = StubFetch.new(
  dns: { 'a.test' => ['93.184.216.34'] },
  responses: [image_response(chunks: [PNG_BYTES], content_type: 'image/png')],
).get_image('https://a.test/favicon.ico')
[@png.content_type, @png.body == PNG_BYTES, @png.final_url]
#=> ['image/png', true, 'https://a.test/favicon.ico']

## Valid ICO is accepted; magic-byte sniff overrides a lying Content-Type header
@ico = StubFetch.new(
  dns: { 'a.test' => ['93.184.216.34'] },
  responses: [image_response(chunks: [ICO_BYTES], content_type: 'application/octet-stream')],
).get_image('https://a.test/favicon.ico')
[@ico.content_type, @ico.body == ICO_BYTES]
#=> ['image/x-icon', true]

## A permitted redirect is followed; final_url reflects the terminal hop
@redir = StubFetch.new(
  dns: { 'good.test' => ['93.184.216.34'], 'cdn.test' => ['93.184.216.34'] },
  responses: [redirect_to('https://cdn.test/icon.png'), image_response(chunks: [PNG_BYTES], content_type: 'image/png')],
).get_image('https://good.test/favicon.ico')
[@redir.content_type, @redir.final_url]
#=> ['image/png', 'https://cdn.test/icon.png']

## get_html applies the same guard and returns the raw body string
StubFetch.new(
  dns: { 'a.test' => ['93.184.216.34'] },
  responses: [FakeResponse.new(
    code: 200,
    headers: { 'content-type' => 'text/html' },
    chunks: ['<html><link rel="icon" href="/f.ico"></html>'],
  )],
).get_html('https://a.test/').include?('link rel="icon"')
#=> true

## get_html enforces the SSRF guard too (blocked host raises)
classify { StubFetch.new(dns: { 'lo.test' => ['127.0.0.1'] }, responses: []).get_html('https://lo.test/') }
#=> :blocked_target

## Public IP passes the guard predicate; loopback/metadata do not
f = StubFetch.new(dns: {}, responses: [])
[f.send(:blocked_ip?, '93.184.216.34'), f.send(:blocked_ip?, '127.0.0.1'), f.send(:blocked_ip?, '169.254.169.254')]
#=> [false, true, true]

## Ruby 3.4.9 IPAddr REJECTS decimal-encoded IPv4 (does not normalize it)
begin
  IPAddr.new('2130706433')
  :normalized
rescue IPAddr::InvalidAddressError
  :rejected
end
#=> :rejected

## Encoded-loopback smuggling (2130706433 / 0x7f000001) fails closed as blocked
f = StubFetch.new(dns: {}, responses: [])
[f.send(:blocked_ip?, '2130706433'), f.send(:blocked_ip?, '0x7f000001')]
#=> [true, true]

## IPv6 6to4 (2002::/16) embedding a metadata/private v4 is blocked
f = StubFetch.new(dns: {}, responses: [])
[f.send(:blocked_ip?, '2002:a9fe:a9fe::'), f.send(:blocked_ip?, '2002:0a00:0001::')]
#=> [true, true]

## IPv6 v4-compatible (::/96) and RFC 8215 local-NAT64 (64:ff9b:1::/48) are blocked
f = StubFetch.new(dns: {}, responses: [])
[f.send(:blocked_ip?, '::127.0.0.1'), f.send(:blocked_ip?, '64:ff9b:1::7f00:1')]
#=> [true, true]

## A public IPv6 (Cloudflare 2606:4700:4700::1111) still passes the guard
StubFetch.new(dns: {}, responses: []).send(:blocked_ip?, '2606:4700:4700::1111')
#=> false

## Redirect to a 6to4-encoded metadata host is blocked at re-validation of the new hop
classify do
  StubFetch.new(
    dns: { 'start.test' => ['93.184.216.34'], 'sixto4.test' => ['2002:a9fe:a9fe::'] },
    responses: [redirect_to('https://sixto4.test/')],
  ).get_image('https://start.test/favicon.ico')
end
#=> :blocked_target

## Deadline exceeded at the first hop → FetchTimeout before any fetch work
classify do
  ClockFetch.new(
    clock: [0.0, 100.0], # deadline = 0 + 20; first check at 100 > 20
    dns: { 'a.test' => ['93.184.216.34'] },
    responses: [image_response(chunks: [PNG_BYTES], content_type: 'image/png')],
  ).get_image('https://a.test/favicon.ico')
end
#=> :fetch_timeout

## Deadline exceeded mid body-read (slow drip) → FetchTimeout during read_capped_body
classify do
  ClockFetch.new(
    clock: [0.0, 1.0, 100.0], # deadline 20; hop check at 1 (ok); body-read check at 100 (trips)
    dns: { 'a.test' => ['93.184.216.34'] },
    responses: [image_response(chunks: [PNG_BYTES], content_type: 'image/png')],
  ).get_image('https://a.test/favicon.ico')
end
#=> :fetch_timeout

## A fetch that stays within budget still returns the Result (no false trip)
ClockFetch.new(
  clock: [0.0, 1.0, 2.0], # all < deadline 20
  dns: { 'a.test' => ['93.184.216.34'] },
  responses: [image_response(chunks: [PNG_BYTES], content_type: 'image/png')],
).get_image('https://a.test/favicon.ico').content_type
#=> 'image/png'

## Dual-stack RRset with AAAA listed first: the v4 address is dialed FIRST
@order = StubFetch.new(
  dns: { 'ds.test' => ['2606:4700:4700::1111', '93.184.216.34'] },
  responses: [image_response(chunks: [PNG_BYTES], content_type: 'image/png')],
)
@order.get_image('https://ds.test/favicon.ico')
@order.dialed
#=> ['93.184.216.34']

## Connect fallback: first address unreachable → the next validated address is
## dialed (still pinned) and serves the result
@fall = StubFetch.new(
  dns: { 'ds.test' => ['2606:4700:4700::1111', '93.184.216.34'] },
  responses: [image_response(chunks: [PNG_BYTES], content_type: 'image/png')],
  unreachable: ['93.184.216.34'],
)
[@fall.get_image('https://ds.test/favicon.ico').content_type, @fall.dialed]
#=> ['image/png', ['93.184.216.34', '2606:4700:4700::1111']]

## Every validated address unreachable → the last errno propagates unchanged
## (stays terminal for the worker's retry classification, as pre-fallback)
classify do
  StubFetch.new(
    dns: { 'ds.test' => ['2606:4700:4700::1111', '93.184.216.34'] },
    responses: [],
    unreachable: ['2606:4700:4700::1111', '93.184.216.34'],
  ).get_image('https://ds.test/favicon.ico')
end
#=> "unexpected:Errno::EHOSTUNREACH"

## A timeout does NOT fall through to the next address: one dial, retriable
@to = StubFetch.new(
  dns: { 'ds.test' => ['2606:4700:4700::1111', '93.184.216.34'] },
  responses: [:timeout],
)
[classify { @to.get_image('https://ds.test/favicon.ico') }, @to.dialed]
#=> [:fetch_timeout, ['93.184.216.34']]
