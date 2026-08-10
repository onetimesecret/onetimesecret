# spec/unit/onetime/config/admin_allowed_hosts_spec.rb
#
# frozen_string_literal: true

# #4062: an explicitly set ADMIN_ALLOWED_HOSTS that names nothing the admin
# host gate could ever match aborts boot.
#
# The validator is driven DIRECTLY with an explicit raw argument rather than
# through a booted OT.conf, the same way spec/unit/onetime/config/
# link_domains_spec.rb drives validate_link_domains!. Reproducing these
# postures through a real boot would mean setting ENV['ADMIN_ALLOWED_HOSTS']
# and re-running the whole ERB+YAML load per case. Driving the pure helper is
# what makes the criterion testable; the wiring into raise_concerns is pinned
# separately below so deleting the call site is still caught.
#
# NOTE THE POLARITY, and do not "harmonize" it with #4063's LINK_DOMAINS:
#
#   validate_link_domains!        — EMPTY is the error. An empty pool silently
#                                   becomes the canonical domain, i.e. the
#                                   picker offers the internal platform host
#                                   LINK_DOMAINS exists to hide.
#   validate_admin_allowed_hosts! — EMPTY is the SAFE DEFAULT (the host gate
#                                   falls back to the canonical anchors).
#                                   NON-EMPTY-but-unenforceable is the error,
#                                   because before #4062 that config disabled
#                                   the gate and served /colonel on every
#                                   hostname — failing open on a typo.
#
# Both checks implement one rule: an operator who typed something either gets
# what they meant or gets told. They look opposite because the safe fallback
# is opposite. See the comments on both methods before changing either.
#
# Run with:
#   bundle exec rspec spec/unit/onetime/config/admin_allowed_hosts_spec.rb

require 'spec_helper'

