# spec/unit/onetime/config/link_domains_spec.rb
#
# frozen_string_literal: true

# AC5 (#4063): LINK_DOMAINS set-but-empty aborts boot.
#
# The validator is driven DIRECTLY with an explicit raw argument rather than
# through a booted OT.conf. spec/config.test.yaml cannot represent the
# set-but-empty case from a spec process: reproducing it would mean setting
# ENV['LINK_DOMAINS']='' and re-running the whole ERB+YAML load, and the lane
# runner scrubs LINK_DOMAINS precisely so a dev shell cannot do that by
# accident. Driving the pure helper is what makes the criterion testable at
# all; the wiring into raise_concerns is pinned separately below so deleting
# the call site is still caught.
#
# NOTE the polarity: empty means ERROR here, unlike #4062's admin
# allowed_hosts where empty means canonical-only. See the comment on
# Onetime::Config.validate_link_domains! before "fixing" either to match.
#
# Run with:
#   bundle exec rspec spec/unit/onetime/config/link_domains_spec.rb

require 'spec_helper'

RSpec.describe Onetime::Config, 'LINK_DOMAINS validation (#4063)' do
  describe '.validate_link_domains!' do
    context 'when LINK_DOMAINS is unset (nil)' do
      it 'returns without raising — the picker falls back to the canonical domain' do
        expect { described_class.validate_link_domains!(nil) }.not_to raise_error
      end
    end

    context 'when LINK_DOMAINS names at least one host' do
      it 'accepts a single host' do
        expect { described_class.validate_link_domains!(['a.com']) }.not_to raise_error
      end

      it 'accepts several hosts' do
        expect { described_class.validate_link_domains!(%w[a.com b.com]) }.not_to raise_error
      end

      it 'accepts a list whose blanks sit beside a real host' do
        expect { described_class.validate_link_domains!(['', 'a.com']) }.not_to raise_error
      end
    end

    context 'when LINK_DOMAINS is set but empty (LINK_DOMAINS="")' do
      it 'raises Onetime::ConfigError' do
        expect { described_class.validate_link_domains!([]) }
          .to raise_error(Onetime::ConfigError)
      end

      it 'names the env var so the operator can find the setting' do
        expect { described_class.validate_link_domains!([]) }
          .to raise_error(Onetime::ConfigError, /LINK_DOMAINS/)
      end

      it 'names the config path too' do
        expect { described_class.validate_link_domains!([]) }
          .to raise_error(Onetime::ConfigError, /features\.domains\.link_domains/)
      end

      it 'tells the operator how to resolve it' do
        expect { described_class.validate_link_domains!([]) }
          .to raise_error(Onetime::ConfigError, /unset LINK_DOMAINS/)
      end
    end

    context 'when LINK_DOMAINS is whitespace only (LINK_DOMAINS=" ")' do
      it "raises for [''] — the shape ERB renders for a blank value" do
        expect { described_class.validate_link_domains!(['']) }
          .to raise_error(Onetime::ConfigError, /LINK_DOMAINS/)
      end

      it 'raises for a padded blank entry' do
        expect { described_class.validate_link_domains!(['   ']) }
          .to raise_error(Onetime::ConfigError, /LINK_DOMAINS/)
      end

      it 'raises when every entry is blank' do
        expect { described_class.validate_link_domains!(['', '  ']) }
          .to raise_error(Onetime::ConfigError, /LINK_DOMAINS/)
      end
    end

    # A typo'd pool is the same defect as a blank one — the operator asked for
    # a pool and there is none — and it used to boot clean. DomainStrategy
    # then fell back to [canonical_domain], so the picker offered the internal
    # platform host: precisely the outcome LINK_DOMAINS exists to prevent.
    # There is no safe fallback, so this must fail at boot.
    context 'when LINK_DOMAINS names no parseable host' do
      it 'raises for a private/internal hostname with no public suffix' do
        expect { described_class.validate_link_domains!(['links.internal']) }
          .to raise_error(Onetime::ConfigError, /LINK_DOMAINS/)
      end

      it 'raises for a bare hostname' do
        expect { described_class.validate_link_domains!(['localhost']) }
          .to raise_error(Onetime::ConfigError, /LINK_DOMAINS/)
      end

      it 'raises when no entry in a multi-entry list parses' do
        expect { described_class.validate_link_domains!(%w[links.internal shortener]) }
          .to raise_error(Onetime::ConfigError, /LINK_DOMAINS/)
      end

      it 'echoes the offending entries so the operator can spot the typo' do
        expect { described_class.validate_link_domains!(['links.internal']) }
          .to raise_error(Onetime::ConfigError, /links\.internal/)
      end

      it 'tells the operator how to resolve it' do
        expect { described_class.validate_link_domains!(['links.internal']) }
          .to raise_error(Onetime::ConfigError, /[Uu]nset LINK_DOMAINS/)
      end
    end

    # Partial failure is NOT a boot error: DomainStrategy drops the bad entry
    # and logs it, and the pool still has a host to offer. Only a pool with
    # nothing usable in it is fatal.
    context 'when LINK_DOMAINS mixes parseable and unparseable hosts' do
      it 'accepts the list' do
        expect { described_class.validate_link_domains!(%w[links.internal go.example.com]) }
          .not_to raise_error
      end
    end

    # Parseability is judged exactly as the middleware judges it, so a host
    # that boots is a host DomainStrategy will serve. Ports are stripped
    # before the public-suffix check on both sides.
    context 'when a LINK_DOMAINS entry carries a port' do
      it 'accepts it' do
        expect { described_class.validate_link_domains!(['go.example.com:8443']) }
          .not_to raise_error
      end
    end
  end

  # The helper is only useful if boot actually calls it. A spec that drives
  # validate_link_domains! alone stays green if the call site in
  # raise_concerns is deleted, so pin the wiring separately.
  describe '.raise_concerns wiring' do
    # The minimum conf that reaches the link_domains check: a global secret
    # (or the nil-secret escape hatch) and a truemail block.
    def conf_with(link_domains, domains_enabled: true)
      domains                 = { 'enabled' => domains_enabled }
      domains['link_domains'] = link_domains unless link_domains == :unset

      {
        'site' => { 'secret' => 'a-test-secret' },
        'mail' => { 'truemail' => {} },
        'features' => { 'domains' => domains },
      }
    end

    it 'aborts boot when LINK_DOMAINS is set but empty' do
      expect { described_class.raise_concerns(conf_with([])) }
        .to raise_error(Onetime::ConfigError, /LINK_DOMAINS/)
    end

    it 'aborts boot when LINK_DOMAINS is whitespace only' do
      expect { described_class.raise_concerns(conf_with([''])) }
        .to raise_error(Onetime::ConfigError, /LINK_DOMAINS/)
    end

    it 'boots when LINK_DOMAINS is absent from the config entirely' do
      expect { described_class.raise_concerns(conf_with(:unset)) }.not_to raise_error
    end

    it 'boots when LINK_DOMAINS names a host' do
      expect { described_class.raise_concerns(conf_with(['links.example.net'])) }.not_to raise_error
    end

    it 'aborts boot when LINK_DOMAINS names no parseable host' do
      expect { described_class.raise_concerns(conf_with(['links.internal'])) }
        .to raise_error(Onetime::ConfigError, /LINK_DOMAINS/)
    end

    # Deliberate: the operator explicitly wrote a blank LINK_DOMAINS, and
    # raise_concerns runs before any feature gating. Failing loud on the typo
    # beats tolerating dead config — and it is the only placement where the
    # check is reachable in a default lane, where domains.enabled is false.
    it 'aborts even when features.domains.enabled is false' do
      expect { described_class.raise_concerns(conf_with([], domains_enabled: false)) }
        .to raise_error(Onetime::ConfigError, /LINK_DOMAINS/)
    end

    # AC6 at the config layer: DEFAULT_DOMAIN does not have to be a pool
    # member. "Anchor links on the canonical host but keep it out of the
    # picker" is the single-tenant ge-* install, and it is legitimate.
    it 'does not require features.domains.default to appear in the pool' do
      conf                                   = conf_with(['short.example.com'])
      conf['features']['domains']['default'] = 'links.example.net'

      expect { described_class.raise_concerns(conf) }.not_to raise_error
    end
  end

  # The unset-vs-set-empty distinction only survives if deep_merge never gets
  # a default to restore. Config::DEFAULTS carrying a link_domains entry would
  # turn nil back into that default (see the `elsif v2.nil? then v1` arm) and
  # AC5 would be untestable in production, not just here.
  describe 'Config::DEFAULTS' do
    it 'does not define features.domains.link_domains' do
      domains = described_class::DEFAULTS.dig('features', 'domains')

      expect(domains).not_to have_key('link_domains') if domains.is_a?(Hash)
      expect(described_class::DEFAULTS.to_s).not_to include('link_domains')
    end
  end
end
