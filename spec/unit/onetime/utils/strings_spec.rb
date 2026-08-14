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
# The second contract this file pins is the shape of the raise. strict_bool!
# is public, so a future caller can hand it whatever an operator put in an
# env var — including a value misrouted from a credential — and the message
# lands in logs, a boot trace, and Sentry's issue title, where by-param-name
# scrubbing cannot reach a string interpolated into the exception itself.
# So the message NEVER reproduces the rejected value: not verbatim, not
# lowercased, not truncated. It carries the flag name (the actionable part),
# the character count, a truncated SHA-256 correlation tag, and the token
# vocabularies. See ADR-037 and the non-disclosure sweep below, which is the
# load-bearing test in this file.
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

  describe '.strict_bool!' do
    # Module function, not a mixed-in instance method: every call site says
    # Onetime::Utils::Strings.strict_bool! explicitly. The surface assertion
    # at the bottom of this block pins that.

    # Unset takes the caller's documented default — including the
    # security-relevant default-ON case.
    [true, false].each do |default|
      [nil, '', '   ', "\n"].each do |blank|
        it "resolves #{blank.inspect} to the caller's default (#{default})" do
          expect(described_class.strict_bool!('RABBITMQ_VERIFY_PEER', blank, default: default)).to be(default)
        end
      end

      described_class::TRUTHY_VALUES.each do |token|
        it "resolves #{token.inspect} to true regardless of default (#{default})" do
          expect(described_class.strict_bool!('FLAG', token, default: default)).to be(true)
        end
      end

      described_class::FALSEY_VALUES.each do |token|
        it "resolves #{token.inspect} to false regardless of default (#{default})" do
          expect(described_class.strict_bool!('FLAG', token, default: default)).to be(false)
        end
      end
    end

    it 'accepts padded and mixed-case tokens' do
      expect(described_class.strict_bool!('FLAG', ' TRUE ', default: false)).to be(true)
      expect(described_class.strict_bool!('FLAG', "Off\n", default: true)).to be(false)
    end

    %w[ture flase enabled maybe 2].each do |garbage|
      it "raises ConfigError on #{garbage.inspect} instead of falling back to the default" do
        expect { described_class.strict_bool!('RABBITMQ_VERIFY_PEER', garbage, default: true) }
          .to raise_error(Onetime::ConfigError)
      end
    end

    describe 'the shape of the raise' do
      # Replaces a retired assertion that required the message to quote the
      # offending value (/RABBITMQ_VERIFY_PEER.*"ture"/). That contract was
      # the defect: see the non-disclosure sweep below and ADR-037.
      it 'names the flag and both token vocabularies, so the operator can act' do
        expect { described_class.strict_bool!('RABBITMQ_VERIFY_PEER', 'ture', default: true) }
          .to raise_error(Onetime::ConfigError, /RABBITMQ_VERIFY_PEER/)
        expect { described_class.strict_bool!('RABBITMQ_VERIFY_PEER', 'ture', default: true) }
          .to raise_error(Onetime::ConfigError, %r{1/true/yes/on/y/t.*0/false/no/off/n/f}m)
      end

      it 'reports the character count of the normalized value' do
        expect { described_class.strict_bool!('FLAG', '  MayBe  ', default: true) }
          .to raise_error(Onetime::ConfigError, /\(5 chars,/)
      end

      it 'carries a truncated SHA-256 of the normalized value as a correlation tag' do
        expected = Digest::SHA256.hexdigest('ture')[0, described_class::BOOL_DIGEST_LENGTH]

        expect { described_class.strict_bool!('FLAG', 'ture', default: true) }
          .to raise_error(Onetime::ConfigError, /sha256:#{expected}\b/)
      end

      # Normalization happens once, before both the token tables and the tag,
      # so the same mistyped value tags identically however it was padded or
      # cased. That is what makes the tag usable to compare two hosts.
      it 'tags the normalized form, so padding and case do not change the tag' do
        tags = ['ture', ' TURE ', "Ture\n"].map do |raw|
          described_class.strict_bool!('FLAG', raw, default: true)
        rescue Onetime::ConfigError => e
          e.message[/sha256:(\h+)/, 1]
        end

        expect(tags.uniq.length).to eq(1)
        expect(tags.first).to eq(Digest::SHA256.hexdigest('ture')[0, described_class::BOOL_DIGEST_LENGTH])
      end

      it 'tags the value, not the flag name: two flags with one typo correlate' do
        tag = lambda do |name|
          described_class.strict_bool!(name, 'ture', default: true)
        rescue Onetime::ConfigError => e
          e.message[/sha256:(\h+)/, 1]
        end

        expect(tag.call('RABBITMQ_VERIFY_PEER')).to eq(tag.call('BILLING_ENABLED'))
      end

      # Pins the truncation length. A future widening toward a full hash would
      # stop being a tag and start being a fingerprint of a short secret.
      it 'truncates the digest to BOOL_DIGEST_LENGTH hex characters' do
        expect(described_class::BOOL_DIGEST_LENGTH).to eq(8)

        expect { described_class.strict_bool!('FLAG', 'ture', default: true) }
          .to raise_error(Onetime::ConfigError, /sha256:\h{#{described_class::BOOL_DIGEST_LENGTH}}(?!\h)/)
      end
    end

    # THE LOAD-BEARING TEST. strict_bool! is public, so a future caller may
    # hand it a value misrouted from a credential; the message reaches logs
    # and Sentry's issue title, where by-param-name scrubbing cannot reach a
    # string interpolated into the exception. Nothing derived from the value's
    # CONTENT may appear — a truncated head is not a fix, because most secrets
    # are shorter than any workable cap.
    #
    # Fixtures are chosen not to collide incidentally with the fixed message
    # text ("unrecognized boolean", "chars", "sha256", "leave unset", and the
    # two token lists), and to contain no long hex runs that could collide
    # with the digest tag.
    describe 'non-disclosure of the rejected value' do
      {
        'a short secret, well under any plausible truncation cap' => 'hunter2',
        'a numeric PIN' => '4813',
        'a long API-key-shaped value' => "sk_live_#{'z' * 64}",
        'a URL with inline credentials' => 'https://packrat:swordfish@internal.example/path',
        'a mixed-case value, proving the downcased form does not leak either' => 'MyPaSsWord',
        'a whole config blob with newlines' => "amqp_password: swordfish\napi_token: zzzz-9999",
      }.each do |label, secret|
        it "does not reproduce #{label}" do
          message = begin
            described_class.strict_bool!('RABBITMQ_VERIFY_PEER', secret, default: true)
            raise 'expected strict_bool! to raise'
          rescue Onetime::ConfigError => e
            e.message
          end

          normalized = secret.strip.downcase

          expect(message).not_to include(secret)
          expect(message).not_to include(normalized)

          # No prefix, suffix, or interior run of the value survives either.
          # Four characters is short enough to catch a truncated head and long
          # enough that ordinary English overlap does not fire.
          leaked = (0..(normalized.length - 4)).map { |i| normalized[i, 4] }.select do |run|
            message.include?(run)
          end
          expect(leaked).to be_empty, "message leaked substrings #{leaked.inspect}: #{message}"
        end
      end

      # The message is the whole exposure surface — ConfigError carries no
      # other attribute — so pin that the renderings which actually reach a
      # log or a Sentry title are clean too.
      it 'leaks nothing through inspect or full_message either' do
        secret = 'hunter2'
        error = begin
          described_class.strict_bool!('RABBITMQ_VERIFY_PEER', secret, default: true)
          raise 'expected strict_bool! to raise'
        rescue Onetime::ConfigError => e
          e
        end

        expect(error.inspect).not_to include(secret)
        expect(error.full_message(highlight: false, order: :top)).not_to include(secret)
      end

      # Pins the REJECTED approach so it cannot be reintroduced quietly: an
      # earlier fix echoed a 32-character truncated head via a private
      # bool_echo/MAX_BOOL_ECHO_LENGTH pair.
      it 'has no value-echoing helper left behind' do
        expect(described_class.private_instance_methods).not_to include(:bool_echo)
        expect(described_class.respond_to?(:bool_echo, true)).to be(false)
        expect(defined?(described_class::MAX_BOOL_ECHO_LENGTH)).to be_nil
      end
    end

    # Exposed as a module function only. Onetime::Utils does `extend Strings`,
    # so a public instance copy would silently re-add Onetime::Utils
    # .strict_bool! and let call sites drift back to the shorter name.
    it 'is not exposed on the mixed-in utility surface' do
      expect(utils).not_to respond_to(:strict_bool!)
      expect(described_class).to respond_to(:strict_bool!)
    end
  end
end
