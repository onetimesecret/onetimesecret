# apps/web/auth/operations/customers/set_suspension.rb
#
# frozen_string_literal: true

require 'onetime/models/admin_audit_event'
require 'onetime/operations/sessions/store'

module Auth
  module Operations
    module Customers
      # Suspend / unsuspend a customer — the trust & safety "pause button".
      #
      # The ONE implementation of the suspension verb. The colonel
      # `SuspendUser` / `UnsuspendUser` Logic classes are thin adapters over
      # it. This is a MUTATING admin op, so it records exactly one
      # AdminAuditEvent per successful change (epic #20 CONTRACT 4 / #21). An
      # idempotent no-op (already in the target state) mutates nothing and is
      # therefore not audited.
      #
      # ## Reversible by design (unlike purge)
      #
      # Suspension destroys NO data: it flips `suspended` to 'true' and stamps
      # who/when/why. Unsuspending clears all of it. The enforcement lives at
      # the auth layer — login (Core::Logic::Authentication::AuthenticateSession)
      # rejects suspended customers after credential verification, and
      # BaseSessionAuthStrategy refuses their sessions on every request — so
      # the account is dead-on-arrival from the moment the flag is set.
      #
      # ## Session revocation is best-effort hygiene, not the enforcement
      #
      # Suspending also sweeps the session store (the same bounded scan as
      # Onetime::Operations::Sessions::List) and deletes any session whose
      # payload matches the customer's extid or email. Production session
      # payloads are encrypted, so this sweep cannot see inside them — which is
      # fine: the auth-strategy check above rejects those sessions on their
      # next request regardless. The sweep just removes the plainly-readable
      # ones immediately.
      #
      # ## Privilege guard
      #
      # Colonel accounts cannot be suspended ({PrivilegedAccount}) — otherwise
      # one compromised/rogue colonel could lock out every other operator.
      # Demote first (customers role), then suspend.
      class SetSuspension
        include Onetime::LoggerMethods

        AUDIT_VERB_SUSPEND   = 'customer.suspend'
        AUDIT_VERB_UNSUSPEND = 'customer.unsuspend'

        # Raised when asked to suspend a colonel-role account. Adapters catch
        # this (colonel -> form error). It is also a backstop: adapters should
        # validate up front for good UX.
        class PrivilegedAccount < StandardError; end

        # @!attribute status [r]
        #   @return [Symbol] :success (state changed) or :no_change (already there)
        Result = Data.define(:status, :customer, :suspended, :sessions_revoked)

        # @param customer [Onetime::Customer] target (caller ensures non-nil,
        #   non-anonymous)
        # @param suspended [Boolean] target state
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity
        #   (colonel extid/email, or a CLI sentinel). Never an internal objid.
        # @param reason [String, nil] optional operator-supplied reason (stored
        #   on the customer and in the audit detail; cleared on unsuspend)
        # @param dbclient [Object, nil] Redis-like client for the session sweep;
        #   defaults to Familia.dbclient.
        def initialize(customer:, suspended:, actor:, reason: nil, dbclient: nil)
          @customer  = customer
          @suspended = suspended ? true : false
          @actor     = actor
          reason     = reason.to_s.strip
          @reason    = reason.empty? ? nil : reason
          @dbclient  = dbclient
        end

        # @return [Result]
        # @raise [PrivilegedAccount] when suspending a colonel-role account
        def call
          if @suspended && @customer.role.to_s == 'colonel'
            raise PrivilegedAccount, 'Colonel accounts cannot be suspended. Demote the role first.'
          end

          if @customer.suspended? == @suspended
            return Result.new(status: :no_change, customer: @customer,
              suspended: @suspended, sessions_revoked: 0)
          end

          if @suspended
            @customer.suspended        = true
            @customer.suspended_at     = Familia.now.to_i
            @customer.suspended_by     = actor_label
            @customer.suspended_reason = @reason
          else
            @customer.suspended        = false
            @customer.suspended_at     = nil
            @customer.suspended_by     = nil
            @customer.suspended_reason = nil
          end
          @customer.save

          # Best-effort sweep AFTER the flag is saved: any session the sweep
          # cannot see (encrypted payload) is already rejected at the auth
          # layer, so ordering guarantees no window where a swept-but-not-yet
          # -suspended account could re-authenticate.
          sessions_revoked = @suspended ? revoke_sessions : 0

          # One audit event per successful mutation, emitted from the op layer.
          Onetime::AdminAuditEvent.record(
            actor: @actor,
            verb: @suspended ? AUDIT_VERB_SUSPEND : AUDIT_VERB_UNSUSPEND,
            target: @customer.extid,
            result: :success,
            detail: audit_detail(sessions_revoked),
          )

          # debug level (not info): the audit event is the durable record (see
          # SetRole for the CLI output-contract rationale).
          auth_logger.debug "[#{@suspended ? AUDIT_VERB_SUSPEND : AUDIT_VERB_UNSUSPEND}] " \
                            "#{@customer.extid} by #{actor_label}"

          Result.new(status: :success, customer: @customer,
            suspended: @suspended, sessions_revoked: sessions_revoked)
        end

        private

        def audit_detail(sessions_revoked)
          return { sessions_revoked: sessions_revoked } unless @suspended

          { reason: @reason, sessions_revoked: sessions_revoked }
        end

        # Delete every readable session belonging to this customer. Bounded by
        # construction: the same capped, string-typed cursor scan the session
        # listing uses (Sessions::Store — CONTRACT 6, never a blocking KEYS).
        # Deliberately does NOT route through Sessions::Delete: that op writes
        # one `session.delete` audit event per session, which would spam the
        # audit trail; here the single suspend event carries the revoked count.
        #
        # @return [Integer] number of session keys deleted
        def revoke_sessions
          store   = Onetime::Operations::Sessions::Store
          db      = @dbclient || Familia.dbclient
          revoked = 0

          store.scan_keys(db).each do |key|
            data = store.load_data(db, key)
            next unless data
            next unless matches_customer?(data)

            db.del(key)
            revoked += 1
          end

          revoked
        end

        # A session belongs to the customer when one of its identity fields
        # EXACTLY equals the customer's extid or email (case-insensitive).
        # Deliberately stricter than the search's substring predicate — a
        # substring match here could revoke a different customer's session
        # (e.g. a@b.com would substring-match aa@b.com's session).
        def matches_customer?(data)
          identities = [
            data['email'],
            data['external_id'],
            data['account_external_id'],
          ].compact.map { |value| value.to_s.downcase }

          [@customer.extid, @customer.email].any? do |needle|
            needle = needle.to_s.downcase
            !needle.empty? && identities.include?(needle)
          end
        end

        # Loggable, non-secret actor label (mirrors the audit actor normalization).
        def actor_label
          return @actor if @actor.is_a?(String)
          return @actor.extid if @actor.respond_to?(:extid) && !@actor.extid.to_s.empty?
          return @actor.email if @actor.respond_to?(:email)

          @actor.to_s
        end
      end
    end
  end
end
