# spec/unit/onetime/config/admin_allowed_cidrs_spec.rb
#
# frozen_string_literal: true

# An ADMIN_ALLOWED_CIDRS entry that does not parse as a CIDR range is announced
# at boot with a WARN — sibling of the ADMIN_ALLOWED_HOSTS check in
# admin_allowed_hosts_spec.rb, and driven the same way: the pure helper takes
# the raw config value directly, and the wiring into raise_concerns is pinned
# separately so deleting the call site is still caught.
#
# WARN, NOT RAISE. The runtime CIDR gate is fail-closed:
# AdminNetworkIsolation#unusable_network_gate keeps a configured list whose
# every entry is unparseable ACTIVE with an EMPTY range set, denying both admin
# surfaces on every request — including from inside the range the operator
# MEANT. That backstop makes a raise unnecessary (the over-exposure cannot
# happen) and disproportionate (it would abort the public site, the API and the
# health endpoints over an admin-console-only typo). What the backstop cannot
# do is diagnose itself: its first symptom is a dark admin console. This check
# moves the diagnosis to the startup log.
#
# Run with:
#   bundle exec rspec spec/unit/onetime/config/admin_allowed_cidrs_spec.rb

require 'spec_helper'

RSpec.describe Onetime::Config, 'ADMIN_ALLOWED_CIDRS validation' do
  # Every example asserts on OT.lw, so nothing here writes to the real boot log.
  # `allow` (not `expect`) by default: the silent postures assert absence.
  before { allow(OT).to receive(:lw) }

  describe '.check_admin_allowed_cidrs' do
    # Posture 1: unset / empty. The network gate is opt-in; nothing to say.
    context 'when ADMIN_ALLOWED_CIDRS is unset or empty' do
      it 'says nothing for nil — the opt-in default' do
        described_class.check_admin_allowed_cidrs(nil)
        expect(OT).not_to have_received(:lw)
      end

      it 'says nothing for an empty list' do
        described_class.check_admin_allowed_cidrs([])
        expect(OT).not_to have_received(:lw)
      end

      it 'says nothing for a list of only blanks (the shape ERB renders for a blank value)' do
        described_class.check_admin_allowed_cidrs(['', '   '])
        expect(OT).not_to have_received(:lw)
      end
    end

    # Posture 2: parseable ranges. The ordinary configured case.
    context 'when ADMIN_ALLOWED_CIDRS names parseable ranges' do
      it 'accepts a single IPv4 range' do
        described_class.check_admin_allowed_cidrs(['100.64.0.0/10'])
        expect(OT).not_to have_received(:lw)
      end

      it 'accepts several ranges' do
        described_class.check_admin_allowed_cidrs(%w[100.64.0.0/10 10.0.0.0/8])
        expect(OT).not_to have_received(:lw)
      end

      it 'accepts a single-host /32 — the single-admin-IP idiom' do
        described_class.check_admin_allowed_cidrs(['198.51.100.45/32'])
        expect(OT).not_to have_received(:lw)
      end

      it 'accepts a bare address (IPAddr reads it as a single host)' do
        described_class.check_admin_allowed_cidrs(['10.0.0.5'])
        expect(OT).not_to have_received(:lw)
      end

      it 'accepts IPv6 ranges' do
        described_class.check_admin_allowed_cidrs(['2001:db8::/48', 'fd00::/8'])
        expect(OT).not_to have_received(:lw)
      end

      it 'accepts an entry padded with whitespace' do
        described_class.check_admin_allowed_cidrs(['  100.64.0.0/10  '])
        expect(OT).not_to have_received(:lw)
      end
    end

    # Posture 3: some entries parse, some do not. The middleware drops the bad
    # ones and enforces the survivors; the boot log has to name the dropped.
    context 'when ADMIN_ALLOWED_CIDRS mixes parseable and unparseable entries' do
      it 'warns, naming the unparseable entry' do
        described_class.check_admin_allowed_cidrs(['garbage', '10.0.0.0/8'])
        expect(OT).to have_received(:lw).with(/ADMIN_ALLOWED_CIDRS/)
      end

      it 'says the survivors are still enforced' do
        message = nil
        allow(OT).to receive(:lw) { |text| message = text }
        described_class.check_admin_allowed_cidrs(['garbage', '10.0.0.0/8'])

        expect(message).to match(/remaining entries are enforced/)
      end

      it 'names only the unparseable entries, not the survivors' do
        message = nil
        allow(OT).to receive(:lw) { |text| message = text }
        described_class.check_admin_allowed_cidrs(['garbage', '10.0.0.0/8'])

        expect(message).to match(/garbage/)
        expect(message).not_to match(/404 to EVERY request/)
      end
    end

    # Posture 4: nothing parses. THE security case: the runtime gate stays
    # ACTIVE with no range and denies both surfaces on every request — a list
    # an operator wrote is never silently disabled.
    context 'when ADMIN_ALLOWED_CIDRS has no parseable entry' do
      it 'warns for a hostname typed where a CIDR belongs' do
        described_class.check_admin_allowed_cidrs(['admin.example.com'])
        expect(OT).to have_received(:lw).with(/ADMIN_ALLOWED_CIDRS/)
      end

      it 'warns for a backslash where the slash belongs' do
        described_class.check_admin_allowed_cidrs(['100.64.0.0\\10'])
        expect(OT).to have_received(:lw).with(/ADMIN_ALLOWED_CIDRS/)
      end

      it 'warns for an out-of-range prefix' do
        described_class.check_admin_allowed_cidrs(['10.0.0.0/33'])
        expect(OT).to have_received(:lw).with(/ADMIN_ALLOWED_CIDRS/)
      end

      it 'warns when no entry in a multi-entry list parses' do
        described_class.check_admin_allowed_cidrs(['garbage', 'also-garbage'])
        expect(OT).to have_received(:lw).with(/ADMIN_ALLOWED_CIDRS/)
      end

      # The mirror of the hosts check's non-raise pin: an admin-console
      # misconfiguration must not take the public site down with it.
      it 'does NOT raise — the public site, API and health endpoints still boot' do
        expect { described_class.check_admin_allowed_cidrs(['garbage']) }.not_to raise_error
      end

      # The adjacent-key mixup, in this direction: a hostname that belongs in
      # ADMIN_ALLOWED_HOSTS typed into the CIDRs key.
      it 'does not raise on a hostname typed into the cidrs key' do
        expect { described_class.check_admin_allowed_cidrs(['admin.example.com']) }.not_to raise_error
      end
    end

    # The message is the whole point of warning loudly: it has to name the
    # setting, the offending entries, the consequence, and the way out.
    describe 'the warning message when nothing parses' do
      let(:captured) do
        message = nil
        allow(OT).to receive(:lw) { |text| message = text }
        described_class.check_admin_allowed_cidrs(['garbage', '100.64.0.0\\10'])
        message
      end

      it 'names the env var so the operator can find the setting' do
        expect(captured).to match(/ADMIN_ALLOWED_CIDRS/)
      end

      it 'names the config path too' do
        expect(captured).to match(/site\.admin\.allowed_cidrs/)
      end

      it 'echoes every offending entry so the operator can spot the typo' do
        expect(captured).to match(/garbage/)
        expect(captured).to match(/100\.64\.0\.0\\10/)
      end

      it 'states the consequence of the config as written' do
        expect(captured).to match(%r{/colonel and /api/colonel})
        expect(captured).to match(/404/)
      end

      it 'shows a working example and the way out' do
        expect(captured).to match(/100\.64\.0\.0\/10/)
        expect(captured).to match(/unset/)
      end
    end
  end

  # The helper is only useful if boot actually calls it. A spec that drives
  # check_admin_allowed_cidrs alone stays green if the call site in
  # raise_concerns is deleted, so pin the wiring separately.
  describe '.raise_concerns wiring' do
    # The minimum conf that reaches the admin-cidrs check: a global secret and
    # a truemail block. site.admin is omitted entirely when :unset, which is
    # the shape of a config that predates the key.
    def conf_with(allowed_cidrs)
      site = { 'secret' => 'a-test-secret' }
      site['admin'] = { 'allowed_cidrs' => allowed_cidrs } unless allowed_cidrs == :unset

      {
        'site' => site,
        'mail' => { 'truemail' => {} },
      }
    end

    it 'warns at boot when ADMIN_ALLOWED_CIDRS has no parseable entry' do
      described_class.raise_concerns(conf_with(['garbage']))
      expect(OT).to have_received(:lw).with(/ADMIN_ALLOWED_CIDRS/)
    end

    it 'warns at boot on a partially unparseable list' do
      described_class.raise_concerns(conf_with(['garbage', '10.0.0.0/8']))
      expect(OT).to have_received(:lw).with(/ADMIN_ALLOWED_CIDRS/)
    end

    it 'still BOOTS with an unparseable list — the warning is not fatal' do
      expect { described_class.raise_concerns(conf_with(['garbage'])) }.not_to raise_error
    end

    it 'boots when the site.admin block is absent entirely' do
      expect { described_class.raise_concerns(conf_with(:unset)) }.not_to raise_error
    end

    it 'boots quietly when ADMIN_ALLOWED_CIDRS is empty (no network gate)' do
      described_class.raise_concerns(conf_with([]))
      expect(OT).not_to have_received(:lw).with(/ADMIN_ALLOWED_CIDRS/)
    end

    it 'boots quietly on parseable ranges' do
      described_class.raise_concerns(conf_with(['100.64.0.0/10']))
      expect(OT).not_to have_received(:lw).with(/ADMIN_ALLOWED_CIDRS/)
    end
  end

  # One parse, one answer. This check warns about exactly the entries
  # AdminNetworkIsolation#parse_allowed_cidrs drops at construction (both
  # rescue IPAddr::InvalidAddressError, which covers bad prefixes), and it
  # reports the total-deny consequence exactly when #unusable_network_gate
  # would fire — a configured list, zero survivors. If these two ever disagreed
  # the app would boot quietly into a config the middleware then refuses to
  # serve, or warn about one it serves happily.
  #
  # Asserted through the same IPAddr parse rather than by booting a middleware
  # (that lives in try/unit/middleware/admin_network_isolation_try.rb), so this
  # stays a pure unit spec.
  describe 'agreement with the middleware denial' do
    def warns?(raw)
      warned = false
      allow(OT).to receive(:lw) { warned = true }
      described_class.check_admin_allowed_cidrs(raw)
      warned
    end

    def middleware_would_drop_any?(raw)
      entries = Array(raw).map { |cidr| cidr.to_s.strip }.reject(&:empty?)
      entries.any? do |entry|
        IPAddr.new(entry)
        false
      rescue IPAddr::InvalidAddressError
        true
      end
    end

    {
      nil => false,
      []                          => false,
      ['', '   ']                 => false,
      ['100.64.0.0/10']           => false,
      ['198.51.100.45/32']        => false,
      ['2001:db8::/48']           => false,
      ['garbage', '10.0.0.0/8']   => true,
      ['garbage']                 => true,
      ['100.64.0.0\\10']          => true,
      ['10.0.0.0/33']             => true,
      ['admin.example.com']       => true,
    }.each do |raw, expected|
      it "agrees on #{raw.inspect}: warns=#{expected}" do
        expect(warns?(raw)).to eq(expected)
        expect(middleware_would_drop_any?(raw)).to eq(expected)
      end
    end
  end
end
