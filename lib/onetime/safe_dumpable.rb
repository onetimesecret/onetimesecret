# lib/onetime/safe_dumpable.rb
#
# frozen_string_literal: true

module Onetime
  # The value-object counterpart of the Familia::Horreum `safe_dump` boundary
  # (ADR-040).
  #
  # Our persistence models follow a serialization boundary convention:
  # `#safe_dump` is the POSITIVE allow-list that may cross an API/HTTP boundary;
  # `#to_h` is the FULL internal representation and may carry material the
  # boundary must never see (tokens, join keys, PII). It is a discipline code
  # follows, not a guarantee the type enforces: code serializes `safe_dump`,
  # never `to_h` (see SessionMetadata's allow-list, which omits
  # `active_session_id_hmac` on purpose).
  #
  # Ruby 3.2+ `Data` value objects earn `#to_h` for free, and it is genuinely
  # useful: pattern matching, `#with`, internal joins, logging inside a trust
  # boundary. The hazard is only that `#to_h` is INDISCRIMINATE. A value object
  # that pairs a public projection with internal correlation data (a join key,
  # provenance, a raw upstream value) leaks the internal members the instant
  # someone splats it into a response.
  #
  # The answer is NOT to cripple `#to_h` on those objects (a bespoke,
  # inconsistent shape that the next reader "fixes" back to a plain Data,
  # silently reopening the hole). It is to give them the SAME two-method
  # contract the models already have:
  #
  #   * #to_h      full, internal, indiscriminate (Data's default). Never
  #                crosses a boundary.
  #   * #safe_dump explicit positive allow-list. The ONLY shape that may.
  #
  # The rule "serialize safe_dump, never to_h" then holds UNIFORMLY across the
  # codebase, whether the object is a Horreum model or a Data result row.
  #
  # @example declare an allow-list (the common case)
  #   Row = Data.define(:public_id, :internal_token) do
  #     include Onetime::SafeDumpable
  #     safe_dump_fields :public_id            # internal_token omitted on purpose
  #   end
  #   row = Row.new(public_id: 'x', internal_token: 't')
  #   row.safe_dump                            #=> { public_id: 'x' }
  #   row.to_h                                 #=> { public_id: 'x', internal_token: 't' }
  #
  # @example a single-member projection that is itself already safe
  #   Entry = Data.define(:session, :join_key) do
  #     include Onetime::SafeDumpable
  #     def safe_dump = session                # the member IS a model safe_dump row
  #   end
  module SafeDumpable
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      # Declare the positive allow-list. Members NOT listed are internal and are
      # absent from `#safe_dump`. Mirrors Familia's `safe_dump_fields`. With no
      # arguments, returns the current allow-list (empty until declared).
      def safe_dump_fields(*fields)
        @safe_dump_fields   = fields.freeze unless fields.empty?
        @safe_dump_fields ||= [].freeze
      end
    end

    # @return [Hash] the allow-listed public projection. Classes whose public
    #   projection is not a straight member slice (e.g. a single member that is
    #   itself a safe_dump row) override this directly.
    def safe_dump
      self.class.safe_dump_fields.each_with_object({}) do |field, memo|
        memo[field] = public_send(field)
      end
    end
  end
end
