# spec/unit/onetime/utils/strings_spec.rb
#
# frozen_string_literal: true

# Boolean-token parsing for operator-supplied flags.
#
# Why this exists: lib/onetime/jobs/queues/config.rb read
# `ENV.fetch('RABBITMQ_VERIFY_PEER', 'true') == 'true'`, so every spelling
# other than the literal `true` — TRUE, 1, yes, " true ", or the typo
# `ture` — silently DISABLED AMQPS certificate verification on a
# default-ON control. The load-bearing distinction, and the reason
# explicit_no? is not `!explicit_yes?`: these are RECOGNIZERS, not a
# partition. Unrecognized input is neither yes nor no, so the configuration
# resolver can fail loudly rather than landing a typo on false (ADR-033).
#
# Run with:
#   AUTHENTICATION_MODE=simple bundle exec rspec spec/unit/onetime/utils/strings_spec.rb

require 'spec_helper'

RSpec.describe Onetime::Utils::Strings do
  # Methods are mixed in via `extend Strings` in lib/onetime/utils.rb; the
  # module-function surface is what every call site actually uses.
  subject(:utils) { Onetime::Utils }

  describe '#explicit_yes? / #explicit_no?' do
    described_class::TRUTHY_VALUES.each do |token|
      it "recognizes #{token.inspect} as yes, not no" do
        expect(utils.explicit_yes?(token)).to be(true)
        expect(utils.explicit_no?(token)).to be(false)
      end
    end

    described_class::FALSEY_VALUES.each do |token|
      it "recognizes #{token.inspect} as no, not yes" do
        expect(utils.explicit_no?(token)).to be(true)
        expect(utils.explicit_yes?(token)).to be(false)
      end
    end

    it 'is case-insensitive' do
      expect(utils.explicit_yes?('TRUE')).to be(true)
      expect(utils.explicit_no?('Off')).to be(true)
    end

    # Regression guard: the pre-rename yes? did not strip, so a trailing
    # newline out of a .env file or a padded compose value read as unset.
    it 'tolerates surrounding whitespace' do
      expect(utils.explicit_yes?(' true ')).to be(true)
      expect(utils.explicit_yes?("1\n")).to be(true)
      expect(utils.explicit_no?("\tfalse ")).to be(true)
    end

    it 'treats nil and blank as neither yes nor no' do
      [nil, '', '   '].each do |blank|
        expect(utils.explicit_yes?(blank)).to be(false), "explicit_yes?(#{blank.inspect})"
        expect(utils.explicit_no?(blank)).to be(false), "explicit_no?(#{blank.inspect})"
      end
    end

    # THE CENTRAL INVARIANT. If explicit_no? were `!explicit_yes?`, a typo
    # would resolve to "no" — which on RABBITMQ_VERIFY_PEER means peer
    # verification off, silently.
    it 'is a recognizer, not a partition: unrecognized input is neither yes nor no' do
      %w[ture flase enabled maybe 2].each do |garbage|
        expect(utils.explicit_yes?(garbage)).to be(false), "explicit_yes?(#{garbage.inspect})"
        expect(utils.explicit_no?(garbage)).to be(false), "explicit_no?(#{garbage.inspect})"
      end
    end

    # The alias carries ~10 existing call sites; removing it is a silent
    # NoMethodError at boot.
    it 'keeps yes? as an alias of explicit_yes?' do
      expect(utils.method(:yes?)).to eq(utils.method(:explicit_yes?))
      expect(utils.yes?('yes')).to be(true)
      expect(utils.yes?('ture')).to be(false)
    end
  end

  it 'does not expose configuration resolution on the mixed-in utility surface' do
    expect(utils).not_to respond_to(:strict_bool!)
  end
end
