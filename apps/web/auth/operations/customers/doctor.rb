# apps/web/auth/operations/customers/doctor.rb
#
# frozen_string_literal: true

require 'onetime/models/admin_audit_event'
require 'onetime/audited_failure'

module Auth
  module Operations
    module Customers
      # Customer data-integrity checks (and optional repair).
      #
      # The ONE implementation of the per-customer integrity checks and the
      # email_index integrity check. The `bin/ots customers doctor` command is a
      # thin adapter: it owns orchestration (scan-all, output formatting, exit
      # codes) and delegates the actual checks + repairs to this op, so the check
      # logic lives in exactly one place.
      #
      # ## Audit (epic #20 CONTRACT 4)
      #
      # Repairs mutate customer records, so a repaired customer records ONE
      # AdminAuditEvent (summarizing the repair actions) when an `actor` is
      # supplied and `repair: true`. It is one event per repaired customer (not per
      # field, and never on audit-only runs), which keeps the capped audit set
      # bounded even on a `--all --repair` sweep. Per-action OT.info logging is
      # unchanged and remains the fine-grained trail.
      #
      # ## Email-drift checks (#3731 PR-C1)
      #
      # Three checks exist specifically to make a half-completed email change
      # visible: `:auth_email_drift` (the ONLY Redis-vs-SQL comparison here — a
      # `ChangeEmail` op returning `:partial` is invisible without it),
      # `:org_email_index_stale` (the org-scoped index, which Familia never
      # auto-populates) and `:org_contact_email_stale` (default workspaces still
      # contacting a dead address). See each method for its scoping rules.
      #
      # NOTE: `VALID_ROLES` here is intentionally the doctor's own narrower set
      # ([customer, anonymous, colonel]) — the historical data-shape checker — and
      # is deliberately NOT the assignable-role list in SetRole::VALID_ROLES. They
      # answer different questions and must not be merged (preserved bit-for-bit).
      # rubocop:disable Metrics/ClassLength
      class Doctor
        include Onetime::LoggerMethods

        # Recorded on a REPAIR run only — never on a diagnostic pass. Shared by
        # the success and failure events so both land under one filter.
        AUDIT_VERB = 'customer.doctor_repair'

        SEVERITY_ORDER = { critical: 0, high: 1, medium: 2, warning: 3, low: 4 }.freeze

        # Valid customer roles (historical data-shape check — see NOTE above)
        VALID_ROLES = %w[customer anonymous colonel].freeze

        # Valid verified_by values
        VALID_VERIFIED_BY = %w[email stripe_payment autoverify].freeze

        # Counter fields to check
        COUNTER_FIELDS = [:secrets_created, :secrets_burned, :secrets_shared, :emails_sent].freeze

        # Per-customer result. `issues` is severity-sorted; `repaired` is the list
        # of repair-action hashes applied (empty unless repair: true).
        Report = Data.define(:issues, :repaired)

        # @param customer [Onetime::Customer] the customer to check
        # @param repair [Boolean] apply auto-repairs (default: audit only)
        # @param actor [String, #extid, #email, nil] acting admin's PUBLIC identity;
        #   when present and a repair is applied, one audit event is recorded
        def initialize(customer:, repair: false, actor: nil)
          @customer = customer
          @repair   = repair
          @actor    = actor
        end

        # Run all per-customer checks. Returns a Report; the caller aggregates.
        # @return [Report]
        def call
          issues   = []
          repaired = []

          check_orphan_default_org(issues, repaired)
          check_email_index_entry(issues, repaired)
          check_auth_email_drift(issues, repaired)
          check_org_email_index(issues, repaired)
          check_org_contact_email(issues, repaired)
          check_org_membership_sync(issues, repaired)
          check_role_validity(issues)
          check_verified_consistency(issues, repaired)
          check_counter_sanity(issues, repaired)
          check_field_serialization(issues, repaired)

          audit_repair(repaired) if @repair && repaired.any?

          Report.new(issues: issues.sort_by { |i| SEVERITY_ORDER[i[:severity]] }, repaired: repaired)
        rescue StandardError => ex
          # DELIBERATELY NOT the `audit_failures` macro (see audited_failure.rb).
          # The macro records unconditionally, and this op's DEFAULT mode is a
          # pure diagnostic read: wrapping it would emit an audit event for a
          # failed `bin/ots customers doctor` with no --repair, breaking
          # CONTRACT 4 (viewing never writes). Worse, the doctor runs per
          # customer on a `--all` sweep, so a systemic read failure would write
          # one event per customer and evict the real destructive-action trail
          # from the count-capped set.
          #
          # So the failure is recorded on exactly the same gate as the success
          # event: a REPAIR run with a known actor. A repair that blew up
          # partway is a mutation left in an unknown state, and that must be in
          # the trail. The record helper is shared, only the gate is bespoke.
          audit_repair_failure(ex) if @repair && !@actor.nil?
          raise
        end

        # Index-level check: email_index entries point to live customers with the
        # right email. Returns { issues:, repaired: }. Cross-customer, so it is a
        # class method rather than a per-customer instance check.
        #
        # @param repair [Boolean]
        # @return [Hash] { issues: Array, repaired: Array }
        def self.check_email_index(repair:)
          issues         = []
          repaired       = []
          stale_count    = 0
          mismatch_count = 0

          Onetime::Customer.email_index.hgetall.each do |email, objid|
            customer = Onetime::Customer.load(objid)

            if customer.nil?
              stale_count += 1
              if repair
                Onetime::Customer.email_index.remove_field(email)
                OT.info "[customers doctor] Removed orphan email_index[#{email}] -> #{objid}"
              end
            elsif customer.email.to_s.downcase != email.downcase
              issues << {
                check: :email_index_mismatch,
                severity: :high,
                message: "email_index[#{email}] -> customer with email #{customer.email}",
                email: email,
                customer_objid: objid,
                actual_email: customer.email,
                repairable: true,
              }

              if repair
                # Set correct entry before removing wrong one so there's no window with a missing key
                Onetime::Customer.email_index[customer.email] = objid
                Onetime::Customer.email_index.remove_field(email)
                OT.info "[customers doctor] Fixed email_index: #{email} -> #{customer.email} -> #{objid}"
                mismatch_count                               += 1
              end
            end
          end

          if stale_count.positive?
            if repair
              repaired << {
                action: :email_index_orphans_cleaned,
                count: stale_count,
              }
            else
              issues << {
                check: :email_index_stale,
                severity: :high,
                message: "#{stale_count} email_index entries point to deleted customers",
                count: stale_count,
                repairable: true,
              }
            end
          end

          if mismatch_count.positive?
            repaired << {
              action: :email_index_mismatches_fixed,
              count: mismatch_count,
            }
          end

          { issues: issues.sort_by { |i| SEVERITY_ORDER[i[:severity]] }, repaired: repaired }
        end

        private

        # CHECK: default_org_id points to existing org that customer is member of
        def check_orphan_default_org(issues, repaired)
          return if @customer.default_org_id.to_s.empty?

          organization = Onetime::Organization.load(@customer.default_org_id)

          if organization.nil?
            issues << {
              check: :orphan_default_org,
              severity: :critical,
              message: "default_org_id '#{@customer.default_org_id}' points to deleted organization",
              repairable: true,
              repair_action: 'Clear default_org_id field',
            }

            if @repair
              @customer.default_org_id = nil
              @customer.save
              OT.info "[customers doctor] Cleared default_org_id for #{@customer.extid}"
              repaired << {
                customer: @customer.extid,
                action: :default_org_cleared,
                reason: :org_deleted,
              }
            end
            return
          end

          # Org exists but customer may not be a member
          return if organization.member?(@customer)

          issues << {
            check: :orphan_default_org,
            severity: :critical,
            message: "default_org_id '#{@customer.default_org_id}' points to org customer is not a member of",
            repairable: true,
            repair_action: 'Clear default_org_id field',
          }

          return unless @repair

          @customer.default_org_id = nil
          @customer.save
          OT.info "[customers doctor] Cleared default_org_id for #{@customer.extid} (not a member)"
          repaired << {
            customer: @customer.extid,
            action: :default_org_cleared,
            reason: :not_member,
          }
        end

        # CHECK: email_index entry exists and matches
        def check_email_index_entry(issues, repaired)
          return if @customer.email.to_s.empty?

          indexed_objid = Onetime::Customer.email_index[@customer.email]

          if indexed_objid.nil?
            issues << {
              check: :email_index_missing,
              severity: :high,
              message: "no email_index entry for #{@customer.obscure_email}",
              repairable: true,
              repair_action: 'Add email_index entry',
            }

            if @repair
              Onetime::Customer.email_index[@customer.email] = @customer.objid
              OT.info "[customers doctor] Added email_index[#{@customer.email}] -> #{@customer.objid}"
              repaired << {
                customer: @customer.extid,
                action: :email_index_added,
              }
            end
          elsif indexed_objid != @customer.objid
            issues << {
              check: :email_index_mismatch,
              severity: :high,
              message: "email_index[#{@customer.obscure_email}] points to #{indexed_objid}, expected #{@customer.objid}",
              repairable: true,
              repair_action: 'Fix email_index entry',
            }

            if @repair
              Onetime::Customer.email_index[@customer.email] = @customer.objid
              OT.info "[customers doctor] Fixed email_index[#{@customer.email}] -> #{@customer.objid}"
              repaired << {
                customer: @customer.extid,
                action: :email_index_fixed,
              }
            end
          end
        end

        # CHECK: the Rodauth accounts row agrees with the Customer record
        #
        # THE ONLY CROSS-STORE CHECK IN THIS DOCTOR. Every other check compares
        # Redis against Redis, which means a half-completed cross-store email
        # change (Auth::Operations::Customers::ChangeEmail returning `:partial`)
        # was previously UNDETECTABLE: Redis is internally consistent on one
        # address while Postgres holds the other, so the customer signs in with an
        # address the app does not show them (or vice versa).
        #
        # Direction of repair is Redis -> SQL only. The Customer record is what
        # every Redis index is keyed against; rewriting it to match SQL would
        # invalidate `customer:email_index`, the org-scoped index and the org
        # contact index in one move. Pushing the Customer's address into
        # `accounts` reconciles authentication to what the rest of the system
        # already believes.
        #
        # A MISSING accounts row is deliberately not reported here — that is a
        # provisioning gap, not drift, and `bin/ots customers sync-auth-accounts`
        # owns it.
        #
        # COST: one SQL round trip per customer. On a `--all` sweep over a large
        # authdb this is the dominant cost of the doctor run. Skipped entirely in
        # simple mode (no auth database).
        def check_auth_email_drift(issues, repaired)
          db = auth_db
          return if db.nil?

          extid = @customer.extid.to_s
          return if extid.empty?
          return if @customer.email.to_s.empty?

          account = db[:accounts].where(external_id: extid).select(:id, :email).first
          return if account.nil?

          sql_email = account[:email].to_s
          return if sql_email.downcase == @customer.email.to_s.downcase

          issues << {
            check: :auth_email_drift,
            severity: :critical,
            message: "auth account email #{OT::Utils.obscure_email(sql_email)} != customer email " \
                     "#{@customer.obscure_email} (cross-store split-brain)",
            auth_email: OT::Utils.obscure_email(sql_email),
            repairable: true,
            repair_action: 'Write the Customer email into the Rodauth accounts row',
          }

          return unless @repair

          db.transaction do
            db[:accounts].where(id: account[:id]).update(
              email: @customer.email, updated_at: Sequel::CURRENT_TIMESTAMP,
            )
          end
          OT.info "[customers doctor] Repaired auth email drift for #{@customer.extid}"
          repaired << {
            customer: @customer.extid,
            action: :auth_email_drift_repaired,
          }
        rescue StandardError => ex
          # A doctor check must never abort the sweep over one unreachable DB.
          OT.le "[customers doctor] auth_email_drift check failed for #{@customer.extid}: " \
                "#{ex.class} #{ex.message}"
        end

        # CHECK: the ORG-SCOPED email index (organization:<objid>:email_index)
        #
        # Distinct from check_email_index_entry, which only ever looks at the
        # GLOBAL `customer:email_index`. The org-scoped index is not
        # auto-populated on save (Familia only auto-adds class-level indexes), so
        # it is the first thing to go stale after an email change — a stale entry
        # under the OLD address plus a missing entry under the new one.
        #
        # A key that points at a DIFFERENT customer is reported but NOT repaired:
        # overwriting it would steal that customer's index entry, and this doctor
        # has no way to tell which of the two is the rightful holder.
        #
        # COST: the stale-key sweep reads the org's ENTIRE email index once per
        # (customer, org) pair, so a `--all` run is O(customers x org-index-size).
        # Bounded in practice — a personal workspace holds one entry — but a large
        # shared org is re-read once per member. HSCAN would not reduce that: the
        # sweep matches on the index VALUE (objid) while MATCH filters on the field
        # (email), so a cursor walk reads the same bytes in batches and still needs
        # a full-size seen-map to absorb HSCAN's at-least-once yields.
        def check_org_email_index(issues, repaired)
          email = @customer.email.to_s
          return if email.empty?

          objid = @customer.objid.to_s

          customer_organizations.each do |org|
            index   = org.email_index
            indexed = index.get(email).to_s
            stale   = index.hgetall.select { |key, value| value.to_s == objid && key != email }.keys

            if !indexed.empty? && indexed != objid
              issues << {
                check: :org_email_index_stale,
                severity: :high,
                message: "#{org.extid}.email_index[#{@customer.obscure_email}] points to #{indexed}, " \
                         "expected #{objid}",
                org_extid: org.extid,
                repairable: false,
                repair_action: 'Manual decision required: org email_index entry is held by another customer',
              }
              next
            end

            next if !indexed.empty? && stale.empty?

            issues << {
              check: :org_email_index_stale,
              severity: :high,
              message: org_email_index_message(org, indexed, stale),
              org_extid: org.extid,
              stale_keys: stale.size,
              repairable: true,
              repair_action: 'Re-key the org-scoped email index',
            }

            next unless @repair

            # Add the correct entry BEFORE removing the stale ones, so there is
            # no window in which the customer is unfindable within the org.
            index[email] = objid
            stale.each { |key| index.remove_field(key) }
            OT.info "[customers doctor] Re-keyed #{org.extid}.email_index for #{@customer.extid} " \
                    "(removed #{stale.size} stale)"
            repaired << {
              customer: @customer.extid,
              action: :org_email_index_rekeyed,
              org: org.extid,
              stale_keys: stale.size,
            }
          end
        rescue StandardError => ex
          OT.le "[customers doctor] org_email_index check failed for #{@customer.extid}: " \
                "#{ex.class} #{ex.message}"
        end

        # CHECK: a personal workspace still contacting a dead address
        #
        # `CreateDefaultWorkspace` seeds the auto-created workspace's
        # contact_email from the customer's address and nothing ever updated it,
        # so every self-service email change left the default org (and
        # `organization:contact_email_index`) pointing at an address no account
        # holds. That matters because the signup repair path looks orgs up BY
        # contact_email.
        #
        # Scoped hard to avoid false positives and cross-customer damage:
        #   * only `is_default` workspaces the customer OWNS
        #   * only when the contact address resolves to NO live customer — a
        #     contact deliberately set to a colleague's account address is left
        #     alone. A deliberate non-account address (billing@acme.com) is the
        #     known false positive; it is reported at :warning, and repair is
        #     opt-in, never automatic.
        def check_org_contact_email(issues, repaired)
          email = @customer.email.to_s
          return if email.empty?

          customer_organizations.each do |org|
            next unless default_org?(org)

            contact = org.contact_email.to_s
            next if contact.empty?
            next if contact.downcase == email.downcase
            next unless Onetime::Customer.email_index.get(contact).nil?
            next unless org.owner?(@customer)

            holder     = Onetime::Organization.contact_email_index.get(email)
            conflicted = !holder.nil? && holder.to_s != org.identifier.to_s

            issues << {
              check: :org_contact_email_stale,
              severity: :warning,
              message: "#{org.extid} (default workspace) contact_email " \
                       "#{OT::Utils.obscure_email(contact)} belongs to no account",
              org_extid: org.extid,
              repairable: !conflicted,
              repair_action: if conflicted
                               'Manual decision required: another org already holds the customer address'
                             else
                               'Point contact_email at the customer address'
                             end,
            }

            next if conflicted
            next unless @repair

            org.contact_email = email
            org.update_in_class_contact_email_index(contact)
            org.save
            OT.info "[customers doctor] Updated #{org.extid}.contact_email for #{@customer.extid}"
            repaired << {
              customer: @customer.extid,
              action: :org_contact_email_updated,
              org: org.extid,
            }
          end
        rescue StandardError => ex
          OT.le "[customers doctor] org_contact_email check failed for #{@customer.extid}: " \
                "#{ex.class} #{ex.message}"
        end

        # CHECK: participation reverse index sync with org.members
        def check_org_membership_sync(issues, repaired)
          org_objids = @customer.participating_ids_for_target(Onetime::Organization, ['members'])

          org_objids.each do |org_objid|
            organization = Onetime::Organization.load(org_objid)

            if organization.nil?
              collection_key = [Onetime::Organization.prefix, org_objid, 'members'].join(Familia.delim)
              issues << {
                check: :org_membership_desync,
                severity: :medium,
                message: "participations references deleted org #{org_objid}",
                org_objid: org_objid,
                repairable: true,
                repair_action: 'Remove stale participation entry',
              }

              if @repair
                @customer.untrack_participation_in(collection_key)
                OT.info "[customers doctor] Removed stale participation #{collection_key} for #{@customer.extid}"
                repaired << {
                  customer: @customer.extid,
                  action: :stale_org_removed,
                  org_objid: org_objid,
                }
              end
            elsif !organization.member?(@customer)
              issues << {
                check: :org_membership_desync,
                severity: :medium,
                message: "customer tracked in participations for #{organization.extid} but not in org.members",
                org_extid: organization.extid,
                repairable: true,
                repair_action: 'Add customer to org.members',
              }

              if @repair
                organization.add_members_instance(@customer)
                OT.info "[customers doctor] Added #{@customer.extid} to #{organization.extid}.members"
                repaired << {
                  customer: @customer.extid,
                  action: :added_to_org_members,
                  org: organization.extid,
                }
              end
            end
          end
        end

        # CHECK: role has valid value
        def check_role_validity(issues)
          role = @customer.role.to_s
          return if role.empty? # No role is OK for some accounts
          return if VALID_ROLES.include?(role)

          issues << {
            check: :role_invalid,
            severity: :medium,
            message: "role '#{role}' is not a recognized value (expected: #{VALID_ROLES.join(', ')})",
            repairable: false,
            repair_action: 'Manual decision required: determine correct role',
          }
        end

        # CHECK: verified/verified_by consistency
        def check_verified_consistency(issues, repaired)
          verified    = @customer.verified.to_s == 'true'
          verified_by = @customer.verified_by.to_s

          return unless verified && verified_by.empty?

          issues << {
            check: :verified_inconsistent,
            severity: :warning,
            message: "verified='true' but verified_by is empty",
            repairable: true,
            repair_action: "Set verified_by to 'legacy'",
          }

          return unless @repair

          @customer.verified_by = 'legacy'
          @customer.save
          OT.info "[customers doctor] Set verified_by='legacy' for #{@customer.extid}"
          repaired << {
            customer: @customer.extid,
            action: :verified_by_set,
            value: 'legacy',
          }
        end

        # CHECK: counter fields are non-negative
        def check_counter_sanity(issues, repaired)
          negative_counters = []

          COUNTER_FIELDS.each do |field|
            value = @customer.send(field).to_i
            negative_counters << { field: field, value: value } if value.negative?
          end

          return if negative_counters.empty?

          issues << {
            check: :counter_negative,
            severity: :low,
            message: "#{negative_counters.size} counter(s) have negative values",
            counters: negative_counters,
            repairable: true,
            repair_action: 'Reset negative counters to 0',
          }

          return unless @repair

          negative_counters.each do |counter|
            @customer.send(:"#{counter[:field]}=", 0)
          end
          @customer.save
          OT.info "[customers doctor] Reset #{negative_counters.size} negative counter(s) for #{@customer.extid}"
          repaired << {
            customer: @customer.extid,
            action: :counters_reset,
            fields: negative_counters.map { |c| c[:field] },
          }
        end

        # CHECK: field values in :object hash are properly JSON-serialized
        def check_field_serialization(issues, repaired)
          dbclient     = @customer.class.dbclient
          customer_key = @customer.dbkey(:object)
          raw_hash     = dbclient.hgetall(customer_key)
          bad_fields   = []

          raw_hash.each do |field_name, raw_value|
            next if properly_serialized?(raw_value)

            bad_fields << { field: field_name, value: raw_value[0..60] }
          end

          return if bad_fields.empty?

          issues << {
            check: :field_serialization,
            severity: :high,
            message: "#{bad_fields.size} field(s) stored as raw strings instead of JSON: #{bad_fields.map { |f| f[:field] }.join(', ')}",
            fields: bad_fields,
            repairable: true,
            repair_action: 'Re-serialize fields with Familia::JsonSerializer.dump',
          }

          return unless @repair

          updates = bad_fields.to_h do |entry|
            [entry[:field], Familia::JsonSerializer.dump(raw_hash[entry[:field]])]
          end
          dbclient.hset(customer_key, updates)

          OT.info "[customers doctor] Re-serialized #{bad_fields.size} field(s) for #{@customer.extid}: #{bad_fields.map { |f| f[:field] }.join(', ')}"
          repaired << {
            customer: @customer.extid,
            action: :fields_reserialized,
            fields: bad_fields.map { |f| f[:field] },
          }
        end

        # Auth database handle, or nil in simple mode / when unreachable.
        def auth_db
          return @auth_db if defined?(@auth_db)

          @auth_db = defined?(Auth::Database) ? Auth::Database.connection : nil
        rescue StandardError
          @auth_db = nil
        end

        # Memoized once per Doctor instance — three checks iterate it.
        def customer_organizations
          @customer_organizations ||= @customer.organization_instances.to_a
        rescue StandardError
          @customer_organizations = []
        end

        # `is_default` is a conservative boolean: absent/blank means NOT default.
        def default_org?(org)
          org.respond_to?(:is_default) && org.is_default.to_s == 'true'
        end

        def org_email_index_message(org, indexed, stale)
          if indexed.empty?
            "#{org.extid}.email_index has no entry for #{@customer.obscure_email} " \
              "(#{stale.size} stale key(s) point here)"
          else
            "#{org.extid}.email_index has #{stale.size} stale key(s) still pointing at #{@customer.extid}"
          end
        end

        # Checks whether a raw Redis value is a valid JSON literal. See the CLI
        # docs for the empty-string / bare-primitive caveats (preserved verbatim).
        def properly_serialized?(raw_value)
          return true if raw_value.nil? || raw_value.empty?

          Familia::JsonSerializer.parse(raw_value)
          true
        rescue JSON::ParserError, Familia::SerializerError
          false
        end

        # One audit event per repaired customer (see class docs).
        def audit_repair(repaired)
          return if @actor.nil?

          Onetime::AdminAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @customer.extid,
            result: :success,
            detail: { actions: repaired.map { |r| r[:action] }.compact },
          )
        end

        # Same verb/target/actor as the success event, so the failed repair sits
        # next to the completed ones under one filter. Routed through
        # Onetime::AuditedFailure.record (not AdminAuditEvent.record directly) so
        # it inherits the shared rules: authorization rejections are dropped, an
        # exception already recorded by an inner audited op is not recorded
        # twice, and the write is best-effort.
        def audit_repair_failure(error)
          Onetime::AuditedFailure.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @customer&.extid.to_s,
            error: error,
          )
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
