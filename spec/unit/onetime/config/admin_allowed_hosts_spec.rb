# spec/unit/onetime/config/admin_allowed_hosts_spec.rb
#
# frozen_string_literal: true

# #4062: an explicitly set ADMIN_ALLOWED_HOSTS that names nothing the admin
# host gate could ever match is announced at boot with a WARN.
# #4127: so is an ADMIN_ALLOWED_HOSTS that was set but left blank — the gate
# quietly takes the same canonical-anchor fallback as unset, which on a
# localhost/bare-IP install means no host gate at all, and only boot can say
# so.
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
    # Posture 1: unset. The gate falls back to the canonical anchors and
    # self-disables on a localhost or bare-IP install. Nobody configured
    # anything, so there is nothing to say.
    context 'when ADMIN_ALLOWED_HOSTS is unset' do
      it 'says nothing for nil — the canonical anchor fallback' do
        described_class.check_admin_allowed_hosts(nil)
        expect(OT).not_to have_received(:lw)
      end
    end

    # Posture 1b: SET BUT BLANK (#4127). ADMIN_ALLOWED_HOSTS="" renders [],
    # ADMIN_ALLOWED_HOSTS="  " renders [''] (see the ENV mapping specs below).
    # The runtime outcome is identical to unset — anchor fallback, restrictive
    # on a routable canonical, self-disabling on localhost/bare-IP — but the
    # operator explicitly wrote an allowlist, and boot is the only place to
    # tell them their written config produced no host gate of its own.
    context 'when ADMIN_ALLOWED_HOSTS is set but blank' do
      it 'warns for an empty list (ADMIN_ALLOWED_HOSTS="")' do
        described_class.check_admin_allowed_hosts([])
        expect(OT).to have_received(:lw).with(/ADMIN_ALLOWED_HOSTS/)
      end

      it 'warns for a list of only blanks (ADMIN_ALLOWED_HOSTS="  " or ", ,")' do
        described_class.check_admin_allowed_hosts(['', '   '])
        expect(OT).to have_received(:lw).with(/ADMIN_ALLOWED_HOSTS/)
      end

      it 'does NOT raise — the fallback is the restrictive default, only unvoiced' do
        expect { described_class.check_admin_allowed_hosts([]) }.not_to raise_error
      end

      describe 'the warning message' do
        let(:captured) do
          message = nil
          allow(OT).to receive(:lw) { |text| message = text }
          described_class.check_admin_allowed_hosts([])
          message
        end

        it 'names the env var and the config path' do
          expect(captured).to match(/ADMIN_ALLOWED_HOSTS/)
          expect(captured).to match(/site\.admin\.allowed_hosts/)
        end

        it 'states the consequence: the canonical-anchor fallback' do
          expect(captured).to match(/canonical anchors/)
        end

        it 'states the localhost/bare-IP consequence: the gate self-disables' do
          expect(captured).to match(/self-disables/)
        end

        it 'offers every way out: a hostname, unsetting, or the `*` escape hatch' do
          expect(captured).to match(/admin\.example\.com/)
          expect(captured).to match(/unset/)
          expect(captured).to match(/\*/)
        end
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

    it 'boots when ADMIN_ALLOWED_HOSTS is blank — the set-but-blank WARN is not fatal (#4127)' do
      expect { described_class.raise_concerns(conf_with([])) }.not_to raise_error
      expect(OT).to have_received(:lw).with(/ADMIN_ALLOWED_HOSTS/)
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
  # active gate and an EMPTY allowlist (deny both surfaces) — and additionally
  # (#4127) when the list is set but blank, where the middleware takes the
  # anchor fallback and the boot WARN is the ONLY signal. `denies` below is
  # the middleware half (Classification#unenforceable?); `warns` is the boot
  # half. warns must be a superset of denies: every runtime denial is
  # announced, and the one extra warning names a fallback, not a denial. If
  # the two halves ever disagreed on denials the app would boot quietly into
  # a config the middleware then refuses to serve, or warn about one it
  # serves happily.
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
      nil => { warns: false, denies: false },
      []                                 => { warns: true,  denies: false }, # set-but-blank: anchor fallback, announced (#4127)
      ['', '   ']                        => { warns: true,  denies: false }, # ditto, the ADMIN_ALLOWED_HOSTS="  " shape
      ['*']                              => { warns: false, denies: false },
      ['admin.example.com']              => { warns: false, denies: false },
      ['*', 'admin.example.com']         => { warns: false, denies: false },
      ['*', '10.0.0.5']                  => { warns: false, denies: false },
      ['127.0.0.1', 'admin.example.com'] => { warns: false, denies: false },
      ['127.0.0.1']                      => { warns: true,  denies: true },
      ['*.example.com']                  => { warns: true,  denies: true },
      ['bücher.example']                 => { warns: true,  denies: true },
      %w[localhost ::1]                  => { warns: true,  denies: true },
    }.each do |raw, expected|
      it "agrees on #{raw.inspect}: warns=#{expected[:warns]} denies=#{expected[:denies]}" do
        expect(warns?(raw)).to eq(expected[:warns])
        expect(classifier.classify(raw).unenforceable?).to eq(expected[:denies])
      end
    end
  end

  # The nil/[] distinction the boot check relies on is MANUFACTURED upstream,
  # by two pieces that must hold together (#4127):
  #
  #   1. The config template renders ADMIN_ALLOWED_HOSTS without an `|| []`
  #      fallback, so unset arrives as YAML nil and set-but-blank as a list
  #      with nothing usable in it.
  #   2. DEFAULTS carries NO site.admin.allowed_hosts key, because deep_merge
  #      has an explicit `v2.nil? -> v1` arm that would resolve the YAML nil
  #      back to any default and erase the distinction.
  #
  # Either piece regressing silently turns the set-but-blank WARN into either
  # noise on every default install or a check that can never fire — so both
  # are pinned here, against the REAL defaults template.
  describe 'the ENV -> config shapes the check depends on (#4127)' do
    let(:defaults_path) do
      File.expand_path('../../../../etc/defaults/config.defaults.yaml', __dir__)
    end

    def rendered_allowed_hosts(env_value)
      original = ENV.fetch('ADMIN_ALLOWED_HOSTS', :absent)
      if env_value.nil?
        ENV.delete('ADMIN_ALLOWED_HOSTS')
      else
        ENV['ADMIN_ALLOWED_HOSTS'] = env_value
      end

      yaml = described_class.send(:load_yaml_with_erb, defaults_path)
      yaml.dig('site', 'admin', 'allowed_hosts')
    ensure
      if original == :absent
        ENV.delete('ADMIN_ALLOWED_HOSTS')
      else
        ENV['ADMIN_ALLOWED_HOSTS'] = original
      end
    end

    it 'renders nil when ADMIN_ALLOWED_HOSTS is unset' do
      expect(rendered_allowed_hosts(nil)).to be_nil
    end

    it 'renders an empty list for ADMIN_ALLOWED_HOSTS=""' do
      expect(rendered_allowed_hosts('')).to eq([])
    end

    it 'renders a blank entry for ADMIN_ALLOWED_HOSTS="  "' do
      expect(rendered_allowed_hosts('  ')).to eq([''])
    end

    it 'still renders a real list for a set value' do
      expect(rendered_allowed_hosts('admin.example.com, ops.example.net'))
        .to eq(%w[admin.example.com ops.example.net])
    end

    it 'has no allowed_hosts key in DEFAULTS, so deep_merge cannot resurrect []' do
      expect(described_class::DEFAULTS.dig('site', 'admin')).not_to have_key('allowed_hosts')
    end

    it 'preserves the rendered nil through the DEFAULTS merge' do
      loaded = { 'site' => { 'admin' => { 'allowed_hosts' => nil } } }
      merged = described_class.send(:deep_merge, described_class::DEFAULTS, loaded)

      expect(merged['site']['admin']).to have_key('allowed_hosts')
      expect(merged.dig('site', 'admin', 'allowed_hosts')).to be_nil
    end
  end
end
