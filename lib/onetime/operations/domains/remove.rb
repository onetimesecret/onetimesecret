# lib/onetime/operations/domains/remove.rb
#
# frozen_string_literal: true

# Domain-owned (app-scoped) operation — mirrors Operations::Domains::Transfer.
# Loaded at the call site (colonel logic + CLI), so require deps explicitly.
require 'onetime/models/admin_audit_event'
require 'onetime/domain_validation/strategy'
require 'onetime/operations/delete_sender_domain'

module Onetime
  module Operations
    module Domains
      # Remove (permanently delete) a custom domain — the SINGLE toolbox
      # implementation of the remove verb (#3731 P3). The colonel endpoint
      # (DELETE /api/colonel/domains/:extid) and 'bin/ots domains remove' are
      # thin adapters over it. Mirrors the Transfer op: dry_run:true default,
      # exactly-once AdminAuditEvent emitted FROM THE OP ONLY, Result Data.
      #
      # ## Teardown parity
      #
      # The apply path mirrors DomainsAPI::Logic::Domains::RemoveDomain#process
      # VERBATIM: delete the external vhost (strategy), delete the external sender
      # identity BEFORE destroy! wipes mailer_config, then destroy!. It does NOT
      # call org.remove_domain — CustomDomain#destroy! already removes org
      # participation internally (custom_domain.rb:457-460); adding it would be a
      # redundant second removal against the same collection.
      #
      # ## display_domain_index re-assertion (the crux)
      #
      # CustomDomain#destroy! ends in a bare 'super' (Familia) whose transaction
      # UNCONDITIONALLY HDELs display_domain_index[fqdn], keyed on THIS record's
      # own display_domain, with NO check of which objid the entry holds
      # (unique_index_generators). Two live records cannot legitimately share one
      # FQDN (create! gates on HSETNX), but a drift-produced SHADOW hash can
      # coexist while the index points at the single canonical owner. If we are
      # removing such a shadow, destroy!'s blind HDEL wipes the survivor's
      # pointer. So: snapshot index_owner_id = display_domain_index.get(fqdn) and
      # victim_objid = domain.objid BEFORE destroy!, then AFTER destroy! re-assert
      # ONLY when index_owner_id is present AND != victim_objid (reload the
      # survivor + confirm its display_domain still == fqdn before re-pointing).
      class Remove
        AUDIT_VERB = 'domain.remove'

        # @!attribute status [r] Symbol — :planned (dry-run) | :removed (applied)
        Result = Data.define(
          :status,
          :domain_id,
          :extid,
          :display_domain,
          :org_id,
          :org_name,
          :dry_run,
          :reasserts_survivor,
        )

        # @param domain [Onetime::CustomDomain] resolved target (caller ensures non-nil).
        # @param actor [String, #extid] acting principal's PUBLIC id (colonel extid
        #   or the 'cli' sentinel) — never an objid.
        # @param dry_run [Boolean] preview only when true (default).
        def initialize(domain:, actor:, dry_run: true)
          @domain  = domain
          @actor   = actor
          @dry_run = dry_run
        end

        # @return [Result]
        def call
          org_id = @domain.org_id
          org    = org_id.to_s.empty? ? nil : Onetime::Organization.load(org_id)

          # --- INDEX SNAPSHOT (before ANY mutation) ---
          index          = Onetime::CustomDomain.display_domain_index
          fqdn           = @domain.display_domain.to_s.downcase
          victim_objid   = @domain.objid
          index_owner_id = fqdn.empty? ? nil : index.get(fqdn)  # .get => plain objid string
          reasserts      = !fqdn.empty? && !index_owner_id.nil? && index_owner_id != victim_objid

          # Build the full Result NOW, before destroy! nils the domain's fields.
          plan = Result.new(
            status: :planned,
            domain_id: @domain.domainid,
            extid: @domain.extid,
            display_domain: @domain.display_domain,
            org_id: org_id,
            org_name: org&.display_name,
            dry_run: @dry_run,
            reasserts_survivor: reasserts,
          )

          # --- DRY RUN: preview only, mutate nothing, audit nothing ---
          return plan if @dry_run

          # --- APPLY: teardown mirrors RemoveDomain#process (NO org.remove_domain) ---
          delete_vhost(@domain)
          Onetime::Operations::DeleteSenderDomain.new(mailer_config: @domain.mailer_config).call
          @domain.destroy! # Familia 'super' HDELs display_domain_index[fqdn] here

          # --- CONDITIONAL INDEX RE-ASSERTION ---
          # Best-effort: destroy! has already committed, so a failure here must
          # NOT abort the call — that would skip the audit of a destroy that DID
          # happen and leave the action untraced. On any error we log and press
          # on; a cleared survivor pointer is recoverable by the index-rebuild
          # maintenance job. (The re-assert is also not atomic with destroy!'s
          # HDEL: a concurrent lookup in that sub-ms window sees nil — acceptable
          # on this single-actor drift-repair path.)
          if reasserts
            begin
              survivor = Onetime::CustomDomain.load(index_owner_id)
              if survivor && survivor.display_domain.to_s.downcase == fqdn
                index.put(fqdn, index_owner_id)
                OT.info "[Domains::Remove] Re-asserted display_domain_index[#{fqdn}] -> " \
                        "#{index_owner_id} (survivor) after destroying shadow #{victim_objid}"
              else
                OT.le "[Domains::Remove] display_domain_index[#{fqdn}] owner #{index_owner_id} " \
                      "no longer valid after destroying #{victim_objid}; leaving entry cleared"
              end
            rescue StandardError => ex
              OT.le "[Domains::Remove] re-assertion of display_domain_index[#{fqdn}] failed " \
                    "after destroying shadow #{victim_objid}: #{ex.class} #{ex.message}"
            end
          end

          # --- EXACTLY ONE audit event, applied path only ---
          Onetime::AdminAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: plan.extid,
            result: :success,
            detail: { org_id: org_id.to_s, reasserted: reasserts },
          )

          plan.with(status: :removed)
        end

        private

        # Mirrors RemoveDomain#delete_vhost: no-op for non-Approximated strategies,
        # swallows provider/transport errors so removal proceeds regardless.
        def delete_vhost(domain)
          strategy = Onetime::DomainValidation::Strategy.for_config(OT.conf)
          result   = strategy.delete_vhost(domain)
          OT.info "[Domains::Remove.delete_vhost] #{domain.display_domain} -> #{result && result[:message]}"
        rescue HTTParty::ResponseError, Timeout::Error, Errno::ECONNREFUSED => ex
          OT.le "[Domains::Remove.delete_vhost error] #{domain.display_domain} #{ex}"
        end
      end
    end
  end
end
