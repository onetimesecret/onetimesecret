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

  # Spec-side oracle, written by hand and independent of the code under
  # test: each Host value maps to the hostname host detection takes from it
  # (the first entry of a doubled Host, with any port dropped), or nil when
  # it names no usable DNS hostname.
  HOST_NAMES = {
    ORIGIN => 'origin.internal',
    CANONICAL => CANONICAL,
    REGISTERED => REGISTERED,
    "#{REGISTERED}:8443" => REGISTERED,
    'evil.test' => 'evil.test',
    'evil.test:8443' => 'evil.test',
    "#{REGISTERED}, evil.test" => REGISTERED,
    "evil.test, #{REGISTERED}" => 'evil.test',
    "#{REGISTERED}@evil.test" => nil,
    "evil.test@#{REGISTERED}" => nil,
    "user:pw@#{REGISTERED}" => nil,
    "#{REGISTERED}:pw@evil.test" => nil,
    '10.0.0.7:3000' => nil,
    'localhost:3000' => nil,
    '' => nil,
    nil => nil,
  }.freeze

  HOSTS = HOST_NAMES.keys.freeze

  # A single X-Forwarded-Host value with userinfo ('@') in it: no host is
  # detected for the request, and detection does not continue with Host.
  REFUSED = :refused

  # The same for X-Forwarded-Host from a trusted proxy: the hostname it is
  # selected as, nil when it is not selected and detection continues with
  # Host, or REFUSED. A value with more than one entry is never selected.
  FORWARDED_HOST_NAMES = {
    nil => nil,
    '' => nil,
    REGISTERED => REGISTERED,
    REGISTERED.upcase => REGISTERED,
    # The trailing dot of an FQDN is kept in the detected name.
    "#{REGISTERED}." => "#{REGISTERED}.",
    " #{REGISTERED} " => REGISTERED,
    "#{REGISTERED}:8443" => REGISTERED,
    "#{REGISTERED}:443" => REGISTERED,
    "#{REGISTERED}:80" => REGISTERED,
    "#{REGISTERED}:0" => REGISTERED,
    "#{REGISTERED}:65536" => REGISTERED,
    "#{REGISTERED}:99999" => REGISTERED,
    "#{REGISTERED}:" => REGISTERED,
    "#{REGISTERED}:abc" => REGISTERED,
    "#{REGISTERED}:8443:9" => REGISTERED,
    "#{REGISTERED}:8443/path" => REGISTERED,
    "#{REGISTERED}/path" => nil,
    "#{REGISTERED}?x=1" => nil,
    "#{REGISTERED}#evil.test" => nil,
    "#{REGISTERED}@evil.test" => REFUSED,
    "evil.test@#{REGISTERED}" => REFUSED,
    "user:pw@#{REGISTERED}" => REFUSED,
    "#{REGISTERED}:pw@evil.test" => REFUSED,
    "#{CANONICAL}:8443@evil.test" => REFUSED,
    # URL forms name the URL's host, unless the URL carries userinfo.
    "https://#{REGISTERED}" => REGISTERED,
    "https://#{REGISTERED}:8443/x" => REGISTERED,
    "https://evil.test@#{REGISTERED}/" => REFUSED,
    "https://#{REGISTERED}@evil.test/" => REFUSED,
    "#{REGISTERED}\r\nX-Injected: 1" => nil,
    "#{REGISTERED}\tevil.test" => nil,
    "#{REGISTERED} evil.test" => nil,
    "#{REGISTERED}, evil.test" => nil,
    "evil.test, #{REGISTERED}" => nil,
    "#{REGISTERED}," => nil,
    CANONICAL => CANONICAL,
    "www.#{CANONICAL}" => "www.#{CANONICAL}",
    "tenant.#{CANONICAL}" => "tenant.#{CANONICAL}",
    'evil.test' => 'evil.test',
    'unregistered.test:8443' => 'unregistered.test',
    'broken-read.test' => 'broken-read.test',
    'broken-read.example.net' => 'broken-read.example.net',
    '10.0.0.7' => nil,
    '[::1]:8443' => nil,
    'localhost' => nil,
    'xn--e1afmkfd.xn--p1ai' => 'xn--e1afmkfd.xn--p1ai',
    "-#{REGISTERED}" => nil,
    (('a' * 64) + '.test') => nil,
  }.freeze

  FORWARDED_HOSTS = FORWARDED_HOST_NAMES.keys.freeze

  # Every detected name this install serves, with its classification when
  # the domains feature is on. Any other name is :invalid. Any subdomain of
  # the canonical host classifies :subdomain; these are the two the inputs
  # above can produce, so no other subdomain is accepted here.
  SERVED_STRATEGIES = {
    CANONICAL => :canonical,
    "www.#{CANONICAL}" => :canonical,
    "tenant.#{CANONICAL}" => :subdomain,
    REGISTERED => :custom,
    "#{REGISTERED}." => :custom,
  }.freeze

  FORWARDED_PORTS = [nil, '', '8443', '443', '80', '0', '65536', '8443, 443', 'abc', '-1', ' 8443 ', "8443\n9"].freeze

  RFC7239 = [nil, 'host=evil.test', "host=#{REGISTERED};proto=http", 'for=a"b;host=evil.test'].freeze

  SCHEMES = %w[https http].freeze

  # A rewritten authority must name one of the served names exactly. The
  # FQDN form of the registered domain is in the table because detection
  # keeps the trailing dot and the name still classifies :custom.
  def served?(host)
    SERVED_STRATEGIES.key?(host)
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

  # The broken-read host makes the domain strategy log an error with a full
  # backtrace on every example that reaches it, several thousand times per
  # run. That line is the middleware behaving correctly, not something this
  # spec asserts, so keep it out of the test output.
  before do
    quiet_http_logger = SemanticLogger['HTTP'].tap { |logger| logger.level = :fatal }
    allow(Onetime).to receive(:http_logger).and_return(quiet_http_logger)
    allow(described_class).to receive(:enabled?).and_return(true)
    allow(Onetime::CustomDomain).to receive(:from_display_domain) do |name|
      raise StandardError, 'datastore unavailable' if name == 'broken-read.example.net'

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

  def authority_snapshot(env)
    request = Rack::Request.new(env)
    [env.values_at('HTTP_HOST', 'SERVER_NAME', 'SERVER_PORT', described_class::ORIGINAL_HTTP_HOST),
      request.host, request.port, request.host_with_port, request.base_url]
  end

  def classification_snapshot(env)
    env.values_at(Rack::DetectHost.result_field_name, 'onetime.display_domain',
      'onetime.domain_strategy', Rack::DetectHost.forwarded_authority_field_name,
      'onetime.custom_domain_id')
  end


  # What the oracle tables expect for one matrix input, with the domains
  # feature on: the detected name, the display domain, the classification,
  # and whether the request is rewritten (a served name that the received
  # Host does not already name as one plain host[:port]).
  def expected_for(input)
    forwarded = TRUSTED_PEERS.include?(input[:peer]) ? FORWARDED_HOST_NAMES.fetch(input[:xfh]) : nil
    name      = forwarded == REFUSED ? nil : forwarded || HOST_NAMES.fetch(input[:host])
    strategy  = SERVED_STRATEGIES.fetch(name, :invalid)
    named     = !name.nil? && input[:host].to_s.match?(/\A#{Regexp.escape(name)}(?::[0-9]+)?\z/i)
    {
      detected: name,
      display: name || CANONICAL,
      strategy: strategy,
      rewritten: strategy != :invalid && !named,
    }
  end

  it 'classifies every input as the spec-side oracle expects, rewritten or not' do
    report(
      violations do |input, out|
        expected = expected_for(input)
        actual   = {
          detected: out[Rack::DetectHost.result_field_name],
          display: out['onetime.display_domain'],
          strategy: out['onetime.domain_strategy'],
        }
        next if actual == expected.slice(:detected, :display, :strategy)

        "actual=#{actual.inspect} expected=#{expected.inspect}"
      end,
    )
  end

  # The oracle is the same peer and Host sent with no forwarded headers
  # (including a doubled Host). Asserted: X-Forwarded-Port is gone, and the
  # detected host, display domain, strategy, forwarded authority, custom
  # domain id, HTTP_HOST, SERVER_NAME, SERVER_PORT, the original-Host key
  # and Rack's host, port and base_url all equal the oracle's. The inputs
  # here are X-Forwarded-Host and X-Forwarded-Port only; Forwarded and the
  # scheme carriers are covered under 'forwarded scheme trust' below.
  it 'gives a peer that is not a trusted proxy what its Host alone produces, ' \
     'whatever X-Forwarded-Host and X-Forwarded-Port it sends' do
    baselines = {}
    report(
      violations do |input, out|
        next if TRUSTED_PEERS.include?(input[:peer])

        baseline = baselines[[input[:peer], input[:host]]] ||= run(peer: input[:peer], host: input[:host])
        if out.key?('HTTP_X_FORWARDED_PORT')
          "X-Forwarded-Port kept: #{out['HTTP_X_FORWARDED_PORT'].inspect}"
        elsif classification_snapshot(out) != classification_snapshot(baseline)
          "classification=#{classification_snapshot(out).inspect} baseline=#{classification_snapshot(baseline).inspect}"
        elsif authority_snapshot(out) != authority_snapshot(baseline)
          "authority=#{authority_snapshot(out).inspect} baseline=#{authority_snapshot(baseline).inspect}"
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

  it 'rewrites exactly the inputs the oracle classifies as served and whose Host does not already name that host' do
    report(
      violations do |input, out|
        expected = expected_for(input)
        next if rewritten?(out) == expected[:rewritten]

        "rewritten=#{rewritten?(out)} expected=#{expected.inspect} HTTP_HOST=#{out['HTTP_HOST'].inspect}"
      end,
    )
  end

  describe 'input-specific lookup failures and unregistered hosts' do
    # .test is rejected by PublicSuffix before a lookup; use parseable hosts
    # so the failed-read and absent fixtures actually reach the datastore.
    { 'broken-read.example.net' => :read_failed, 'unregistered.example.net' => :absent }.each do |hostname, state|
      PEERS.each_key do |peer|
        [nil, '443', '8443'].each do |port|
          authority = port ? "#{hostname}:#{port}" : hostname
          shapes = [{ host: authority }]
          shapes << { host: ORIGIN, xfh: authority } if TRUSTED_PEERS.include?(peer)
          shapes.each do |headers|
            it "keeps #{state} #{authority} invalid and preserves Host for #{peer} #{headers.inspect}" do
              out = run(peer: peer, **headers)
              lookup = out[Onetime::CustomDomain::Lookup::ENV_KEY]

              aggregate_failures do
                expect(out[Rack::DetectHost.result_field_name]).to eq(hostname)
                expect(out['onetime.display_domain']).to eq(hostname)
                expect(out['onetime.domain_strategy']).to eq(:invalid)
                expect(Onetime::CustomDomain).to have_received(:from_display_domain).with(hostname)
                expect(lookup).to have_attributes(host: hostname, state: state, record: nil)
                expect(out).not_to have_key('onetime.custom_domain')
                expect(out).not_to have_key('onetime.custom_domain_id')
                expect(out).not_to have_key(described_class::ORIGINAL_HTTP_HOST)
                expect(out['HTTP_HOST']).to eq(headers.fetch(:host))
                expect(out['SERVER_NAME']).to eq('origin.internal')
                expect(out['SERVER_PORT']).to eq('3000')
                expect(authority_snapshot(out)).to eq(authority_snapshot(request_env(peer: peer, host: headers.fetch(:host))))
              end
            end
          end
        end
      end
    end
  end

  describe 'forwarded scheme trust' do
    # Expected schemes for the two pinned families on an origin-http request.
    scheme_cases = [
      [{ 'HTTP_X_FORWARDED_PROTO' => 'https' }, 'https', 'http'],
      [{ 'HTTP_X_FORWARDED_SCHEME' => 'https' }, 'https', 'http'],
      # Rack reads SSL=on before the pinned forwarding family.
      [{ 'HTTP_X_FORWARDED_SSL' => 'on' }, 'https', 'https'],
      [{ 'HTTP_X_FORWARDED_SSL' => 'off' }, 'http', 'http'],
      [{ 'HTTP_X_FORWARDED_SSL' => "on\r\nX-Injected: 1" }, 'http', 'http'],
      [{ 'HTTP_X_FORWARDED_SSL' => 'on', 'HTTP_X_FORWARDED_PROTO' => 'http',
         'HTTP_X_FORWARDED_SCHEME' => 'http', 'HTTP_FORWARDED' => 'host=evil.test;proto=http' }, 'https', 'https'],
      [{ 'HTTP_FORWARDED' => "host=evil.test;proto=https" }, 'http', 'https'],
      [{ 'HTTP_X_FORWARDED_PROTO' => 'http', 'HTTP_X_FORWARDED_SCHEME' => 'https',
         'HTTP_FORWARDED' => 'host=evil.test;proto=https' }, 'http', 'https'],
      [{ 'HTTP_X_FORWARDED_PROTO' => 'https', 'HTTP_X_FORWARDED_SCHEME' => 'http',
         'HTTP_FORWARDED' => 'host=evil.test;proto=http' }, 'https', 'http'],
      [{ 'HTTP_X_FORWARDED_PROTO' => 'javascript', 'HTTP_X_FORWARDED_SCHEME' => 'javascript',
         'HTTP_FORWARDED' => 'host=evil.test;proto=javascript' }, 'http', 'http'],
      # Rack resolves this proto despite the malformed for= quoting. Whole
      # header deletion must still remove its hostile authority.
      [{ 'HTTP_FORWARDED' => 'for=a"b;host=evil.test;proto=https' }, 'http', 'https'],
    ]

    [:x_forwarded, :forwarded].each_with_index do |family, index|
      it "ignores untrusted scheme carriers under #{family} (PHR-ADV-0#{index + 1})" do
        Rack::Request.forwarded_priority = [family]
        found = []
        (PEERS.keys - TRUSTED_PEERS).each do |peer|
          SCHEMES.each do |scheme|
            [REGISTERED, "#{REGISTERED}, evil.test", ORIGIN].each do |host|
              baseline = run(peer: peer, host: host, scheme: scheme, extra: { 'HTTPS' => nil })
              scheme_cases.each do |headers, _x_scheme, _f_scheme|
                out = run(peer: peer, host: host, scheme: scheme, xfh: "#{REGISTERED}:443", xfp: '8443',
                  extra: headers.merge('HTTPS' => nil))
                surviving = headers.keys.select { |key| out.key?(key) }
                unless surviving.empty?
                  found << "peer=#{peer} host=#{host.inspect} scheme=#{scheme} headers=#{headers.inspect}: " \
                    "untrusted carriers survive=#{surviving.inspect}"
                end
                actual = [classification_snapshot(out), authority_snapshot(out), Rack::Request.new(out).scheme, out['rack.url_scheme']]
                expected = [classification_snapshot(baseline), authority_snapshot(baseline), Rack::Request.new(baseline).scheme, baseline['rack.url_scheme']]
                next if actual == expected

                found << "peer=#{peer} host=#{host.inspect} scheme=#{scheme} headers=#{headers.inspect}: " \
                  "actual=#{actual.inspect} baseline=#{expected.inspect}"
              end
            end
          end
        end
        report(found)
      end

      scheme_cases.each do |headers, x_scheme, f_scheme|
        TRUSTED_PEERS.each do |peer|
          it "uses the #{family} scheme for trusted #{peer} #{headers.inspect}" do
            Rack::Request.forwarded_priority = [family]
            expected_scheme = family == :x_forwarded ? x_scheme : f_scheme
            out = run(peer: peer, host: ORIGIN, scheme: 'http', xfh: "#{REGISTERED}:443", xfp: '8443', extra: headers)
            request = Rack::Request.new(out)

            aggregate_failures do
              expect(out[Rack::DetectHost.result_field_name]).to eq(REGISTERED)
              expect(out.values_at('onetime.display_domain', 'onetime.domain_strategy')).to eq([REGISTERED, :custom])
              expect(request.scheme).to eq(expected_scheme)
              expect(out['HTTP_HOST']).to eq(expected_scheme == 'https' ? REGISTERED : "#{REGISTERED}:443")
              expect(request.host).to eq(REGISTERED)
              expect(request.port).to eq(443)
              expect(request.base_url).to eq("#{expected_scheme}://#{out['HTTP_HOST']}")
              expect(URI.parse(request.base_url).port).to eq(request.port)
              expect(out).not_to have_key('HTTP_FORWARDED')
              expect(out).not_to have_key('HTTP_X_FORWARDED_HOST')
              expect(out).not_to have_key('HTTP_X_FORWARDED_PORT')
            end
          end
        end
      end
    end

    PEERS.each_key do |peer|
      it "does not persist a Forwarded proto downgrade of origin TLS for #{peer}" do
        Rack::Request.forwarded_priority = [:forwarded]
        out = run(peer: peer, host: "#{REGISTERED}, evil.test", scheme: 'https',
          forwarded: 'host=evil.test;proto=http', extra: { 'HTTPS' => nil })
        request = Rack::Request.new(out)

        expect(out['rack.url_scheme']).to eq('https')
        expect(request.scheme).to eq('https')
        expect(request.base_url).to eq("https://#{REGISTERED}")
        expect(request.port).to eq(443)
      end
    end
  end

  # X-Forwarded-Proto as an adversarial input. This is a separate, bounded
  # product and not a dimension of each_case: every peer x three origin
  # connections x the proto values x the request shapes below. It does not
  # vary X-Forwarded-Scheme, X-Forwarded-SSL or Forwarded (see 'forwarded
  # scheme trust' above), and it holds Rack's forwarded priority at
  # [:x_forwarded], the value the app pins.
  #
  # StripForwardedHost is the first middleware in this chain to decide
  # scheme trust: it deletes X-Forwarded-Proto unless the peer is a trusted
  # proxy. What it keeps is read by Rack::Request#scheme, after HTTPS=on.
  # In what it keeps, a ws entry is rewritten to http and a wss entry to
  # https: Rack has no default port for either.
  describe 'X-Forwarded-Proto values across request shapes' do
    # Value => the scheme the apps get from it, or nil when it names none.
    # Rack splits the value on commas, spaces and tabs and takes the last
    # entry that is exactly https, http, wss or ws; wss counts as https and
    # ws as http.
    protos = {
      nil => nil,
      '' => nil,
      'https' => 'https',
      'http' => 'http',
      'HTTPS' => nil,
      ' https ' => 'https',
      'https, http' => 'http',
      'http, https' => 'https',
      'https,' => 'https',
      "http\thttps" => 'https',
      'javascript' => nil,
      'javascript, https' => 'https',
      'https, javascript' => 'https',
      'https://' => nil,
      'on' => nil,
      "https\r\nX-Injected: 1" => nil,
      'wss' => 'https',
      'ws' => 'http',
      'https, wss' => 'https',
      'wss, http' => 'http',
      'http, ws' => 'http',
      "ws\twss" => 'https',
      'javascript, wss' => 'https',
      'WSS' => nil,
      'wss://' => nil,
    }.freeze

    # The values a trusted proxy's header is rewritten to. Any other value
    # reaches the apps as it arrived.
    kept_as = {
      'wss' => 'https',
      'ws' => 'http',
      'https, wss' => 'https, https',
      'wss, http' => 'https, http',
      'http, ws' => 'http, http',
      "ws\twss" => "http\thttps",
      'javascript, wss' => 'javascript, https',
    }.freeze

    # Origin connection => [request_env scheme, extra env, scheme without a
    # forwarded one, whether a forwarded scheme can replace it]. HTTPS=on is
    # read before any forwarded scheme; rack.url_scheme alone is read after.
    origins = {
      'plain http' => ['http', {}, 'http', true],
      'TLS with HTTPS=on' => ['https', {}, 'https', false],
      'TLS with rack.url_scheme only' => ['https', { 'HTTPS' => nil }, 'https', true],
    }.freeze

    # Request headers => the public port a trusted proxy forwarded, if any.
    shapes = {
      { host: ORIGIN, xfh: REGISTERED } => nil,
      { host: ORIGIN, xfh: "#{REGISTERED}:8443" } => 8443,
      { host: ORIGIN, xfh: "#{REGISTERED}:443" } => 443,
      { host: ORIGIN, xfh: "#{REGISTERED}:80" } => 80,
      { host: ORIGIN, xfh: REGISTERED, xfp: '8443' } => 8443,
      { host: ORIGIN, xfh: CANONICAL, xfp: '443' } => 443,
      { host: "#{REGISTERED}, evil.test", xfh: "#{REGISTERED}:8443" } => 8443,
      # Not rewritten for any peer.
      { host: "#{REGISTERED}:8443" } => nil,
      { host: ORIGIN } => nil,
      { host: ORIGIN, xfh: 'evil.test', xfp: '8443' } => nil,
    }.freeze

    default_ports = { 'https' => 443, 'http' => 80 }.freeze

    def scheme_snapshot(env)
      request = Rack::Request.new(env)
      [request.scheme, request.ssl?, env['rack.url_scheme']]
    end

    (PEERS.keys - TRUSTED_PEERS).each do |peer|
      it "gives #{peer} the scheme, classification and authority of the same Host sent alone" do
        found = []
        origins.each do |origin, (env_scheme, extra, _scheme, _replaceable)|
          shapes.each_key do |headers|
            baseline = run(peer: peer, host: headers[:host], scheme: env_scheme, extra: extra)
            protos.each_key do |proto|
              forwarded = proto.nil? ? {} : { 'HTTP_X_FORWARDED_PROTO' => proto }
              out       = run(peer: peer, scheme: env_scheme, extra: extra.merge(forwarded), **headers)
              actual    = [out.key?('HTTP_X_FORWARDED_PROTO'), scheme_snapshot(out),
                           classification_snapshot(out), authority_snapshot(out)]
              expected  = [false, scheme_snapshot(baseline),
                           classification_snapshot(baseline), authority_snapshot(baseline)]
              next if actual == expected

              found << "#{origin} #{headers.inspect} proto=#{proto.inspect}: " \
                       "actual=#{actual.inspect} baseline=#{expected.inspect}"
            end
          end
        end
        report(found)
      end
    end

    TRUSTED_PEERS.each do |peer|
      it "gives the apps the scheme #{peer} forwards and the authority expected under that scheme" do
        found = []
        origins.each do |origin, (env_scheme, extra, origin_scheme, replaceable)|
          shapes.each do |headers, public_port|
            oracle  = expected_for(peer: peer, host: headers[:host], xfh: headers[:xfh])
            without = run(peer: peer, scheme: env_scheme, extra: extra, **headers)
            protos.each do |proto, forwarded_scheme|
              forwarded = proto.nil? ? {} : { 'HTTP_X_FORWARDED_PROTO' => proto }
              out       = run(peer: peer, scheme: env_scheme, extra: extra.merge(forwarded), **headers)
              request   = Rack::Request.new(out)
              scheme    = replaceable && forwarded_scheme ? forwarded_scheme : origin_scheme
              default   = default_ports[scheme]

              if oracle[:rewritten]
                name      = oracle[:detected]
                authority = public_port && public_port != default ? "#{name}:#{public_port}" : name
                port      = public_port || default
              else
                authority  = headers[:host]
                name, port = authority.split(':')
                port       = port.to_i
              end
              base_url = port == default ? "#{scheme}://#{name}" : "#{scheme}://#{name}:#{port}"

              # The apps get http or https whatever the proxy sent, so
              # #port and the port of #base_url are one Integer in every
              # case, and never SERVER_PORT's on a rewritten request.
              actual   = [out['HTTP_X_FORWARDED_PROTO'], request.scheme, request.ssl?, rewritten?(out),
                          out['HTTP_HOST'], request.host, request.port, request.base_url,
                          URI.parse(request.base_url).port, classification_snapshot(out)]
              expected = [kept_as.fetch(proto, proto), scheme, scheme == 'https', oracle[:rewritten],
                          authority, name, port, base_url,
                          port, classification_snapshot(without)]
              next if actual == expected

              found << "#{origin} #{headers.inspect} proto=#{proto.inspect}: " \
                       "actual=#{actual.inspect} expected=#{expected.inspect}"
            end
          end
        end
        report(found)
      end
    end
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
