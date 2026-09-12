# apps/api/colonel/logic/colonel/reset_rate_limit.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/ratelimit/reset'
require 'onetime/operations/ratelimit/registry'

module ColonelAPI
  module Logic
    module Colonel
      # Reset (clear) a rate limiter's Redis state for one subject (Colonel).
      #
      # Thin adapter over {Onetime::Operations::RateLimit::Reset} — the single,
      # audited implementation whose keys the `bin/ots ratelimit keys` CLI also
      # emits as a `DEL` (ticket #44). This class keeps only the HTTP concerns
      # (param validation); the op owns the delete + the ColonelAuditEvent.
      #
      # Clearing a limiter lets a throttled subject act again, so the UI gates this
      # behind an AdminConfirmDialog typed-confirmation. A reset that actually
      # removed a key records EXACTLY ONE audit event (verb `ratelimit.reset`);
      # resetting an already-clear subject is an idempotent no-op that records none.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class ResetRateLimit < ColonelAPI::Logic::Base
        attr_reader :kind, :subject, :result

        def process_params
          @kind    = params['kind'].to_s.strip
          @subject = params['subject'].to_s.strip
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          raise_form_error('Limiter kind is required', field: :kind) if kind.empty?
          raise_form_error('Subject is required', field: :subject) if subject.empty?

          unless Onetime::Operations::RateLimit::Registry.known?(kind)
            raise_not_found("Unknown rate limiter: #{kind}")
          end

          # TIER 2 (#4326): a reset removes an active defence. The composed token
          # DEPENDS on the two required-field guards above — without them an
          # empty kind and subject would compose the non-blank string ":" and
          # slip past the blank-expected tripwire in require_confirmation!.
          guard_destructive_action!(
            tier: :sensitive,
            confirm_with: "#{kind}:#{subject}",
            confirm_subject: 'the limiter kind and subject joined by a colon',
            field: :kind,
          )

          refuse_self_colonel_reset!
        end

        # INTERLOCK (#4329 review): a colonel may not clear their OWN colonel_*
        # limiter over HTTP. Those buckets exist to bound the ACTING colonel:
        # colonel_elevation is the sole backstop against step-up brute force
        # (Auth::Config.valid_login_and_password? is an internal request and never
        # trips Rodauth's own lockout — see colonel_rate_limiter.rb), colonel_destructive
        # keeps the tier-1 count under the audit cap, and colonel_mutation bounds
        # the surface. Self-clearing any of them from a cookie turns the bucket into
        # a no-op — brute-force elevation, reset, repeat — so recovery of one's own
        # colonel lockout is CLI-only (shell access is the higher bar the registry
        # already documents). Resetting a PEER colonel's bucket, or any non-colonel
        # limiter, is unaffected: that is the operator-recovery use case. The
        # confirmation token here is caller-supplied (kind:subject) and proves
        # nothing, so this guard — not the token — is what stops the loop.
        def refuse_self_colonel_reset!
          return unless kind.start_with?('colonel_')
          return unless subject == cust&.extid.to_s

          raise_form_error(
            'Refusing to clear your own colonel rate limiter over the API; a leaked ' \
            'colonel cookie could otherwise reset its own lockout in a loop. Clear it ' \
            "from the CLI instead (bin/ots ratelimit keys #{kind} #{subject}).",
            field: :subject,
          )
        end

        def process
          @result = Onetime::Operations::RateLimit::Reset.new(
            kind: kind,
            subject: subject,
            actor: cust.extid,
          ).call

          success_data
        end

        def success_data
          {
            record: {
              kind: result.kind,
              subject: result.subject,
              cleared: result.status == :success,
            },
            details: {
              deleted: result.deleted,
              message: result.status == :success ? 'Rate limiter reset' : 'No active rate-limit state to reset',
            },
          }
        end
      end
    end
  end
end
