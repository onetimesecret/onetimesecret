# spec/unit/onetime/config/admin_allowed_hosts_spec.rb
#
# frozen_string_literal: true

# #4062: an explicitly set ADMIN_ALLOWED_HOSTS that names nothing the admin
# host gate could ever match is announced at boot with a WARN.
#
# The check is driven DIRECTLY with an explicit raw argument rather than
# through a booted OT.conf, the same way spec/unit/onetime/config/
# link_domains_spec.rb drives validate_link_domains!. Reproducing these
# postures through a real boot would mean setting ENV['ADMIN_ALLOWED_HOSTS']
# and re-running the whole ERB+YAML load per case. Driving the pure helper is
# what makes the criterion testable; the wiring into raise_concerns is pinned
# separately below so deleting the call site is still caught.
#
# WARN, NOT RAISE — and the asymmetry with #4063's LINK_DOMAINS is deliberate:
#
#   validate_link_domains!       — RAISES. An empty or unparseable pool has no
#                                  fail-closed runtime backstop: it silently
#                                  becomes the canonical domain, i.e. the
#                                  picker offers the internal platform host
#                                  LINK_DOMAINS exists to hide. Nothing
#                                  downstream can recover the intent.
#   check_admin_allowed_hosts    — WARNS. AdminNetworkIsolation already returns
#                                  an ACTIVE gate with an EMPTY allowlist for
#                                  exactly this config and 404s both admin
#                                  surfaces, so the over-exposure this check
#                                  exists to prevent cannot happen either way.
#                                  Aborting the boot would take down the public
#                                  site, the API and the health endpoints over
#                                  an admin-console-only typo (e.g. an
#                                  ADMIN_ALLOWED_HOSTS=10.0.0.0/8 mixup with the
#                                  adjacent ADMIN_ALLOWED_CIDRS key).
#
# Both checks implement one rule: an operator who typed something either gets
# what they meant or gets told. See the comments on both methods before
# changing either.
#
# Run with:
#   bundle exec rspec spec/unit/onetime/config/admin_allowed_hosts_spec.rb

require 'spec_helper'