RSpec.describe Onetime::Config, 'ADMIN_ALLOWED_HOSTS validation (#4062)' do
  describe '.validate_admin_allowed_hosts!' do
    # Posture 1: unset / empty. The gate falls back to the canonical anchors
    # and self-disables on a localhost or bare-IP install. Nothing to refuse.
    context 'when ADMIN_ALLOWED_HOSTS is unset or empty' do
      it 'accepts nil — the canonical anchor fallback' do
        expect { described_class.validate_admin_allowed_hosts!(nil) }.not_to raise_error
      end

      it 'accepts an empty list' do
        expect { described_class.validate_admin_allowed_hosts!([]) }.not_to raise_error
      end

      it 'accepts a list of only blanks (the shape ERB renders for a blank value)' do
        expect { described_class.validate_admin_allowed_hosts!(['', '   ']) }.not_to raise_error
      end
    end

    # Posture 2: the documented escape hatch. The middleware WARNs; boot
    # proceeds, because turning the gate off is a deliberate, supported choice.
    context 'when ADMIN_ALLOWED_HOSTS is the `*` escape hatch' do
      it 'accepts a bare `*`' do
        expect { described_class.validate_admin_allowed_hosts!(['*']) }.not_to raise_error
      end

      it 'accepts a padded `*`' do
        expect { described_class.validate_admin_allowed_hosts!(['  *  ']) }.not_to raise_error
      end

      it 'accepts `*` beside blank entries' do
        expect { described_class.validate_admin_allowed_hosts!(['', '*']) }.not_to raise_error
      end
    end

    # Posture 3: a routable hostname. The ordinary configured case.
    context 'when ADMIN_ALLOWED_HOSTS names a routable hostname' do
      it 'accepts a single host' do
        expect { described_class.validate_admin_allowed_hosts!(['admin.example.com']) }.not_to raise_error
      end

      it 'accepts several hosts' do
        expect { described_class.validate_admin_allowed_hosts!(%w[admin.example.com ops.example.net]) }
          .not_to raise_error
      end

      it 'accepts an entry carrying a port, scheme or trailing dot' do
        expect { described_class.validate_admin_allowed_hosts!(['HTTPS://Admin.Example.COM:8443/']) }
          .not_to raise_error
        expect { described_class.validate_admin_allowed_hosts!(['admin.example.com.']) }.not_to raise_error
      end

      it 'accepts the punycode form of an internationalized domain' do
        expect { described_class.validate_admin_allowed_hosts!(['xn--bcher-kva.example']) }.not_to raise_error
      end

      # Partial failure is not a boot error: the middleware drops the bad entry
      # with a WARN and the gate still has a host to enforce.
      it 'accepts a list that mixes an unusable entry with a routable one' do
        expect { described_class.validate_admin_allowed_hosts!(['127.0.0.1', 'admin.example.com']) }
          .not_to raise_error
      end
    end

    # Posture 4: `*` mixed with names. The `*` is dropped (it is only honored
    # as the sole entry) and the names are enforced, so there is something to
    # enforce and boot proceeds.
    context 'when ADMIN_ALLOWED_HOSTS mixes `*` with a named host' do
      it 'accepts the list' do
        expect { described_class.validate_admin_allowed_hosts!(['*', 'admin.example.com']) }.not_to raise_error
      end
    end

    # Posture 5: set, but nothing survives classification. THE security case.
    # Pre-#4062 this disabled the gate — serving /colonel on every hostname
    # from a config whose plain intent was to restrict it.
    context 'when ADMIN_ALLOWED_HOSTS names nothing enforceable' do
      it 'raises for a bare IPv4 literal (never a detected host)' do
        expect { described_class.validate_admin_allowed_hosts!(['127.0.0.1']) }
          .to raise_error(Onetime::ConfigError)
      end

      it 'raises for a public IPv4 literal too — no IP is ever a detected host' do
        expect { described_class.validate_admin_allowed_hosts!(['203.0.113.9']) }
          .to raise_error(Onetime::ConfigError)
      end

      it 'raises for localhost forms' do
        expect { described_class.validate_admin_allowed_hosts!(%w[localhost localhost.localdomain]) }
          .to raise_error(Onetime::ConfigError)
      end

      it 'raises for a wildcard PATTERN — there is no glob matching, so it matches nothing' do
        expect { described_class.validate_admin_allowed_hosts!(['*.example.com']) }
          .to raise_error(Onetime::ConfigError)
      end

      it 'raises for a non-ASCII (U-label) hostname — no IDN library ships here' do
        expect { described_class.validate_admin_allowed_hosts!(['bücher.example']) }
          .to raise_error(Onetime::ConfigError)
      end

      it 'raises when no entry in a multi-entry list survives' do
        expect { described_class.validate_admin_allowed_hosts!(['127.0.0.1', '*.example.com', 'localhost']) }
          .to raise_error(Onetime::ConfigError)
      end
    end

    # The message is the whole point of failing loud: it has to name the
    # setting, the offending entries, the reason, and every way out.
    describe 'the error message' do
      subject(:raise_it) { -> { described_class.validate_admin_allowed_hosts!(['127.0.0.1', '*.example.com']) } }

      it 'names the env var so the operator can find the setting' do
        expect(&raise_it).to raise_error(Onetime::ConfigError, /ADMIN_ALLOWED_HOSTS/)
      end

      it 'names the config path too' do
        expect(&raise_it).to raise_error(Onetime::ConfigError, /site\.admin\.allowed_hosts/)
      end

      it 'echoes every offending entry so the operator can spot the typo' do
        expect(&raise_it).to raise_error(Onetime::ConfigError, /127\.0\.0\.1/)
        expect(&raise_it).to raise_error(Onetime::ConfigError, /\*\.example\.com/)
      end

      it 'gives the reason per entry, in the operator vocabulary' do
        expect(&raise_it).to raise_error(Onetime::ConfigError, /not a routable hostname/)
        expect(&raise_it).to raise_error(Onetime::ConfigError, /wildcard patterns are not supported/)
      end

      it 'states the consequence of the config as written' do
        expect(&raise_it).to raise_error(Onetime::ConfigError, %r{/colonel and /api/colonel})
      end

      it 'offers the escape hatch by name' do
        expect(&raise_it).to raise_error(Onetime::ConfigError, /\*/)
      end

      it 'tells the non-ASCII operator to supply punycode' do
        expect { described_class.validate_admin_allowed_hosts!(['bücher.example']) }
          .to raise_error(Onetime::ConfigError, /punycode|xn--/)
      end
    end
  end

  # The helper is only useful if boot actually calls it. A spec that drives
  # validate_admin_allowed_hosts! alone stays green if the call site in
  # raise_concerns is deleted, so pin the wiring separately.
  describe '.raise_concerns wiring' do
    # The minimum conf that reaches the admin-hosts check: a global secret and
    # a truemail block. site.admin is omitted entirely when :unset, which is
    # the shape of a config that predates the key.
    def conf_with(allowed_hosts)
      site = { 'secret' => 'a-test-secret' }
      site['admin'] = { 'allowed_hosts' => allowed_hosts } unless allowed_hosts == :unset

      {
        'site' => site,
        'mail' => { 'truemail' => {} },
      }
    end

    it 'aborts boot when ADMIN_ALLOWED_HOSTS names nothing enforceable' do
      expect { described_class.raise_concerns(conf_with(['127.0.0.1'])) }
        .to raise_error(Onetime::ConfigError, /ADMIN_ALLOWED_HOSTS/)
    end

    it 'aborts boot on a wildcard pattern' do
      expect { described_class.raise_concerns(conf_with(['*.example.com'])) }
        .to raise_error(Onetime::ConfigError, /ADMIN_ALLOWED_HOSTS/)
    end

    it 'boots when the site.admin block is absent entirely' do
      expect { described_class.raise_concerns(conf_with(:unset)) }.not_to raise_error
    end

    it 'boots when ADMIN_ALLOWED_HOSTS is empty (the canonical anchor fallback)' do
      expect { described_class.raise_concerns(conf_with([])) }.not_to raise_error
    end

    it 'boots when ADMIN_ALLOWED_HOSTS names a routable hostname' do
      expect { described_class.raise_concerns(conf_with(['admin.example.com'])) }.not_to raise_error
    end

    it 'boots on the `*` escape hatch' do
      expect { described_class.raise_concerns(conf_with(['*'])) }.not_to raise_error
    end

    # The admin check must not depend on the domains feature being on: the
    # surfaces exist in every posture, and a self-hosted install with
    # features.domains.enabled=false is exactly where a typo goes unnoticed.
    it 'aborts even when features.domains is absent from the config' do
      conf = conf_with(['127.0.0.1'])
      expect(conf).not_to have_key('features')
      expect { described_class.raise_concerns(conf) }.to raise_error(Onetime::ConfigError, /ADMIN_ALLOWED_HOSTS/)
    end
  end

  # One classifier, one answer. Onetime::Config refuses to boot exactly when
  # Onetime::Middleware::AdminNetworkIsolation would construct itself with an
  # active gate and an EMPTY allowlist (deny both surfaces). If these two ever
  # disagreed the app would either boot into a config the middleware then
  # refuses to serve, or refuse to boot on a config it would have served.
  #
  # Asserted through the shared classifier rather than by booting a middleware
  # (that lives in try/unit/middleware/admin_network_isolation_try.rb), so this
  # stays a pure unit spec.
  describe 'agreement with the middleware backstop' do
    let(:classifier) { Onetime::Utils::AdminHostAllowlist }

    def refuses_boot?(raw)
      described_class.validate_admin_allowed_hosts!(raw)
      false
    rescue Onetime::ConfigError
      true
    end

    {
      nil => false,
      []                                => false,
      ['*']                             => false,
      ['admin.example.com']             => false,
      ['*', 'admin.example.com']        => false,
      ['127.0.0.1', 'admin.example.com'] => false,
      ['127.0.0.1']                     => true,
      ['*.example.com']                 => true,
      ['bücher.example']                => true,
      %w[localhost ::1]                 => true,
    }.each do |raw, expected|
      it "agrees on #{raw.inspect}: refuses_boot=#{expected}" do
        expect(refuses_boot?(raw)).to eq(expected)
        expect(classifier.classify(raw).unenforceable?).to eq(expected)
      end
    end
  end
end
