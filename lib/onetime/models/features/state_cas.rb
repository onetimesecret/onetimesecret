# lib/onetime/models/features/state_cas.rb
#
# frozen_string_literal: true

module Onetime
  module Models
    module Features
      # Atomic compare-and-set on a Horreum model's +state+ field.
      #
      # This is the single concurrency primitive behind every lifecycle state
      # transition on both Secret and Receipt. Redis runs the Lua script inside
      # its single-threaded command loop, so of any number of racing callers
      # exactly one observes an allowed +from+ value and flips it -- there is no
      # read-modify-write window in which two callers can both advance the same
      # record.
      #
      # It fails closed. A missing key (destroyed, or TTL-evicted) makes HGET
      # yield a Lua +false+ that matches no +from+ value, so the claim loses and
      # nothing is written -- a gone record is never resurrected as a TTL-less
      # "immortal" key (#3625). An already-advanced state also matches nothing,
      # so a stale instance can never revert a terminal record. The single
      # winner's HSET lands on the confirmed-live key, leaving its TTL untouched.
      #
      # Secret and Receipt each grew their own byte-identical copy of this
      # primitive (SecretStateManagement and DeprecatedFields); this feature is
      # the shared home so both models transition through one audited idiom. Each
      # model's transition methods still live in their own feature and document
      # what their individual guards protect; this feature owns only the
      # mechanism.
      #
      # Enable with +feature :state_cas+. Requires a +state+ field and the
      # Horreum base methods +dbclient+/+dbkey+/+serialize_value+.
      #
      # TODO: Replace with a transaction (MULTI/EXEC) once the follow-up field
      # writes each transition performs can be folded into the same atomic unit.
      module StateCas
        Familia::Base.add_feature self, :state_cas

        def self.included(base)
          OT.ld "[features] #{base}: #{name}"
          base.include InstanceMethods
        end

        module InstanceMethods
          # Lua compare-and-set on the +state+ field, run atomically by Redis.
          # Sets state to ARGV[1] iff the current value equals one of ARGV[2..].
          # Returns 1 to the single caller that performs the flip, 0 to everyone
          # else -- including when the key/field is gone (HGET yields a Lua false
          # that matches nothing) and when the state has already advanced.
          STATE_CAS_SCRIPT = <<~LUA
            local current = redis.call('HGET', KEYS[1], 'state')
            for i = 2, #ARGV do
              if current == ARGV[i] then
                redis.call('HSET', KEYS[1], 'state', ARGV[1])
                return 1
              end
            end
            return 0
          LUA

          private

          # Atomically transition the persisted +state+ field from one of
          # +from_states+ to +to_state+, returning whether THIS caller performed
          # the flip. See the module comment for the atomicity and fail-closed
          # guarantees; each transition method documents what its own guard
          # protects.
          #
          # Operands are produced with #serialize_value so they match how +state+
          # is encoded at rest (Familia JSON-encodes scalar fields for type
          # preservation), rather than hard-coding the on-disk representation
          # here. The eval uses the keyword +keys:+/+argv:+ form (the convention
          # used elsewhere, e.g. claim_once! and the rate limiters) so it does
          # not depend on positional-argument compatibility across Redis client
          # versions.
          #
          # @param to_state [Symbol, String] state to set on success.
          # @param from_states [Array<Symbol, String>] states the flip may fire
          #   from.
          # @return [Boolean] true iff this caller performed the transition.
          def compare_and_set_state!(to_state, from_states)
            argv = [serialize_value(to_state.to_s)]
            from_states.each { |from_state| argv << serialize_value(from_state.to_s) }

            dbclient.eval(STATE_CAS_SCRIPT, keys: [dbkey], argv: argv).to_i == 1
          end
        end
      end
    end
  end
end
