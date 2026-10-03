# spec/unit/onetime/middleware/public_host_rewrite_adversarial_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'logger'
require 'middleware/detect_host'
require 'onetime/middleware/strip_forwarded_host'
require 'onetime/middleware/domain_strategy'
require 'onetime/middleware/public_host_rewrite'

# Adversarial matrix for PublicHostRewrite (#4223).
#
# Runs the real Rack::DetectHost -> StripForwardedHost -> DomainStrategy ->
# PublicHostRewrite chain over the cross product of peer trust states and
# hostile or malformed Host / X-Forwarded-Host / X-Forwarded-Port /
# Forwarded values, and checks properties of the env the apps receive
# rather than individual outputs.
RSpec.describe Onetime::Middleware::PublicHostRewrite, 'adversarial matrix' do
  CANONICAL  = 'example.com'
  REGISTERED = 'secrets.acme.com'
  ORIGIN     = 'origin.internal:3000'

  PEERS = {
    public_no_verdict: { 'REMOTE_ADDR' => '203.0.113.9' },
    private_no_verdict: { 'REMOTE_ADDR' => '10.0.0.5' },
    loopback_no_verdict: { 'REMOTE_ADDR' => '127.0.0.1' },
    mapped_private_no_verdict: { 'REMOTE_ADDR' => '::ffff:10.0.0.5' },
    verdict_true: { 'REMOTE_ADDR' => '203.0.113.9', 'otto.via_trusted_proxy' => true },
    verdict_false_private: { 'REMOTE_ADDR' => '10.0.0.5', 'otto.via_trusted_proxy' => false },
    verdict_string: { 'REMOTE_ADDR' => '10.0.0.5', 'otto.via_trusted_proxy' => 'true' },
    verdict_nil: { 'REMOTE_ADDR' => '10.0.0.5', 'otto.via_trusted_proxy' => nil },
  }.freeze

  TRUSTED_PEERS = [:private_no_verdict, :loopback_no_verdict, :verdict_true].freeze

  HOSTS = [
    ORIGIN,
    CANONICAL,
    REGISTERED,
    "#{REGISTERED}:8443",
    'evil.test',
    'evil.test:8443',
    "#{REGISTERED}, evil.test",
    "evil.test, #{REGISTERED}",
    "#{REGISTERED}@evil.test",
    "evil.test@#{REGISTERED}",
    '10.0.0.7:3000',
    'localhost:3000',
    '',
    nil,
  ].freeze

  FORWARDED_HOSTS = [
    nil,
    '',
    REGISTERED,
    REGISTERED.upcase,
    "#{REGISTERED}.",
    " #{REGISTERED} ",
    "#{REGISTERED}:8443",
    "#{REGISTERED}:443",
    "#{REGISTERED}:80",
    "#{REGISTERED}:0",
    "#{REGISTERED}:65536",
    "#{REGISTERED}:99999",
    "#{REGISTERED}:",
    "#{REGISTERED}:abc",
    "#{REGISTERED}:8443:9",
    "#{REGISTERED}:8443/path",
    "#{REGISTERED}/path",
    "#{REGISTERED}?x=1",
    "#{REGISTERED}#evil.test",
    "#{REGISTERED}@evil.test",
    "evil.test@#{REGISTERED}",
    "user:pw@#{REGISTERED}",
    "https://#{REGISTERED}",
    "https://#{REGISTERED}:8443/x",
    "https://evil.test@#{REGISTERED}/",
    "https://#{REGISTERED}@evil.test/",
    "#{REGISTERED}\r\nX-Injected: 1",
    "#{REGISTERED}\tevil.test",
    "#{REGISTERED} evil.test",
    "#{REGISTERED}, evil.test",
    "evil.test, #{REGISTERED}",
    "#{REGISTERED},",
    CANONICAL,
    "www.#{CANONICAL}",
    "tenant.#{CANONICAL}",
    'evil.test',
    'unregistered.test:8443',
    'broken-read.test',
    '10.0.0.7',
    '[::1]:8443',
    'localhost',
    'xn--e1afmkfd.xn--p1ai',
    "-#{REGISTERED}",
    ('a' * 64) + '.test',
  ].freeze

  FORWARDED_PORTS = [nil, '', '8443', '443', '80', '0', '65536', '8443, 443', 'abc', '-1', ' 8443 ', "8443\n9"].freeze

  RFC7239 = [nil, 'host=evil.test', "host=#{REGISTERED};proto=http", 'for=a"b;host=evil.test'].freeze

  SCHEMES = %w[https http].freeze

  # Everything this install serves. A rewritten authority must name one.
  def served?(host)
    host == CANONICAL || host == REGISTERED || host == "#{REGISTERED}." ||
      host.end_with?(".#{CANONICAL}") || host == 'xn--never-registered'
  end

  let(:seen) { [] }
  let(:terminal) do
    ->(env) do
      seen << env.dup
      [200, {}, ['ok']]
    end
  end

  let(:chain) do
    rewrite  = described_class.new(terminal)
    strategy = Onetime::Middleware::DomainStrategy.new(rewrite)
    allow(strategy).to receive_messages(
      domains_enabled?: domains_enabled,
      canonical_domain: CANONICAL,
      canonical_domains_parsed: [PublicSuffix.parse(CANONICAL)],
      anchor_domains_parsed: [PublicSuffix.parse(CANONICAL)],
    )
    strip    = Onetime::Middleware::StripForwardedHost.new(strategy)
    Rack::DetectHost.new(strip, logger: Logger.new(IO::NULL))
  end

  let(:domains_enabled) { true }
  let(:custom_domain) { instance_double(Onetime::CustomDomain, identifier: 'domain-abc-123') }

  around do |example|
    original                         = Rack::Request.forwarded_priority
    Rack::Request.forwarded_priority = [:x_forwarded]
    example.run
  ensure
    Rack::Request.forwarded_priority = original
  end

  before do
    allow(described_class).to receive(:enabled?).and_return(true)
    allow(Onetime::CustomDomain).to receive(:from_display_domain) do |name|
      raise StandardError, 'datastore unavailable' if name == 'broken-read.test'

      name.to_s.chomp('.') == REGISTERED ? custom_domain : nil
    end
  end

  def request_env(peer:, host:, xfh: nil, xfp: nil, forwarded: nil, scheme: 'https', extra: {})
    env                           = Rack::MockRequest.env_for("#{scheme}://placeholder.invalid/auth/login")
    env.delete('HTTP_HOST')
    env['HTTP_HOST']              = host unless host.nil?
    env['SERVER_NAME']            = 'origin.internal'
    env['SERVER_PORT']            = '3000'
    env['HTTP_X_FORWARDED_HOST']  = xfh unless xfh.nil?
    env['HTTP_X_FORWARDED_PORT']  = xfp unless xfp.nil?
    env['HTTP_FORWARDED']         = forwarded unless forwarded.nil?
    env.merge(PEERS.fetch(peer)).merge(extra)
  end

  def run(**)
    env = request_env(**)
    chain.call(env)
    seen.last
  end

  def each_case
    PEERS.each_key do |peer|
      HOSTS.each do |host|
        FORWARDED_HOSTS.each do |xfh|
          FORWARDED_PORTS.each do |xfp|
            yield({ peer: peer, host: host, xfh: xfh, xfp: xfp })
          end
        end
      end
    end
  end

  def violations
    found = []
    each_case do |input|
      out     = run(**input)
      problem = yield(input, out)
      found << "#{input.inspect} => #{problem}" if problem
    end
    found
  end

  def report(found)
    return if found.empty?

    raise RSpec::Expectations::ExpectationNotMetError,
      "#{found.size} violating inputs, first 25:\n  #{found.first(25).join("\n  ")}"
  end

  def rewritten?(env)
    env.key?(described_class::ORIGINAL_HTTP_HOST)
  end

  # From a peer that is not a trusted proxy nothing forwarded is read. The
  # one change such a request can see is a doubled Host that resolves to a
  # served host being replaced by that host, which is the Host's own first
  # value and never carries a port.
  it 'takes nothing from the forwarded headers of a peer that is not a trusted proxy' do
    report(
      violations do |input, out|
            next if TRUSTED_PEERS.include?(input[:peer])

            first_value = Rack::DetectHost.normalize_host(input[:host])
            if out.key?('HTTP_X_FORWARDED_PORT')
              "X-Forwarded-Port kept: #{out['HTTP_X_FORWARDED_PORT'].inspect}"
            elsif rewritten?(out) && !(input[:host].to_s.include?(',') && out['HTTP_HOST'] == first_value)
              "rewritten to #{out['HTTP_HOST'].inspect}"
            elsif !rewritten?(out) && out['HTTP_HOST'] != input[:host]
              "HTTP_HOST changed to #{out['HTTP_HOST'].inspect}"
            end
      end,
    )
  end

  it 'never gives Rack a port outside 1..65535, rewritten or not' do
    report(
      violations do |_input, out|
            port = Rack::Request.new(out).port
            next if (1..65_535).cover?(port)

            "port=#{port.inspect} HTTP_HOST=#{out['HTTP_HOST'].inspect} xfp=#{out['HTTP_X_FORWARDED_PORT'].inspect}"
      end,
    )
  end

  it 'keeps X-Forwarded-Port only as one usable port, and never on a rewritten request' do
    report(
      violations do |_input, out|
            next unless out.key?('HTTP_X_FORWARDED_PORT')

            value = out['HTTP_X_FORWARDED_PORT']
            if rewritten?(out)
              "kept #{value.inspect} on a rewritten request"
            elsif !value.strip.match?(/\A[1-9][0-9]{0,4}\z/) || value.to_i > 65_535
              "kept #{value.inspect}"
            end
      end,
    )
  end

  it 'leaves no forwarded authority carrier for the apps, from any peer' do
    found = []
    PEERS.each_key do |peer|
      FORWARDED_HOSTS.each do |xfh|
        RFC7239.each do |forwarded|
          out = run(peer: peer, host: ORIGIN, xfh: xfh, forwarded: forwarded)
          %w[HTTP_X_FORWARDED_HOST HTTP_FORWARDED].each do |key|
            found << "#{peer} xfh=#{xfh.inspect} fwd=#{forwarded.inspect}: #{key} survives" if out.key?(key)
          end
          host = Rack::Request.new(out).host.to_s
          found << "#{peer} xfh=#{xfh.inspect} fwd=#{forwarded.inspect}: host #{host}" if host.include?('evil')
        end
      end
    end
    report(found)
  end

  it 'writes only a plain authority naming a host the install serves' do
    report(
      violations do |_input, out|
            next unless rewritten?(out)

            authority = out['HTTP_HOST']
            match     = authority.match(/\A([a-z0-9.-]+)(?::([1-9][0-9]{0,4}))?\z/)
            if match.nil?
              "authority #{authority.inspect} is not host[:port]"
            elsif !served?(match[1])
              "authority names #{match[1].inspect}, not a served host"
            elsif match[1] != out['onetime.display_domain'] || match[1] != out['SERVER_NAME']
              "authority #{authority.inspect} display=#{out['onetime.display_domain'].inspect} " \
                "server_name=#{out['SERVER_NAME'].inspect}"
            elsif match[2] && !(1..65_535).cover?(match[2].to_i)
              "port #{match[2]} out of range"
            end
      end,
    )
  end

  it 'never lets Rack::Request#host name a host that is neither received in Host nor classified' do
    report(
      violations do |input, out|
            host     = Rack::Request.new(out).host.to_s
            received = Rack::Request.new(out.merge('HTTP_HOST' => input[:host])).host.to_s
            next if host == received
            next if host == out['onetime.display_domain'] && served?(host)

            "request.host=#{host.inspect} received=#{received.inspect} display=#{out['onetime.display_domain'].inspect}"
      end,
    )
  end

  it 'never rewrites an :invalid, unregistered or failed-read host' do
    report(
      violations do |_input, out|
            next unless rewritten?(out)
            next if [:canonical, :subdomain, :custom].include?(out['onetime.domain_strategy'])

            "rewritten with strategy #{out['onetime.domain_strategy'].inspect}"
      end,
    )
  end

  SCHEMES.each do |scheme|
    it "gives Rack one port for #port and #base_url on a rewritten #{scheme} request" do
      found = []
      each_case do |input|
        out = run(**input, scheme: scheme)
        next unless rewritten?(out)

        req      = Rack::Request.new(out)
        url_port = URI.parse(req.base_url).port
        next if url_port == req.port

        found << "#{input.inspect} => base_url=#{req.base_url} port=#{req.port} HTTP_HOST=#{out['HTTP_HOST'].inspect}"
      end
      report(found)
    end
  end

  # For a well-formed forwarded authority, the env the apps receive is the
  # one a proxy that preserves Host would have produced for the same public
  # request.
  describe 'equivalence with a Host-preserving proxy' do
    [REGISTERED, CANONICAL, "www.#{CANONICAL}", "tenant.#{CANONICAL}"].each do |public_host|
      SCHEMES.each do |scheme|
        [nil, '443', '80', '8443'].each do |port|
          default   = { 'https' => '443', 'http' => '80' }.fetch(scheme)
          authority = port.nil? || port == default ? public_host : "#{public_host}:#{port}"

          {
            'port in X-Forwarded-Host' => { xfh: port ? "#{public_host}:#{port}" : public_host, xfp: nil },
            'port in X-Forwarded-Port' => { xfh: public_host, xfp: port },
            'port in both' => { xfh: port ? "#{public_host}:#{port}" : public_host, xfp: port },
          }.each do |shape, headers|
            it "#{scheme} #{authority} (#{shape})" do
              rewriting  = run(peer: :verdict_true, host: ORIGIN, scheme: scheme, **headers)
              preserving = run(peer: :verdict_true, host: authority, scheme: scheme, **headers)

              a = Rack::Request.new(rewriting)
              b = Rack::Request.new(preserving)

              expect([a.host, a.port, a.base_url, a.host_with_port, rewriting['SERVER_NAME'] == a.host])
                .to eq([b.host, b.port, b.base_url, b.host_with_port, true])
              expect(rewriting.values_at('onetime.display_domain', 'onetime.domain_strategy'))
                .to eq(preserving.values_at('onetime.display_domain', 'onetime.domain_strategy'))
            end
          end
        end
      end
    end
  end

  context 'with the domains feature off' do
    let(:domains_enabled) { false }

    it 'rewrites to nothing but the canonical host' do
      report(
        violations do |_input, out|
                next unless rewritten?(out)
                next if Rack::Request.new(out).host == CANONICAL

                "rewritten to #{out['HTTP_HOST'].inspect}"
        end,
      )
    end
  end
end