RSpec.describe Onetime::Config, 'ADMIN_ALLOWED_HOSTS validation (#4062)' do
  # Every example asserts on OT.lw, so nothing here writes to the real boot log.
  # `allow` (not `expect`) by default: the silent postures assert absence.
  before { allow(OT).to receive(:lw) }

  describe '.check_admin_allowed_hosts' do
    # Posture 1: unset / empty. The gate falls back to the canonical anchors
    # and self-disables on a localhost or bare-IP install. Nothing to say.
    context 'when ADMIN_ALLOWED_HOSTS is unset or empty' do
      it 'says nothing for nil — the canonical anchor fallback' do
        described_class.check_admin_allowed_hosts(nil)
        expect(OT).not_to have_received(:lw)
      end

      it 'says nothing for an empty list' do
        described_class.check_admin_allowed_hosts([])
        expect(OT).not_to have_received(:lw)
      end

      it 'says nothing for a list of only blanks (the shape ERB renders for a blank value)' do
        described_class.check_admin_allowed_hosts(['', '   '])
        expect(OT).not_to have_received(:lw)
      end
    end

    # Posture 2: the documented escape hatch. The middleware WARNs about the
    # gate being off; the boot check has nothing to add.
    context 'when ADMIN_ALLOWED_HOSTS is the `*` escape hatch' do
      it 'accepts a bare `*`' do
        described_class.check_admin_allowed_hosts(['*'])
        expect(OT).not_to have_received(:lw)
      end

      it 'accepts a padded `*`' do
        described_class.check_admin_allowed_hosts(['  *  '])
        expect(OT).not_to have_received(:lw)
      end

      it 'accepts `*` beside blank entries' do
        described_class.check_admin_allowed_hosts(['', '*'])
        expect(OT).not_to have_received(:lw)
      end
    end

    # Posture 3: a routable hostname. The ordinary configured case.
    context 'when ADMIN_ALLOWED_HOSTS names a routable hostname' do
      it 'accepts a single host' do
        described_class.check_admin_allowed_hosts(['admin.example.com'])
        expect(OT).not_to have_received(:lw)
      end

      it 'accepts several hosts' do
        described_class.check_admin_allowed_hosts(%w[admin.example.com ops.example.net])
        expect(OT).not_to have_received(:lw)
      end

      it 'accepts an entry carrying a port, scheme or trailing dot' do
        described_class.check_admin_allowed_hosts(['HTTPS://Admin.Example.COM:8443/'])
        described_class.check_admin_allowed_hosts(['admin.example.com.'])
        expect(OT).not_to have_received(:lw)
      end

      it 'accepts the punycode form of an internationalized domain' do
        described_class.check_admin_allowed_hosts(['xn--bcher-kva.example'])
        expect(OT).not_to have_received(:lw)
      end

      # Partial failure is not a boot concern: the middleware drops the bad
      # entry with a WARN and the gate still has a host to enforce.
      it 'accepts a list that mixes an unusable entry with a routable one' do
        described_class.check_admin_allowed_hosts(['127.0.0.1', 'admin.example.com'])
        expect(OT).not_to have_received(:lw)
      end
    end

    # Posture 4: `*` mixed with anything. An explicit `*` turns the host gate
    # off whatever else is listed — it is the remedy every diagnostic in this
    # feature recommends, so it must never itself be the thing that trips one.
    context 'when ADMIN_ALLOWED_HOSTS mixes `*` with other entries' do
      it 'accepts `*` beside a named host' do
        described_class.check_admin_allowed_hosts(['*', 'admin.example.com'])
        expect(OT).not_to have_received(:lw)
      end

      # THE #4062-review case: the operator was told "set it to *" and did,
      # without removing the entry that caused the message. Before the fix this
      # classified as unenforceable — a boot abort, then a total deny.
      it 'accepts `*` beside an entry that is itself unenforceable' do
        described_class.check_admin_allowed_hosts(['*', '10.0.0.5'])
        expect(OT).not_to have_received(:lw)
      end

      it 'accepts `*` beside a wildcard pattern' do
        described_class.check_admin_allowed_hosts(['*.example.com', '*'])
        expect(OT).not_to have_received(:lw)
      end
    end

    # Posture 5: set, but nothing survives classification. THE security case.
    # Pre-#4062 this disabled the gate — serving /colonel on every hostname
    # from a config whose plain intent was to restrict it. It now denies both
    # surfaces at runtime, and says so here.
    context 'when ADMIN_ALLOWED_HOSTS names nothing enforceable' do
      it 'warns for a bare IPv4 literal (never a detected host)' do
        described_class.check_admin_allowed_hosts(['127.0.0.1'])
        expect(OT).to have_received(:lw).with(/ADMIN_ALLOWED_HOSTS/)
      end

      it 'warns for a public IPv4 literal too — no IP is ever a detected host' do
        described_class.check_admin_allowed_hosts(['203.0.113.9'])
        expect(OT).to have_received(:lw).with(/ADMIN_ALLOWED_HOSTS/)
      end

      it 'warns for localhost forms' do
        described_class.check_admin_allowed_hosts(%w[localhost localhost.localdomain])
        expect(OT).to have_received(:lw).with(/ADMIN_ALLOWED_HOSTS/)
      end

      it 'warns for a wildcard PATTERN — there is no glob matching, so it matches nothing' do
        described_class.check_admin_allowed_hosts(['*.example.com'])
        expect(OT).to have_received(:lw).with(/ADMIN_ALLOWED_HOSTS/)
      end

      it 'warns for a non-ASCII (U-label) hostname — no IDN library ships here' do
        described_class.check_admin_allowed_hosts(['bücher.example'])
        expect(OT).to have_received(:lw).with(/ADMIN_ALLOWED_HOSTS/)
      end

      it 'warns when no entry in a multi-entry list survives' do
        described_class.check_admin_allowed_hosts(['127.0.0.1', '*.example.com', 'localhost'])
        expect(OT).to have_received(:lw).with(/ADMIN_ALLOWED_HOSTS/)
      end

      # The point of the #4062 review's F6: this is an admin-console
      # misconfiguration, and it must not take the public site down with it.
      it 'does NOT raise — the public site, API and health endpoints still boot' do
        expect { described_class.check_admin_allowed_hosts(['127.0.0.1']) }.not_to raise_error
      end

      # The mixup that motivated the downgrade: ADMIN_ALLOWED_HOSTS typed with
      # the value that belongs in the adjacent ADMIN_ALLOWED_CIDRS key.
      it 'does not raise on a CIDR typed into the hosts key' do
        expect { described_class.check_admin_allowed_hosts(['10.0.0.0/8']) }.not_to raise_error
      end
    end

    # The message is the whole point of warning loudly: it has to name the
    # setting, the offending entries, the reason, and every way out.
    describe 'the warning message' do
      let(:captured) do
        message = nil
        allow(OT).to receive(:lw) { |text| message = text }
        described_class.check_admin_allowed_hosts(['127.0.0.1', '*.example.com'])
        message
      end

      it 'names the env var so the operator can find the setting' do
        expect(captured).to match(/ADMIN_ALLOWED_HOSTS/)
      end

      it 'names the config path too' do
        expect(captured).to match(/site\.admin\.allowed_hosts/)
      end

      it 'echoes every offending entry so the operator can spot the typo' do
        expect(captured).to match(/127\.0\.0\.1/)
        expect(captured).to match(/\*\.example\.com/)
      end

      it 'gives the reason per entry, in the operator vocabulary' do
        expect(captured).to match(/not a routable hostname/)
        expect(captured).to match(/wildcard patterns are not supported/)
      end

      # The consequence changed with the downgrade: the surfaces 404, the
      # process does not stop. The text has to say the true thing.
      it 'states the consequence of the config as written' do
        expect(captured).to match(%r{/colonel and /api/colonel})
        expect(captured).to match(/404/)
      end

      it 'offers the escape hatch by name' do
        expect(captured).to match(/\*/)
      end

      it 'tells the non-ASCII operator to supply punycode' do
        message = nil
        allow(OT).to receive(:lw) { |text| message = text }
        described_class.check_admin_allowed_hosts(['bücher.example'])

        expect(message).to match(/punycode|xn--/)
      end
    end
  end

  # The helper is only useful if boot actually calls it. A spec that drives
  # check_admin_allowed_hosts alone stays green if the call site in
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

    it 'warns at boot when ADMIN_ALLOWED_HOSTS names nothing enforceable' do
      described_class.raise_concerns(conf_with(['127.0.0.1']))
      expect(OT).to have_received(:lw).with(/ADMIN_ALLOWED_HOSTS/)
    end

    it 'warns at boot on a wildcard pattern' do
      described_class.raise_concerns(conf_with(['*.example.com']))
      expect(OT).to have_received(:lw).with(/ADMIN_ALLOWED_HOSTS/)
    end

    # The whole point of F6: an admin-console typo does not stop the process.
    it 'still BOOTS with an unenforceable list — the warning is not fatal' do
      expect { described_class.raise_concerns(conf_with(['127.0.0.1'])) }.not_to raise_error
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

    it 'boots quietly on the `*` escape hatch beside junk' do
      described_class.raise_concerns(conf_with(['*', '10.0.0.5']))
      expect(OT).not_to have_received(:lw).with(/ADMIN_ALLOWED_HOSTS/)
    end

    # The admin check must not depend on the domains feature being on: the
    # surfaces exist in every posture, and a self-hosted install with
    # features.domains.enabled=false is exactly where a typo goes unnoticed.
    it 'warns even when features.domains is absent from the config' do
      conf = conf_with(['127.0.0.1'])
      expect(conf).not_to have_key('features')

      described_class.raise_concerns(conf)
      expect(OT).to have_received(:lw).with(/ADMIN_ALLOWED_HOSTS/)
    end
  end

  # One classifier, one answer. Onetime::Config warns at boot exactly when
  # Onetime::Middleware::AdminNetworkIsolation would construct itself with an
  # active gate and an EMPTY allowlist (deny both surfaces). If these two ever
  # disagreed the app would boot quietly into a config the middleware then
  # refuses to serve, or warn about one it serves happily.
  #
  # Asserted through the shared classifier rather than by booting a middleware
  # (that lives in try/unit/middleware/admin_network_isolation_try.rb), so this
  # stays a pure unit spec.
  describe 'agreement with the middleware denial' do
    let(:classifier) { Onetime::Utils::AdminHostAllowlist }

    def warns?(raw)
      warned = false
      allow(OT).to receive(:lw) { warned = true }
      described_class.check_admin_allowed_hosts(raw)
      warned
    end

    {
      nil => false,
      []                                 => false,
      ['*']                              => false,
      ['admin.example.com']              => false,
      ['*', 'admin.example.com']         => false,
      ['*', '10.0.0.5']                  => false,
      ['127.0.0.1', 'admin.example.com'] => false,
      ['127.0.0.1']                      => true,
      ['*.example.com']                  => true,
      ['bücher.example']                 => true,
      %w[localhost ::1]                  => true,
    }.each do |raw, expected|
      it "agrees on #{raw.inspect}: warns=#{expected}" do
        expect(warns?(raw)).to eq(expected)
        expect(classifier.classify(raw).unenforceable?).to eq(expected)
      end
    end
  end
end
