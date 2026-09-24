# lib/onetime/session/impersonation.rb
#
# frozen_string_literal: true

require 'securerandom'

require_relative '../models/colonel_audit_event'

module Onetime
  # SessionImpersonation — the colonel-impersonation session marker primitive.
  #
  # A colonel in the admin console opens a time-boxed, READ-ONLY view of the
  # app as a target customer, in the SAME browser session. This module owns the
  # marker that makes that true, the one resolver that decides the effective
  # identity from it, and the request-scoped context the view layer reads.
  #
  # ## OVERLAY, NOT SWAP (the load-bearing decision)
  #
  # `session['external_id']` stays the COLONEL's extid for the whole
  # impersonation. The marker at `session['impersonation']` OVERLAYS the
  # effective customer on top of that principal. Three consequences, all
  # deliberate:
  #
  #   1. ABSENCE IS THE SAFE STATE. If the marker is lost — a dropped write, a
  #      truncated blob, a future refactor — the session degrades to an
  #      ordinary colonel session. It can never degrade INTO an impersonation.
  #   2. Session indexing (TrackMetadata / `active_sessions`) keeps filing the
  #      session under the colonel, so nothing has to migrate into (and back
  #      out of) the target's session list.
  #   3. It is why the marker must NOT be a sidecar field: the sidecar's
  #      admission rule (lib/onetime/session/sidecar.rb) admits only fields
  #      whose absence is safe *and whose presence is not identity*. The marker
  #      passes the first test but rides the blob anyway, because it must be
  #      written and read atomically with `external_id`.
  #
  # ## Bounded lifetime, independent of the session cookie
  #
  # The marker carries its own `expires_at` ({TTL} seconds after start, fixed;
  # no caller-supplied lifetime). {.active} treats an expired marker as ended:
  # it stops it (which audits `ended_by: 'expired'`) and answers nil. So the
  # impersonation window is bounded even in a session whose `expire_after` is
  # 24h.
  #
  # ## Naming
  #
  # `Onetime::Session` is the Rack session store CLASS, so this cannot nest
  # under it without a circular require. It follows the sibling convention in
  # this directory instead: {Onetime::SessionCodec} (session/codec.rb),
  # {Onetime::SessionSidecar} (session/sidecar.rb).
  module SessionImpersonation
    extend self

    # Session blob key. String, because the blob round-trips through JSON and
    # a symbol would come back as a string anyway.
    SESSION_KEY = 'impersonation'

    # Fixed impersonation lifetime in seconds. Deliberately NOT configurable
    # and not caller-supplied: a lifetime an adapter can widen is not a bound.
    TTL = 30 * 60

    # Request-scoped context slot (same fiber-local discipline as
    # Onetime::EntitlementPreview).
    FIBER_KEY = :ots_impersonation

    # Rack env slot memoizing the loaded target for the request. Up to three
    # call sites resolve identity per request (the session strategy, the
    # noauth strategy, SessionHelpers#current_customer) and {.resolve} reads
    # the target twice on its own, so without this a single impersonated
    # request costs six Customer loads. The entry is a two-element Array —
    # [target_extid, customer_or_nil] — so a nil load (target deleted) is
    # cached as a real answer rather than re-queried, while a marker swap
    # inside one request can never be served a stale customer.
    TARGET_ENV_KEY = 'onetime.impersonation.target'

    AUDIT_VERB_START = 'customer.impersonate.start'
    AUDIT_VERB_STOP  = 'customer.impersonate.stop'

    # Why an impersonation ended. `operator` and `expired` are the ordinary
    # paths; the rest are resolver-detected invalidations (see {.resolve}),
    # which are the interesting ones in the trail — each means the session was
    # still presenting as the target when the precondition went away.
    ENDED_BY_OPERATOR          = 'operator'
    ENDED_BY_EXPIRED           = 'expired'
    ENDED_BY_LOGOUT            = 'logout'
    ENDED_BY_COLONEL_DEMOTED   = 'colonel_demoted'
    ENDED_BY_TARGET_MISSING    = 'target_missing'
    ENDED_BY_TARGET_SUSPENDED  = 'target_suspended'
    ENDED_BY_TARGET_PRIVILEGED = 'target_privileged'

    # Begin an impersonation on this session.
    #
    # Writes the marker only. The `customer.impersonate.start` audit event is
    # the START operation's (Auth::Operations::Customers::Impersonate) — it is
    # the layer that knows the actor and validated the preconditions. The STOP
    # audit lives here instead, because two unrelated call sites end an
    # impersonation (the stop operation and expiry inside {.active}) and they
    # must produce the identical event.
    #
    # @param session [#[]=] Rack session (string keys)
    # @param target [Onetime::Customer] the customer to present as
    # @param reason [String] operator-supplied justification
    # @return [Hash] the marker that was written (string keys)
    def start!(session, target:, reason:)
      now = Familia.now.to_i

      marker = {
        'id' => "imp_#{SecureRandom.hex(8)}",
        'target_extid' => target.extid.to_s,
        'target_email' => target.email.to_s,
        'reason' => reason.to_s,
        'started_at' => now,
        'expires_at' => now + TTL,
      }

      session[SESSION_KEY] = marker
      marker
    end

    # The live marker for this session, or nil.
    #
    # An expired marker is not "a marker that happens to be old": it is ended
    # here and now — cleared and audited — so every reader (the middleware and
    # all three identity call sites) converges on the same verdict without any
    # of them having to know the expiry rule. The clear makes it idempotent:
    # the second caller in the same request sees nil and audits nothing.
    #
    # @param session [#[], nil] Rack session
    # @return [Hash, nil] marker with string keys, or nil
    def active(session)
      marker = read(session)
      return nil unless marker

      if expired?(marker)
        stop!(session, ended_by: ENDED_BY_EXPIRED)
        return nil
      end

      marker
    end

    # End the impersonation on this session and record ONE stop event.
    #
    # Idempotent and audit-once: with no marker present nothing is written and
    # nothing is recorded.
    #
    # @param session [#[], nil] Rack session
    # @param ended_by [String] one of the ENDED_BY_* constants
    # @return [Hash, nil] the marker that was ended, or nil if there was none
    def stop!(session, ended_by: ENDED_BY_OPERATOR)
      marker = read(session)
      clear!(session)
      return nil unless marker

      record_stop_event(session, marker, ended_by)
      marker
    end

    # Remove the marker and the request context WITHOUT auditing.
    #
    # Only for callers that are tearing the session down anyway (logout,
    # session destroy), that have already recorded their own event, or that
    # are UNWINDING a start whose fail-closed start event could not be written
    # (Auth::Operations::Customers::Impersonate) — there a stop! would record
    # an orphan stop for an impersonation that never took effect.
    #
    # @param session [#[], nil] Rack session
    # @return [nil]
    def clear!(session)
      session.delete(SESSION_KEY) if session.respond_to?(:delete)
      clear_context
      nil
    end

    # THE effective-identity decision. Every identity call site funnels through
    # here so "who is this request" has exactly one answer.
    #
    # Never raises and never rejects the session: an invalid impersonation ends
    # the OVERLAY and falls through to the principal. Failing the whole request
    # instead would strand the operator in a session they cannot use and cannot
    # fix (they would have to clear cookies to get their own account back).
    #
    # The principal's own suspension and credential-watermark checks are NOT
    # duplicated here — they stay on the principal at the call sites, where
    # they belong (a colonel suspended mid-impersonation must lose the whole
    # session, not just the overlay).
    #
    # @param session [#[], nil] Rack session
    # @param principal [Onetime::Customer, nil] customer loaded from
    #   session['external_id'] — the REAL operator
    # @param env [Hash, nil] Rack env, for the per-request target memo (see
    #   {TARGET_ENV_KEY}). Omitting it is correct but costs a reload.
    # @return [Array(Onetime::Customer, Hash), Array(Onetime::Customer, nil)]
    #   [effective_customer, marker_or_nil]
    def resolve(session, principal, env: nil)
      marker = active(session)
      return [principal, nil] unless marker

      ended_by = invalidation_reason(principal, marker, env)
      if ended_by
        stop!(session, ended_by: ended_by)
        return [principal, nil]
      end

      [load_target(marker, env), marker]
    rescue StandardError => ex
      # A resolver blowup must not authenticate anyone as anyone: fall back to
      # the principal, loudly.
      OT.le "[impersonation] resolve failed: #{ex.class}: #{ex.message}"
      [principal, nil]
    end

    # Load the target ONCE for this request and park it in env.
    #
    # Called by Middleware::ImpersonationContext so the first identity call
    # site of the request finds a warm memo instead of paying for the read,
    # and so anything downstream that wants the effective customer can take it
    # from env rather than re-deriving it.
    #
    # @param env [Hash] Rack env
    # @param marker [Hash] the live marker
    # @return [Onetime::Customer, nil]
    def preload_target(env, marker)
      load_target(marker, env)
    end

    # --- request-scoped context ------------------------------------------
    #
    # Published once per request by Middleware::ImpersonationContext so the
    # bootstrap serializer reads the SAME marker that decided the identity
    # actually served. A banner computed from a second read of the session
    # could disagree with it.

    # @param marker [Hash] the live marker
    # @param impersonator_extid [String, nil] session['external_id'] — the
    #   principal, which the marker deliberately does not duplicate
    # @return [Hash] the frozen context
    def set_context(marker, impersonator_extid: nil)
      Fiber[FIBER_KEY] = {
        'impersonation_id' => marker['id'],
        'impersonator_extid' => impersonator_extid.to_s,
        'target_extid' => marker['target_extid'],
        'target_email' => marker['target_email'],
        'started_at' => marker['started_at'].to_i,
        'expires_at' => marker['expires_at'].to_i,
      }.freeze
    end

    # @return [Hash, nil] frozen context, or nil when not impersonating
    def context
      Fiber[FIBER_KEY]
    end

    # @return [Boolean]
    def active_context?
      !context.nil?
    end

    # @return [nil]
    def clear_context
      Fiber[FIBER_KEY] = nil
    end

    private

    # @param session [#[], nil]
    # @return [Hash, nil] marker with string keys, or nil when absent/malformed
    def read(session)
      return nil unless session.respond_to?(:[])

      marker = session[SESSION_KEY]
      return nil unless marker.is_a?(Hash)
      return nil if marker['target_extid'].to_s.empty?

      marker
    end

    def expired?(marker)
      marker['expires_at'].to_i <= Familia.now.to_i
    end

    # Which precondition (if any) has gone away since the impersonation
    # started. Order matters only for the audit detail — any hit ends it.
    def invalidation_reason(principal, marker, env = nil)
      return ENDED_BY_COLONEL_DEMOTED unless operator?(principal)

      target = load_target(marker, env)
      return ENDED_BY_TARGET_MISSING unless target
      return ENDED_BY_TARGET_SUSPENDED if target.suspended?
      return ENDED_BY_TARGET_PRIVILEGED if target.role?('colonel')

      nil
    end

    # The overlay is only ever granted to a still-verified colonel. Re-checked
    # on EVERY request, so a demotion or an unverify takes the overlay away on
    # the next click rather than at the 30-minute mark.
    def operator?(principal)
      return false unless principal
      return false unless principal.role?('colonel')

      principal.respond_to?(:verified?) ? principal.verified? : true
    end

    # Resolved fresh per REQUEST rather than cached in the marker: suspension
    # and role are exactly the state that must not be snapshotted across
    # requests. Within one request the read is memoized in env, keyed on the
    # marker's target so it cannot outlive the marker it belongs to.
    def load_target(marker, env = nil)
      extid  = marker['target_extid']
      cached = env.is_a?(Hash) ? env[TARGET_ENV_KEY] : nil
      return cached[1] if cached.is_a?(Array) && cached[0] == extid

      target = fetch_target(extid)

      env[TARGET_ENV_KEY] = [extid, target] if env.is_a?(Hash)
      target
    end

    def fetch_target(extid)
      target = Onetime::Customer.load_by_extid_or_email(extid)
      return nil unless target
      return nil if target.respond_to?(:exists?) && !target.exists?

      target
    end

    # Actor is the PRINCIPAL (the real operator), read from the session rather
    # than from the marker — the marker never carries an actor, so no adapter
    # can fabricate one into the trail.
    def record_stop_event(session, marker, ended_by)
      actor    = session.respond_to?(:[]) ? session['external_id'].to_s : ''
      duration = Familia.now.to_i - marker['started_at'].to_i

      Onetime::ColonelAuditEvent.record(
        actor: actor.empty? ? nil : actor,
        verb: AUDIT_VERB_STOP,
        target: marker['target_extid'],
        result: :success,
        detail: {
          impersonation_id: marker['id'],
          ended_by: ended_by,
          duration_s: duration.negative? ? 0 : duration,
        },
      )
    rescue StandardError => ex
      # ColonelAuditEvent.record is already fail-open; this catches anything
      # raised while ASSEMBLING the event so a stop is never blocked by its
      # own bookkeeping.
      OT.le "[impersonation] stop audit failed: #{ex.class}: #{ex.message}"
    end
  end
end
