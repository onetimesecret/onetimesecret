# lib/onetime/operations/email/send_test.rb
#
# frozen_string_literal: true

# Central (cross-cutting) admin operation — see decision D3 in
# lib/onetime/operations/README.md. Email delivery diagnostics have no single
# domain owner (the mailer is site-wide infrastructure), so — like
# {Onetime::Operations::BanIP} and {Onetime::Operations::Banner} — this lives in
# the central operations home. Loaded at the call site (colonel logic + the
# `bin/ots email test` CLI), so require the audit dependency explicitly.
require 'socket'
require 'onetime/mail'
require 'onetime/models/admin_audit_event'

module Onetime
  module Operations
    module Email
      # Send a plain-text diagnostic email to verify delivery connectivity — the
      # SINGLE, audited implementation of the email test-send verb (ticket #44 /
      # CONTRACT 4). The colonel endpoint (`POST /api/colonel/email/test`) and the
      # `bin/ots email test` CLI are thin adapters over it.
      #
      # ## Behavioural parity (bit-for-bit)
      #
      # {.build} constructs the EXACT diagnostic email the CLI built inline before
      # this extraction (same brand-aware subject/body, same provider/host probe),
      # so the CLI's rendered output stays byte-identical. The CLI keeps its own
      # timing + status-line printing and simply routes the actual send through
      # this op; the op adds exactly one thing the inline send lacked: one
      # {Onetime::AdminAuditEvent} per SUCCESSFUL real send.
      #
      # ## Audit rule (CONTRACT 4)
      #
      # A real send that succeeds records EXACTLY ONE audit event (verb
      # `email.test_send`, actor = PUBLIC id, target = recipient). A dry-run sends
      # nothing and records none. A send that RAISES (delivery failure) never
      # reaches the audit call, so a failed send records none either — "only audit
      # an actual, successful mutation". Delivery exceptions are NOT swallowed: they
      # propagate to the caller so the CLI's existing rescue blocks (and the colonel
      # logic's form-error handling) behave exactly as before.
      class SendTest
        # Audit verb recorded for every successful real send.
        AUDIT_VERB = 'email.test_send'

        # The fully-built diagnostic email plus the delivery context the CLI prints.
        Diagnostic = Data.define(:to, :from, :subject, :text_body, :provider, :host, :timestamp)

        # @!attribute status [r]
        #   @return [Symbol] :dry_run (nothing sent), :sent (delivered / enqueued
        #     synchronously via fallback), or :enqueued (handed to the worker queue).
        Result = Data.define(:status, :diagnostic)

        # Build the diagnostic email verbatim (pure — no side effects, no audit).
        # Shared by the op's own {#call} AND by the CLI's pre-send output block, so
        # the two can never drift. Brand-aware copy: a hardcoded vendor literal
        # would leak into a white-label install's outbound test email (#3612).
        #
        # @param to [String] recipient email address.
        # @return [Diagnostic]
        def self.build(to:)
          provider  = Onetime::Mail::Mailer.send(:determine_provider)
          hostname  = Socket.gethostname
          timestamp = Time.now.utc.iso8601

          product_name = Onetime::CustomDomain::BrandSettingsConstants.global_defaults[:product_name] ||
                         Onetime::CustomDomain::BrandSettingsConstants::NEUTRAL_PRODUCT_NAME

          Diagnostic.new(
            to: to,
            from: Onetime::Mail::Mailer.from_address,
            subject: "[#{product_name}] Email delivery test - #{timestamp}",
            text_body: "This is a test email from the #{product_name} CLI.\n\nProvider: #{provider}\nTimestamp: #{timestamp}\nHost: #{hostname}",
            provider: provider,
            host: hostname,
            timestamp: timestamp,
          )
        end

        # @param to [String] recipient email address (caller validates format).
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity
        #   (colonel extid/email, or the CLI sentinel). Never an internal objid.
        # @param dry_run [Boolean] when true, build only — send nothing, audit none.
        # @param enqueue [Boolean] when true, dispatch via the background worker
        #   queue instead of direct delivery.
        def initialize(to:, actor:, dry_run: false, enqueue: false)
          @to      = to
          @actor   = actor
          @dry_run = dry_run
          @enqueue = enqueue
        end

        # @return [Result]
        # @raise [StandardError] delivery/enqueue failures propagate unchanged.
        def call
          diagnostic = self.class.build(to: @to)

          # Dry-run: preview only. Nothing is dispatched and nothing is audited.
          return Result.new(status: :dry_run, diagnostic: diagnostic) if @dry_run

          status = @enqueue ? enqueue!(diagnostic) : deliver!(diagnostic)

          # One audit event per successful real send. The recipient is the (public)
          # target; the body/subject are non-secret diagnostics but we record only
          # the provider + mode, never the message content.
          Onetime::AdminAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @to,
            result: :success,
            detail: { provider: diagnostic.provider, mode: status.to_s, enqueue: @enqueue },
          )

          Result.new(status: status, diagnostic: diagnostic)
        end

        private

        # Direct delivery via the configured backend. Raises on failure (caller's
        # rescue owns the FAILED output). Mirrors the pre-extraction CLI call.
        # @return [Symbol] :sent
        def deliver!(diagnostic)
          Onetime::Mail::Mailer.delivery_backend.deliver(email_hash(diagnostic))
          :sent
        end

        # Enqueue via the background worker. When jobs are disabled the publisher's
        # :raise fallback sends synchronously and returns falsey, which the CLI
        # renders as "SENT SYNC". Mirrors the pre-extraction CLI call.
        # @return [Symbol] :enqueued (handed to the queue) or :sent (fallback sync)
        def enqueue!(diagnostic)
          require 'onetime/jobs/publisher'

          raw_email = {
            to: diagnostic.to,
            from: diagnostic.from,
            subject: diagnostic.subject,
            body: diagnostic.text_body,
          }
          queued = Onetime::Jobs::Publisher.enqueue_email_raw(raw_email, fallback: :raise)
          queued ? :enqueued : :sent
        end

        def email_hash(diagnostic)
          {
            to: diagnostic.to,
            from: diagnostic.from,
            subject: diagnostic.subject,
            text_body: diagnostic.text_body,
          }
        end
      end
    end
  end
end
