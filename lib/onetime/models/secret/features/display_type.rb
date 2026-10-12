# lib/onetime/models/secret/features/display_type.rb
#
# frozen_string_literal: true

module Onetime::Secret::Features
  # How the recipient's client should present the decrypted value.
  #
  # A presentation hint, not a security control: it says how to show the
  # value, not what the value is, so safe_dump emits it before reveal and the
  # client must sanitize whatever a type renders. Stamped once at creation
  # (Receipt.spawn_pair, from the conceal request) and never inferred from
  # the content. See docs/specs/secret-display-type.md.
  #
  # The field lives on the Secret's own hash rather than a related key: one
  # immutable value whose lifetime is exactly the secret's, so it expires and
  # is destroyed with the record for free.
  #
  # Adding a type (e.g. 'httplink', a "you are about to open an external
  # link" interstitial):
  #
  #   1. Append it to TYPES. Older builds read it as DEFAULT; older clients
  #      fall back to plain text.
  #   2. Put any creation rule for the content (an httplink value must be a
  #      URL) in the conceal logic beside validate_display_type, where the
  #      plaintext is still available.
  #   3. Add it to secretDisplayTypeValues (src/schemas/contracts/secret.ts)
  #      and teach the reveal components what it means.
  #
  module DisplayType
    Familia::Base.add_feature self, :display_type

    # Closed value space. Strings, matching the :state / :kind convention.
    TYPES   = %w[text markdown].freeze
    DEFAULT = 'text'

    def self.included(base)
      OT.ld "[features] #{base}: #{name}"

      base.extend ClassMethods
      base.include InstanceMethods

      # No fast writer (display_type!): the type is stamped once, before the
      # secret's first save, and no later path may rewrite it in place.
      base.field :display_type, fast_method: false
    end

    module ClassMethods
      # @return [Array<String>] every display type this build knows
      def display_types = TYPES

      # @return [String] the type of a secret that names none
      def default_display_type = DEFAULT

      # Whether the given value names a known display type.
      #
      # @param value [String, Symbol, nil]
      # @return [Boolean]
      def valid_display_type?(value)
        TYPES.include?(value.to_s)
      end

      # Canonical form of a requested display type: stripped and downcased,
      # with absent or blank meaning DEFAULT. Does not validate; pair with
      # valid_display_type? so an unknown type is refused, not stored.
      #
      # @param value [String, Symbol, nil]
      # @return [String]
      def normalize_display_type(value)
        normalized = value.to_s.strip.downcase
        normalized.empty? ? DEFAULT : normalized
      end
    end

    module InstanceMethods
      # The stored display type, or DEFAULT when the field is unset (records
      # created before it existed) or holds a value this build does not know
      # (a downgrade after a newer type shipped). Reading falls back rather
      # than raising, and leaves the stored value alone, so a roll-forward
      # shows the newer type again.
      #
      # @return [String] one of TYPES
      def display_type_or_default
        value = display_type.to_s
        self.class.valid_display_type?(value) ? value : DEFAULT
      end

      # @param guess [String, Symbol]
      # @return [Boolean]
      def display_type?(guess)
        display_type_or_default == guess.to_s
      end
    end
  end
end
