# try/unit/net/safe_fetch_try.rb
#
# frozen_string_literal: true

# SSRF-guard unit coverage for Onetime::Net::SafeFetch (#3780).
#
# Hermetic: DNS (Resolv) and transport (Net::HTTP) are stubbed via subclass
# seams, so NO real network is touched and no OT.boot! / Redis / encryption is
# required (requiring 'onetime' through the support helper is enough to define
# Onetime::Problem, the error base).
#
# Proves: metadata/loopback/link-local blocked (incl. v4-mapped and via
# redirect), fail-closed on mixed RRsets and unparseable/encoded addresses,
# https+443-only, redirect cap, timeout mapping, streamed + declared size caps,
# SVG/foreign-type rejection, and PNG/ICO acceptance with magic-byte sniffing.
#
# Relied-on runtime: Ruby 3.4.9 (IPAddr rejects decimal/octal/hex-encoded IPv4
# with InvalidAddressError → our rescue treats them as blocked); FastImage 2.4.1
# (magic-byte type sniff from a StringIO).

require_relative '../../support/test_helpers'
require_relative '../../../lib/onetime/net/safe_fetch'

SF = Onetime::Net::SafeFetch

# Sample payloads (verified magic-byte families: :png, :ico, :svg, :gif).
PNG_BYTES = ("\x89PNG\r\n\x1a\n".b + "\x00\x00\x00\rIHDR".b +
             "\x00\x00\x00\x10\x00\x00\x00\x10\x08\x06\x00\x00\x00".b + "\x1f\xf3\xffa".b).freeze
ICO_BYTES = ("\x00\x00\x01\x00\x01\x00\x10\x10\x00\x00\x01\x00\x20\x00".b + ("\x00" * 32).b).freeze
SVG_BYTES = %(<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg"></svg>).b.freeze
GIF_BYTES = ("GIF89a".b + ("\x00" * 20).b).freeze

# Minimal stand-in for Net::HTTPResponse: exposes only what interpret_response
# and read_capped_body consume. content_length: :auto == honest byte count;
# pass an Integer to fake a lying Content-Length, or nil to omit it.
class FakeResponse
  attr_reader :code

  def initialize(code:, headers: {}, chunks: [], content_length: :auto)
    @code    = code.to_s
    @headers = headers.transform_keys { |k| k.to_s.downcase }
    @chunks  = chunks
    @content_length = content_length == :auto ? chunks.sum(&:bytesize) : content_length
  end

  def [](name)
    @headers[name.to_s.downcase]
  end

  def content_type
    @headers['content-type']
  end

  attr_reader :content_length

  def read_body
    @chunks.each { |chunk| yield chunk }
  end
end

# SafeFetch with DNS + transport stubbed. dns maps host => [ip strings];
# responses is a per-hop queue. A :timeout sentinel raises a real
# Net::OpenTimeout so #fetch's real timeout→FetchTimeout mapping is exercised.
class StubFetch < SF
  DEFAULTS = {
    timeout: 5, max_bytes: 102_400, max_redirects: 3,
    allowed_content_types: %w[image/x-icon image/vnd.microsoft.icon image/png]
  }.freeze

  def initialize(dns:, responses:, **opts)
    super(**DEFAULTS.merge(opts))
    @dns       = dns
    @responses = Array(responses)
  end

  def resolve_addresses(host)
    @dns.fetch(host) { [] }
  end

  def with_pinned_response(_uri, _validated_ip)
    item = @responses.shift
    raise ::Net::OpenTimeout, 'stubbed connect timeout' if item == :timeout
    raise 'no stubbed response queued' if item.nil?

    yield item
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

def image_response(chunks:, content_type: 'application/octet-stream', **opts)
  FakeResponse.new(code: 200, headers: { 'content-type' => content_type }, chunks: chunks, **opts)
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
    responses: [redirect_to('https://meta.test/')]
  ).get_image('https://start.test/favicon.ico')
end
#=> :blocked_target

## Redirect that downgrades scheme (Location: http://) is blocked at re-check
classify do
  StubFetch.new(
    dns: { 'start.test' => ['93.184.216.34'] },
    responses: [redirect_to('http://evil.test/')]
  ).get_image('https://start.test/favicon.ico')
end
#=> :blocked_target

## Redirect cap is enforced (max_redirects: 1, two redirects queued)
classify do
  StubFetch.new(
    dns: { 'a.test' => ['93.184.216.34'], 'b.test' => ['93.184.216.34'] },
    responses: [redirect_to('https://b.test/'), redirect_to('https://c.test/')],
    max_redirects: 1
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
    max_bytes: 10
  ).get_image('https://a.test/favicon.ico')
end
#=> :response_too_large

## Streamed body over the cap is rejected mid-read (absent/lying Content-Length)
classify do
  StubFetch.new(
    dns: { 'a.test' => ['93.184.216.34'] },
    responses: [image_response(chunks: ['aaaaaa', 'bbbbbb'], content_type: 'image/png', content_length: nil)],
    max_bytes: 10
  ).get_image('https://a.test/favicon.ico')
end
#=> :response_too_large

## SVG payload is rejected (textual guard, before magic-byte sniff)
classify do
  StubFetch.new(
    dns: { 'a.test' => ['93.184.216.34'] },
    responses: [image_response(chunks: [SVG_BYTES], content_type: 'image/svg+xml')]
  ).get_image('https://a.test/favicon.svg')
end
#=> :disallowed_content_type

## A foreign image type (GIF) is rejected by magic-byte sniff
classify do
  StubFetch.new(
    dns: { 'a.test' => ['93.184.216.34'] },
    responses: [image_response(chunks: [GIF_BYTES], content_type: 'image/gif')]
  ).get_image('https://a.test/favicon.gif')
end
#=> :disallowed_content_type

## Valid PNG is accepted; content_type is the SNIFFED mime, body is byte-exact
@png = StubFetch.new(
  dns: { 'a.test' => ['93.184.216.34'] },
  responses: [image_response(chunks: [PNG_BYTES], content_type: 'image/png')]
).get_image('https://a.test/favicon.ico')
[@png.content_type, @png.body == PNG_BYTES, @png.final_url]
#=> ['image/png', true, 'https://a.test/favicon.ico']

## Valid ICO is accepted; magic-byte sniff overrides a lying Content-Type header
@ico = StubFetch.new(
  dns: { 'a.test' => ['93.184.216.34'] },
  responses: [image_response(chunks: [ICO_BYTES], content_type: 'application/octet-stream')]
).get_image('https://a.test/favicon.ico')
[@ico.content_type, @ico.body == ICO_BYTES]
#=> ['image/x-icon', true]

## A permitted redirect is followed; final_url reflects the terminal hop
@redir = StubFetch.new(
  dns: { 'good.test' => ['93.184.216.34'], 'cdn.test' => ['93.184.216.34'] },
  responses: [redirect_to('https://cdn.test/icon.png'), image_response(chunks: [PNG_BYTES], content_type: 'image/png')]
).get_image('https://good.test/favicon.ico')
[@redir.content_type, @redir.final_url]
#=> ['image/png', 'https://cdn.test/icon.png']

## get_html applies the same guard and returns the raw body string
StubFetch.new(
  dns: { 'a.test' => ['93.184.216.34'] },
  responses: [FakeResponse.new(code: 200, headers: { 'content-type' => 'text/html' },
                               chunks: ['<html><link rel="icon" href="/f.ico"></html>'])]
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
