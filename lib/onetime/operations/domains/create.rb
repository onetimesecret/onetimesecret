# lib/onetime/operations/domains/create.rb
#
# frozen_string_literal: true

# Domain-owned (app-scoped) operation — see decision D3 in
# lib/onetime/operations/README.md. Loaded at the call site (colonel logic +
# CLI), which run outside the app autoloaders, so require the audit model and
# the validation strategy explicitly (mirrors Repair / Transfer / Remove).
require 'onetime/models/admin_audit_event'
require 'onetime/audited_failure'
require 'onetime/domain_validation/strategy'

module Onetime
  module Operations
    module Domains
      # Register a custom domain against an organization — the SINGLE
      # implementation of the admin create verb.
      #
      # Adapters:
      #   - `POST /api/colonel/domains` (ColonelAPI::Logic::Colonel::CreateCustomDomain)
      #   - `bin/ots domains create DOMAIN --org ORG`
      #
      # Before this op existed, create was the ONE domain verb with no extracted
      # operation: the colonel logic class validated, created, requested the
      # certificate and wrote its own AdminAuditEvent inline, and there was no
      # CLI peer at all. A CLI-only reimplementation would have forked the audit
      # path, so the logic is centralised here and both adapters stay thin.
      #
      # ## Two entry points, one validation
      #
      # {#validate} is the pure, side-effect-free half (normalise + reject). The
      # HTTP adapter calls it from `raise_concerns` so a bad request is refused
      # before `process` runs; {#call} re-runs it (cheap: string + index reads)
      # so the CLI and any future caller cannot skip it. There is exactly one
      # copy of the rules.
      #
      # ## Audit (CONTRACT 4)
      #
      # Exactly ONE {Onetime::AdminAuditEvent} per successful create, emitted
      # here. Adapters MUST NOT audit. A rejected create (invalid / duplicate)
      # mutates nothing but records one `result: :failure` event — a refused
      # attempt to attach a domain to an org is exactly what an operator
      # reviewing the trail needs to see, and `duplicate_other_org` in
      # particular is a takeover-shaped signal. Certificate provisioning failures
      # are logged but do NOT roll back or suppress the audit event — the domain
      # record exists and cert issuance is retryable via
      # `POST /api/colonel/domains/:extid/verify`.
      #
      # ## Deliberate omission
      #
      # There is NO membership / entitlement gate. A colonel attaches a domain to
      # an org they are not a member of; that is the whole point of the verb. The
      # role gate lives at the adapter (router `role=colonel` +
      # `verify_one_of_roles!`), and the CLI is already a root-shell surface.
      class Create
        include Onetime::AuditedFailure

        AUDIT_VERB = 'domain.create'

        # Bound on the failure target. `@domain_input` is raw operator text and
        # `target` is NOT length-capped by AdminAuditEvent (only `detail` is), so
        # an :invalid rejection could otherwise write an unbounded string. 253 is
        # the max FQDN length — anything a valid domain could ever need.
        MAX_TARGET_LENGTH = 253

        # Rejection reasons, mapped to the operator-facing message the incumbent
        # colonel endpoint has always returned. Adapters render these verbatim so
        # the HTTP contract does not shift under the frontend.
        REJECTIONS = {
          blank: 'Please enter a domain',
          invalid: 'Not a valid public domain',
          overlaps_canonical: 'This domain overlaps with the default site domain',
          duplicate_in_org: 'Domain already registered in this organization',
          duplicate_other_org: 'Domain is registered to another organization',
        }.freeze

        # Every rejection is a REFUSED privileged create, so each records one
        # `result: :failure` event. Derived from REJECTIONS so a new rejection
        # reason cannot silently escape the trail.
        REFUSAL_STATUSES = REJECTIONS.keys.freeze

        # TARGET DEVIATION, READ THIS BEFORE CHANGING IT: the success event's
        # target is `domain.extid`, but on the failure path the CustomDomain
        # record does NOT EXIST — it was rejected, or `create!` blew up. There is
        # no `@domain` ivar (only `@domain_input`, the raw string), and a lambda
        # reading one would land silently as 'unknown'. So a failed create
        # targets the FQDN: the normalised display_domain once validation has
        # produced one, else the (length-bounded) raw input. An FQDN is a public
        # identity — this is not a downgrade in identifiability, only in shape.
        #
        # create! atomically claims the display_domain index; anything other than
        # the rejections above raises, and the success record sits after it.
        audit_failures :call,
          verb: AUDIT_VERB,
          target: -> { failure_target },
          detail: -> { { org_id: @org&.extid, display_domain: failure_target } }

        # Outcome of {#validate}.
        #
        # @!attribute status [r] Symbol — :ok, or one of {REJECTIONS}' keys.
        # @!attribute display_domain [r] String, nil — normalised FQDN when :ok.
        # @!attribute message [r] String, nil — operator-facing rejection text.
        # @!attribute claims_orphan [r] Boolean — true when an existing orphaned
        #   record (no org_id) will be claimed rather than a new one created.
        Check = Data.define(:status, :display_domain, :message, :claims_orphan)

        # Outcome of {#call}.
        #
        # @!attribute status [r] Symbol — :created, or a rejection key.
        # @!attribute domain [r] Onetime::CustomDomain, nil
        # @!attribute cert_status [r] String, nil — strategy result, 'error', or
        #   nil when no certificate request was attempted.
        Result = Data.define(
          :status,
          :domain,
          :domain_id,
          :extid,
          :display_domain,
          :message,
          :claims_orphan,
          :cert_status,
        )

        # @param domain [String] raw operator input (adapter pre-sanitises HTML).
        # @param org [Onetime::Organization] target org (adapter resolves; required).
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity
        #   (colonel extid, or the CLI sentinel). Never an internal objid.
        # @param request_certificate [Boolean] kick off SSL provisioning through
        #   the configured strategy after a successful create (default true).
        def initialize(domain:, org:, actor:, request_certificate: true)
          @domain_input        = domain.to_s.strip
          @org                 = org
          @actor               = actor
          @request_certificate = request_certificate
        end

        # Pure validation + normalisation. No writes, no audit.
        #
        # @return [Check]
        def validate
          return reject(:blank) if @domain_input.empty?
          return reject(:invalid) unless Onetime::CustomDomain.valid?(@domain_input)
          return reject(:overlaps_canonical) if Onetime::CustomDomain.overlaps_canonical_domain?(@domain_input)

          display_domain = Onetime::CustomDomain.parse(@domain_input, @org.objid).display_domain

          existing = Onetime::CustomDomain.load_by_display_domain(display_domain)
          return Check.new(status: :ok, display_domain: display_domain, message: nil, claims_orphan: false) unless existing

          # Pre-check duplicates for a precise message; create! re-checks the
          # same three cases atomically at the write gate.
          return reject(:duplicate_in_org, display_domain) if existing.org_id.to_s == @org.objid.to_s
          return reject(:duplicate_other_org, display_domain) unless existing.org_id.to_s.empty?

          # Orphaned record (no org_id): create! claims it atomically.
          Check.new(status: :ok, display_domain: display_domain, message: nil, claims_orphan: true)
        end

        # @return [Result]
        def call
          check           = validate
          # Memoised for the failure paths: once validation has normalised the
          # FQDN it is a better audit target than the raw input, and by the time
          # create! can raise it is always set.
          @display_domain = check.display_domain
          return rejected_result(check) unless check.status == :ok

          # Atomicity: the #validate duplicate/orphan pre-checks run in a
          # separate step and can race a concurrent request — they are advisory
          # (for precise field errors), NOT for correctness. create! is the sole
          # atomic gate: HSETNX on display_domain_index claims a new domain, and
          # claim_orphaned_domain uses a pinned-connection WATCH/MULTI to claim
          # an orphan. The concurrent request that loses the gate gets an
          # Onetime::Problem raised here, so no double-registration occurs.
          domain = Onetime::CustomDomain.create!(check.display_domain, @org.objid)
          cert   = @request_certificate ? provision_certificate(domain) : nil

          # Exactly one audit event per successful create. Public ids only.
          Onetime::AdminAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: domain.extid,
            result: :success,
            detail: {
              org_id: @org.extid,
              display_domain: domain.display_domain,
            },
          )

          OT.info "[Domains::Create] #{domain.display_domain} -> org=#{@org.extid} extid=#{domain.extid}"

          Result.new(
            status: :created,
            domain: domain,
            domain_id: domain.domainid,
            extid: domain.extid,
            display_domain: domain.display_domain,
            message: nil,
            claims_orphan: check.claims_orphan,
            cert_status: cert,
          )
        end

        private

        # The FQDN this call was about, for the failure paths only. Prefers the
        # normalised display_domain; falls back to the bounded raw input (a
        # :blank/:invalid rejection has no normalised form).
        def failure_target
          value = @display_domain.to_s
          value = @domain_input.to_s if value.empty?
          value[0, MAX_TARGET_LENGTH]
        end

        # Same verb/actor as the success event; see the TARGET DEVIATION note on
        # audit_failures for why the target is the FQDN rather than an extid.
        # Best-effort: never break the op.
        def record_refusal(check)
          Onetime::AdminAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: failure_target,
            result: :failure,
            detail: {
              reason: check.status.to_s,
              org_id: @org&.extid,
              display_domain: failure_target,
            },
          )
        rescue StandardError => ex
          OT.le "[Domains::Create] refusal audit failed: #{ex.class}: #{ex.message}"
        end

        # Certificate provisioning is best-effort: the domain record already
        # exists and issuance is retryable, so a failure is logged and reported
        # in the Result rather than raised (unchanged from the incumbent colonel
        # behaviour).
        #
        # @return [String, nil] strategy status, or 'error' when it blew up.
        def provision_certificate(domain)
          strategy = Onetime::DomainValidation::Strategy.for_config(OT.conf)
          result   = strategy.request_certificate(domain)

          OT.info "[Domains::Create.request_certificate] #{domain.display_domain} -> #{result[:status]}"

          if result[:data]
            domain.vhost   = result[:data].to_json
            domain.updated = OT.now.to_i
            domain.save
          end

          result[:status].to_s
        rescue StandardError => ex
          OT.le "[Domains::Create] certificate request failed for #{domain.display_domain}: #{ex.message}"
          'error'
        end

        def reject(status, display_domain = nil)
          Check.new(
            status: status,
            display_domain: display_domain,
            message: REJECTIONS.fetch(status),
            claims_orphan: false,
          )
        end

        # Single exit point for every rejection, so the refusal audit cannot be
        # forgotten at one of the five early returns in #validate.
        def rejected_result(check)
          record_refusal(check) if REFUSAL_STATUSES.include?(check.status)

          Result.new(
            status: check.status,
            domain: nil,
            domain_id: nil,
            extid: nil,
            display_domain: check.display_domain,
            message: check.message,
            claims_orphan: false,
            cert_status: nil,
          )
        end
      end
    end
  end
end
