# lib/onetime/audit_reason.rb
#
# frozen_string_literal: true

module Onetime
  # AuditReason — the operator-supplied WHY on a destructive verb (#4338).
  #
  # The trail records WHAT an operator did (verb, target, result) and WHEN, but
  # never WHY. "ur_abc purged ur_xyz" is not reviewable on its own: a reviewer
  # cannot tell a GDPR erasure request from a mistake from an insider clearing
  # their tracks without leaving the system and finding the ticket. This module
  # is the one place that answers it, and the one place the answer's rules live.
  #
  # ## Optional NOW, required LATER (#4338 rollout)
  #
  # This is the OPTIONAL half of the rollout, deliberately. Every destructive op
  # accepts `reason:` and every surface (console dialog, colonel HTTP adapters,
  # CLI peers) can send one, but nothing rejects a call that omits it — flipping
  # to required is a separate change, made once every surface is confirmed to be
  # sending one, so the flip cannot break an operator mid-incident. When that
  # flip happens it happens HERE ({.normalize} raising / a `require_reason!`
  # peer) plus the adapters' validation, not in twelve ops.
  #
  # ## Why the reason rides INSIDE `detail`
  #
  # It is not a new top-level wire field. {Onetime::ColonelAuditReader::FIELDS},
  # the `colonelAuditEventSchema` Zod shape, and the CSV export header are one
  # linked contract across the API, the console and the CLI; adding a column to
  # them costs six files and buys nothing the detail hash does not already give.
  # `detail` is already rendered by the audit screen's detail cell and already
  # exported verbatim.
  #
  # ## The two rules every call site shares
  #
  #   1. SANITIZE (see {#normalize_reason}). Strip, and treat blank as ABSENT.
  #      An operator who tabs past the field must not mint `reason: ""` rows —
  #      an empty string in the trail reads as "they gave a reason" when they
  #      did not.
  #
  #   2. OMIT WHEN ABSENT (see {#with_reason}). No reason means the detail hash
  #      is byte-for-byte what it was before this feature existed. A
  #      `reason: nil` key would change every existing event's shape (and every
  #      spec's exact-kwarg expectation) to record nothing.
  #
  # ## Length
  #
  # {MAX_LENGTH} is 255, one under {Onetime::ColonelAuditEvent}'s
  # MAX_DETAIL_VALUE_LENGTH of 256. That is the point: the audit model truncates
  # string values at 256 as a defense-in-depth bound, so sanitizing one below it
  # means a reason is never silently clipped on the way into the trail — what
  # the operator typed is what a reviewer reads, or the adapter refused it up
  # front. `reason` is NOT matched by SENSITIVE_KEY_PATTERN, so it is stored
  # verbatim rather than redacted; free text is still free text, so the CLI/HTTP
  # help strings say plainly that it lands in the audit trail.
  #
  # ## Usage
  #
  #   class Purge
  #     include Onetime::AuditReason
  #
  #     def initialize(customer:, actor:, reason: nil)
  #       @reason = normalize_reason(reason)
  #     end
  #
  #     def call
  #       Onetime::ColonelAuditEvent.record(..., detail: with_reason(email: obscure))
  #     end
  #   end
  #
  module AuditReason
    # Longest reason accepted, in characters. See the length note above: one
    # under the audit model's per-value truncation bound, so a reason that
    # passes here is never truncated on storage.
    MAX_LENGTH = 255

    private

    # Normalize a caller-supplied reason into the value ops store in `@reason`.
    #
    # @param value [String, nil] raw operator input (HTTP param, CLI flag).
    # @return [String, nil] the stripped reason, or nil when blank/absent.
    def normalize_reason(value)
      reason = value.to_s.strip
      return nil if reason.empty?

      reason[0, MAX_LENGTH]
    end

    # Merge the op's `@reason` into an audit `detail` hash, or leave the detail
    # exactly as it was when there is no reason.
    #
    # @param detail [Hash, nil] the op's own detail, or nil for ops that record
    #   without one.
    # @return [Hash, nil] `detail` untouched when `@reason` is nil; otherwise
    #   `detail` plus `reason:` (an empty detail becomes `{ reason: ... }`).
    def with_reason(detail = nil)
      return detail if @reason.nil?

      (detail || {}).merge(reason: @reason)
    end
  end
end
