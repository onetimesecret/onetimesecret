# spec/unit/onetime/initializers/configure_familia_spec.rb
#
# frozen_string_literal: true

# Redis/Valkey transport check at boot (RISK-2026-08-14-L07).
#
# ConfigureFamilia classifies the datastore URI before it hands it to Familia:
#
#   redis.require_tls true,  URI not :tls       -> Onetime::Problem, boot stops
#   redis.require_tls false, :remote_plaintext  -> one warning, boot continues
#   redis.require_tls false, :private_plaintext -> one info line (a compose
#                                                  service name like `maindb`)
#   otherwise                                   -> silent
#
# The classifier and the check are pure class methods, tested directly. The
# #execute examples stop at the check (a raise, or a stub that raises), so
# no example assigns Familia.uri or the encryption keys.

require 'spec_helper'

# rubocop:disable-next RSpec/SpecFilePathFormat -- file name matches configure_familia.rb
RSpec.describe Onetime::Initializers::ConfigureFamilia, :aggregate_failures do
  describe '.redis_transport' do
    {
      'rediss://:pw@db.example.com:6380/0' => :tls,
      'valkeys://db.example.com:6380/0' => :tls,
      'REDISS://db.example.com:6380/0' => :tls,
      'redis://127.0.0.1:2163/0' => :local_plaintext,
      'valkey://127.0.0.1:2163/0' => :local_plaintext,
      'redis://127.9.9.9:6379' => :local_plaintext,
      'redis://:pw@localhost:6379' => :local_plaintext,
      'redis://[::1]:6379/0' => :local_plaintext,
      'unix:///var/run/valkey.sock' => :local_plaintext,
      # Single-label names (compose / k8s services) and private, CGNAT and
      # link-local literals: a private network, reported at info.
      'redis://maindb:5212/0?timeout=5' => :private_plaintext,
      'redis://:pw@valkey:6379/0' => :private_plaintext,
      'redis://10.0.0.5:6379/0' => :private_plaintext,
      'redis://172.16.4.2:6379/0' => :private_plaintext,
      'redis://192.168.1.20:6379/0' => :private_plaintext,
      'redis://100.64.0.7:6379/0' => :private_plaintext,
      'redis://169.254.10.1:6379/0' => :private_plaintext,
      'redis://[fd12:3456::1]:6379/0' => :private_plaintext,
      'redis://[fe80::1]:6379/0' => :private_plaintext,
      'redis://[::ffff:10.0.0.5]:6379/0' => :private_plaintext,
      # Dotted hostnames and public literals: warned.
      'redis://db.example.com:6379/0' => :remote_plaintext,
      'redis://maindb.:6379/0' => :remote_plaintext,
      'redis://100.128.0.1:6379/0' => :remote_plaintext,
      'redis://8.8.8.8:6379/0' => :remote_plaintext,
      'redis://[2606:4700::1]:6379/0' => :remote_plaintext,
      'redis://0.0.0.0:6379/0' => :remote_plaintext,
      'redis://localhost.attacker.example:6379' => :remote_plaintext,
      # SEC-B04: numeric host forms the resolver reads as IPv4 (134744072 and
      # 0x8080808 are 8.8.8.8) are never single-label names.
      'redis://134744072:6379/0' => :remote_plaintext,
      'redis://0x8080808:6379/0' => :remote_plaintext,
      'redis://valkey_1:6379/0' => :private_plaintext,
      # SEC-B04: URI::Valkey#conf merges query parameters over the URI's host,
      # and redis-client takes `path` (a unix socket) over `host`. The graded
      # host is the one the client connects to.
      'redis://127.0.0.1/0?host=db.example.com' => :remote_plaintext,
      'redis://127.0.0.1/0?timeout=5&host=maindb' => :private_plaintext,
      'redis://db.example.com/0?host=127.0.0.1' => :local_plaintext,
      'redis://db.example.com/0?path=/var/run/valkey.sock' => :local_plaintext,
      'redis://127.0.0.1/0?host=a.example&host=b.example' => :remote_plaintext,
      'rediss://127.0.0.1:6380/0?host=db.example.com' => :tls,
    }.each do |uri, expected|
      it "classifies #{uri} as #{expected}" do
        expect(described_class.redis_transport(uri)).to eq(expected)
      end
    end

    # URI::Valkey#conf merges query parameters over the scheme-derived
    # `ssl:`, and a bare `?ssl` sets it to nil — plaintext on a rediss:// URI.
    it 'never reports :tls when an ssl query parameter could override the scheme' do
      expect(described_class.redis_transport('rediss://db.example.com:6380/0?ssl')).to eq(:remote_plaintext)
      expect(described_class.redis_transport('rediss://127.0.0.1:6380/0?timeout=5&ssl=true')).to eq(:local_plaintext)
    end

    it 'treats a URI that does not parse as remote plaintext' do
      expect(described_class.redis_transport('redis://user:p#w@db host:6379')).to eq(:remote_plaintext)
    end
  end

  describe '.redis_require_tls?' do
    it 'accepts a boolean true or the string true, nothing else' do
      results = [true, 'true', ' TRUE ', false, nil, 'false', 'yes', '1'].map do |value|
        described_class.redis_require_tls?(value)
      end

      expect(results).to eq([true, true, true, false, false, false, false, false])
    end
  end

  describe '.check_redis_transport!' do
    let(:logger) { instance_double(SemanticLogger::Logger, warn: nil, info: nil) }
    let(:password) { 's3cr3t-datastore-pass' }

    context 'when TLS is required' do
      it 'raises for a plaintext remote URI without exposing the password' do
        expect do
          described_class.check_redis_transport!(
            "redis://:#{password}@db.example.com:6379/0", require_tls: true, logger: logger
          )
        end.to raise_error(Onetime::Problem) { |error|
          expect(error.message).to include('require_tls', 'rediss://')
          expect(error.message).not_to include(password)
        }
      end

      it 'raises for plaintext to a loopback or private host too' do
        %w[
          redis://127.0.0.1:6379/0
          redis://maindb:6379/0
          redis://10.0.0.5:6379/0
          redis://db.example.com/0?host=127.0.0.1
          redis://db.example.com/0?path=/var/run/valkey.sock
        ].each do |uri|
          expect { described_class.check_redis_transport!(uri, require_tls: true, logger: logger) }
            .to raise_error(Onetime::Problem)
        end
      end

      it 'raises when an ssl query parameter makes the scheme unreliable' do
        expect do
          described_class.check_redis_transport!('rediss://db.example.com:6380/0?ssl', require_tls: true, logger: logger)
        end.to raise_error(Onetime::Problem)
      end

      it 'passes a TLS URI silently' do
        result = described_class.check_redis_transport!(
          "rediss://:#{password}@db.example.com:6380/0", require_tls: true, logger: logger
        )

        expect(result).to eq(:tls)
        expect(logger).not_to have_received(:warn)
      end
    end

    context 'when TLS is not required' do
      it 'warns once for a plaintext remote URI, redacting userinfo and query' do
        result = described_class.check_redis_transport!(
          "redis://:#{password}@db.example.com:6379/0?password=#{password}", require_tls: false, logger: logger
        )

        expect(result).to eq(:remote_plaintext)
        expect(logger).to have_received(:warn).once do |message|
          expect(message).to include('[configure_familia]', 'db.example.com', 'VALKEY_REQUIRE_TLS=true')
          expect(message).not_to include(password)
        end
      end

      it 'stays silent for a loopback URI' do
        described_class.check_redis_transport!('redis://127.0.0.1:2163/0', require_tls: false, logger: logger)

        expect(logger).not_to have_received(:warn)
        expect(logger).not_to have_received(:info)
      end

      it 'reports a private-network host at info, not warn, redacting the password' do
        result = described_class.check_redis_transport!(
          "redis://:#{password}@maindb:5212/0", require_tls: false, logger: logger
        )

        expect(result).to eq(:private_plaintext)
        expect(logger).not_to have_received(:warn)
        expect(logger).to have_received(:info).once do |message|
          expect(message).to include('[configure_familia]', 'maindb', 'private network')
          expect(message).not_to include(password)
        end
      end

      it 'stays silent for a TLS URI' do
        described_class.check_redis_transport!('rediss://db.example.com:6380/0', require_tls: false, logger: logger)

        expect(logger).not_to have_received(:warn)
      end
    end
  end

  describe '#execute' do
    subject(:initializer) { described_class.new }

    # Port 2163 satisfies the test-environment datastore guard that runs
    # before the transport check.
    let(:plaintext_uri) { 'redis://127.0.0.1:2163/0' }
    let(:sentinel) { Class.new(StandardError) }

    def stub_conf(redis)
      allow(OT).to receive(:conf).and_return(
        'site' => { 'secret' => 'a' * 64 },
        'redis' => redis,
      )
    end

    before { allow(Familia).to receive(:uri=) }

    it 'refuses to boot before configuring Familia when TLS is required and absent' do
      stub_conf('uri' => plaintext_uri, 'require_tls' => true)

      expect { initializer.execute({}) }.to raise_error(Onetime::Problem, /require_tls/)
      expect(Familia).not_to have_received(:uri=)
    end

    it 'passes the configured URI and an absent require_tls (false) to the check' do
      stub_conf('uri' => plaintext_uri)
      allow(described_class).to receive(:check_redis_transport!).and_raise(sentinel)

      expect { initializer.execute({}) }.to raise_error(sentinel)
      expect(described_class).to have_received(:check_redis_transport!).with(plaintext_uri, require_tls: false)
      expect(Familia).not_to have_received(:uri=)
    end
  end
end
