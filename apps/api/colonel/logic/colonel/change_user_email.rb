# apps/api/colonel/logic/colonel/change_user_email.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative 'account_identifier'
require 'auth/operations/customers/change_email'

module ColonelAPI
  module Logic
    module Colonel
      # Change a user's account email address (Colonel) — #3731 PR-C3, D43.
      #
      # POST /api/colonel/users/:user_id/email
      # Body: { "new_email": "...", "dry_run": false, "reason": "...", "ticket": "..." }
      #
      # Thin adapter over {Auth::Operations::Customers::ChangeEmail} — the single
      # implementation of the cross-store swap (Rodauth `accounts` row, Customer
      # hash, global + org-scoped email indexes, default-workspace contact_email,
      # pending self-service change markers, session revocation, verification
      # reset). The OP owns the ColonelAuditEvent; this class NEVER audits — that
      # would double-record.
      #
      # Support works from the console, not the shell (D43), so this endpoint is
      # the console-side peer of `bin/ots customers change-email`.
      #
      # ## dry_run defaults to TRUE
      #
      # Same doctrine as {RemoveCustomDomain}: the screen previews (collision
      # check, org count, warnings), then re-issues with `dry_run: false` behind a
      # typed-confirmation dialog. This is the highest-value account-takeover
      # primitive an operator has; an unqualified POST must not mutate.
      #
      # ## Identifier sanitization
      #
      # BOTH `:user_id` and `:new_email` go through `sanitize_account_identifier`
      # (see {AccountIdentifier}). Plain `sanitize_identifier` strips `@` and `.`,
      # which would turn `user@example.com` into `userexamplecom` — silently
      # unresolvable as an identifier and silently mangled as a new address.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class ChangeUserEmail < ColonelAPI::Logic::Base
        include AccountIdentifier

        attr_reader :user_id, :new_email, :reason, :ticket, :dry_run, :notify, :keep_verified, :revoke_sessions, :user, :result

        def process_params
          # sanitize_account_identifier (NOT sanitize_identifier) on BOTH values.
          @user_id   = sanitize_account_identifier(params['user_id'])
          @new_email = sanitize_account_identifier(params['new_email'])

          @reason = sanitize_plain_text(params['reason']).to_s
          @ticket = sanitize_plain_text(params['ticket']).to_s

          # Destructive verb: preview unless the caller explicitly opts out.
          @dry_run = params.key?('dry_run') ? truthy?(params['dry_run']) : true

          # Safe defaults; the console may opt out per-case (a compromised-account
          # remediation must not mail the attacker-controlled old address).
          @notify          = params.key?('notify') ? truthy?(params['notify']) : true
          @keep_verified   = truthy?(params['keep_verified'])
          @revoke_sessions = params.key?('revoke_sessions') ? truthy?(params['revoke_sessions']) : true
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          raise_form_error('User ID is required', field: :user_id) if user_id.to_s.empty?
          raise_form_error('New email is required', field: :new_email) if new_email.to_s.empty?

          # Resolve by PUBLIC id (extid) first — the users list exposes only
          # extid — then email, then objid.
          @user = resolve_account(user_id)
          raise_not_found('User not found') unless user&.exists?

          raise_form_error('Cannot modify anonymous user', field: :user_id) if user.anonymous?
        end

        def process
          @result = Auth::Operations::Customers::ChangeEmail.new(
            customer: user,
            new_email: new_email,
            actor: cust.extid, # acting colonel's PUBLIC id (never an objid)
            dry_run: dry_run,
            require_verification: !keep_verified,
            revoke_sessions: revoke_sessions,
            notify: notify,
            reason: reason.empty? ? nil : reason,
            ticket: ticket.empty? ? nil : ticket,
          ).call

          # Logged BEFORE the status mapping so the outcomes that raise —
          # :partial above all — still leave a line behind.
          # Obscured on both sides: this reaches shipped logs.
          OT.info "[ChangeUserEmail] #{result.extid} status=#{result.status} dry_run=#{dry_run} " \
                  "#{OT::Utils.obscure_email(result.from.to_s)} -> " \
                  "#{OT::Utils.obscure_email(result.to.to_s)} warnings=#{result.warnings.inspect}"

          handle_result_status

          # NOTE: no audit here — the op owns the single ColonelAuditEvent.
          success_data
        end

        def success_data
          {
            record: {
              user_id: user.objid,
              extid: result.extid,
              email: OT::Utils.obscure_email(result.to.to_s),
              from: OT::Utils.obscure_email(result.from.to_s),
              to: OT::Utils.obscure_email(result.to.to_s),
              status: result.status.to_s,
            },
            details: {
              dry_run: result.dry_run,
              changed: result.status == :success,
              auth_row_updated: result.auth_row_updated,
              orgs_reindexed: result.orgs_reindexed,
              sessions_revoked: result.sessions_revoked,
              verification_reset: result.verification_reset,
              warnings: result.warnings.map(&:to_s),
              message: status_message,
            },
          }
        end

        private

        # Non-success statuses that mutated NOTHING are surfaced as 4xx form
        # errors. `:no_change` is an idempotent 200 and `:planned` is the preview.
        #
        # `:partial` and `:verification_not_reset` are the odd ones out and
        # neither MAY return 200. `:partial` means SQL committed and the Redis
        # side did not finish, so the two authoritative stores may disagree.
        # `:verification_not_reset` means the swap DID land but the account is
        # still flagged verified on an address nobody has proven ownership of —
        # the exact state `require_verification` exists to prevent, and one the
        # operator has to clear by hand. The logic base exposes no 5xx helper, so
        # both raise a form error whose message says what actually happened and
        # names the remediation; a silent 200 would tell the operator everything
        # is fine when it is not. The op has already recorded its audit event with
        # the matching result (D38), so the trail survives these raises.
        def handle_result_status
          case result.status
          when :invalid_email
            raise_form_error("Invalid email address: #{new_email}", field: :new_email)
          when :email_taken
            raise_form_error(
              'That email address is already in use by another account',
              field: :new_email,
            )
          when :not_found
            raise_not_found('User has no usable email address')
          when :partial
            # A partial whose Customer hash already committed ran the full
            # follow-up phase, so it can carry :verification_not_reset (or
            # :verification_still_set): the swap LANDED and the account is still
            # flagged verified on an unproven address. Telling that operator to
            # doctor-then-retry sends them the wrong way — the change already
            # stuck, and the obligation is the same "unverify now" the dedicated
            # status below spells out. The remaining warnings stay interpolated
            # either way: they are the only channel a colonel operator has,
            # where the CLI gets print_warnings for free.
            if result.warnings.intersect?([:verification_not_reset, :verification_still_set])
              raise_form_error(
                'PARTIAL: the email change LANDED but verification could not ' \
                "be reset: #{result.extid} is still marked verified on an " \
                'address nobody has proven they own. Do not retry the change — ' \
                "run `bin/ots customers unverify #{result.extid}` now, then " \
                '`bin/ots customers doctor` for the remaining drift.' \
                "#{warnings_suffix}",
                field: :new_email,
              )
            end

            raise_form_error(
              'PARTIAL: the email change did not complete and the auth database ' \
              'and Redis may now disagree. Run `bin/ots customers doctor` ' \
              "(check :auth_email_drift) before retrying.#{warnings_suffix}",
              field: :new_email,
            )
          when :verification_not_reset
            raise_form_error(
              "The email change APPLIED, but verification could not be reset: #{result.extid} " \
              'is still marked verified on an address nobody has proven they own. ' \
              "Do not retry the change — run `bin/ots customers unverify #{result.extid}` now." \
              "#{warnings_suffix}",
              field: :new_email,
            )
          end
        end

        # The op's partial() has one sub-case (no auth-row write, no Customer
        # commit) that appends nothing, so a bare "()" is reachable and reads
        # as a rendering bug rather than "no warnings".
        def warnings_suffix
          result.warnings.empty? ? '' : " (#{result.warnings.join(', ')})"
        end

        def status_message
          case result.status
          when :planned   then 'Preview only — no changes applied'
          when :success   then 'Email changed'
          when :no_change then 'User already uses that email address'
          else result.status.to_s
          end
        end

        def truthy?(value)
          %w[true 1 yes on].include?(value.to_s.strip.downcase)
        end
      end
    end
  end
end
