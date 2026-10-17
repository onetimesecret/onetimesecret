# lib/onetime/operations/domains/collision_resolution/text.rb
#
# frozen_string_literal: true

module Onetime
  module Operations
    module Domains
      class CollisionResolution
        # Text reports for a Plan and an ApplyResult, printed by the CLI
        # command.
        module Text
          extend self

          # @param plan [Plan]
          # @return [String]
          def plan(plan)
            out = []
            out << 'Custom domain collision plan'
            out << ('=' * 40)
            out << 'Mode: READ ONLY (proposals only; nothing written to the datastore)'
            out << "Plan generated at: #{plan.generated_at}"
            out << "Rule version: #{plan.rule_version}"
            out << "Strategy: #{plan.strategy}"
            out.concat(evidence_key)
            counts = plan.counts
            out << "Groups: #{counts[:groups]} (auto #{counts[:auto]}, manual #{counts[:manual]})  records: #{counts[:records]}  proposed removals: #{counts[:removals]}"
            out << "Rules: #{counts[:rules].map { |rule, n| "#{rule} #{n}" }.join(', ')}" if counts[:groups].positive?
            out << ''
            plan.groups.each { |group| out.concat(group_lines(group)) }
            out.concat(plan_next_steps(plan))
            out.join("\n")
          end

          def evidence_key
            [
              'Evidence: dns-confirmed is a historical passing TXT check, not a fresh DNS lookup.',
              'ownership_verified is a stored flag; verified_by_override identifies an operator override.',
              'served/shadow is local name-index routing at plan time, not a network probe.',
              'Use means receipts, brand settings, or use configs; non-use configs are shown separately.',
              'Billing source: local_cache (no live Stripe lookup); billing guards deletion, not keeper selection.',
              'Configs and brand settings on removed records are deleted, not merged; receipts retain share_domain.',
            ]
          end

          def group_lines(group)
            lines = []
            lines << "#{group.ascii_name}  #{state_label(group)}: #{group.rule}"
            lines << "  proposal: keep=#{group.keep || '(none)'}  decision=#{group.decision}"
            lines << "  approval_required=#{group.approval_required?}  approved=#{group.approved}  approval_pending=#{group.approval_pending?}"
            if group.protected_removals.any?
              lines << "  billing-protected proposed removals: #{group.protected_removals.map(&:ref).join(', ')}"
            end
            group.records.each do |record|
              tag = if record.named_by?(group.keep) then 'KEEP  '
                    elsif group.manual? && !group.keep then '?     '
                    else 'REMOVE'
                    end
              lines.concat(record_lines(record, tag))
            end
            group.notes.each { |note| lines << "  note: #{note}" }
            lines << ''
            lines
          end

          def state_label(group)
            return 'SKIP' if group.skip
            return 'auto' unless group.manual?

            group.approved ? 'MANUAL approved' : 'MANUAL'
          end

          def record_lines(record, tag)
            [
              "  #{tag} #{record_line(record)}",
              "    organization: org_id=#{value(record.org_id)}  org_extid=#{value(record.org_extid)}  org_name=#{record.org_name.inspect}  state=#{record.org_state}",
              "    ownership_verified=#{record.ownership_verified}  verified_by_override=#{record.verified_by_override}  " \
              "verification_state=#{value(record.verification_state)}  " \
              "#{record.dns_proof? ? "historical dns-confirmed #{date(record.verified_confirmed_at)}" : 'no historical dns confirmation'}",
              "    use: in_use=#{record.in_use?}  receipts=#{record.receipts}  brand=#{record.brand}  configs=#{list(record.configs)}  vhost=#{record.vhost}",
              "    all_configs=#{list(record.all_configs)}  non-use configs=#{list(record.all_configs - record.configs)}",
              "    billing: source=local_cache  label=#{record.billing_label}  protected=#{record.billing_protected?}  " \
              "planid=#{value(record.planid)}  stripe_customer_id=#{value(record.stripe_customer_id)}  " \
              "stripe_subscription_id=#{value(record.stripe_subscription_id)}  subscription_status=#{value(record.subscription_status)}",
            ]
          end

          def record_line(record)
            [
              format('%-28s', record.ref),
              spelled(record.display_domain),
              "domain_id=#{value(record.domain_id)}",
              "extid=#{value(record.extid)}",
              record.served ? 'served' : 'shadow',
              "created #{date(record.created)}",
            ].join('  ')
          end

          def plan_next_steps(plan)
            return ['No collision groups. Nothing to resolve.'] if plan.groups.empty?

            lines  = []
            manual = plan.groups.select { |group| group.manual? && !group.skip && (!group.keep || !group.approved) }
            if manual.any?
              lines << "#{manual.size} groups need a decision. In the plan file set the group's keep to the"
              lines << 'extid of the record to keep and approved to true, or skip to true.'
            end
            pending = plan.groups.count { |group| !group.skip && group.approval_pending? }
            if pending.positive?
              lines << "#{pending} groups need deletion approval (manual decisions or billing-protected removals)."
              lines << 'An auto proposal still needs approved=true when a removal is billing-protected.'
            end
            lines << 'Billing labels: live_or_recoverable and unknown protect deletion; no_local_subscription'
            lines << 'and not_live describe only the local cache, not current Stripe state.'
            lines << '--yes skips the prompt only; it does not approve plan groups.'
            lines << 'Older rule-version plans are rejected; regenerate and review them, do not just edit the version.'
            lines << 'Review the plan, then with the application stopped:'
            lines << '  bin/ots domains resolve-collisions --apply --plan <file> --dry-run'
            lines << '  bin/ots domains resolve-collisions --apply --plan <file>'
            lines << 'then run bin/ots domains backfill-ascii-index --apply.'
            lines
          end

          # @param result [ApplyResult]
          # @return [String]
          def apply(result)
            out = []
            out << 'Custom domain collision resolution'
            out << ('=' * 40)
            out << "Mode: #{result.dry_run ? 'DRY RUN (no domain changes)' : 'APPLY'}"
            out << "Strategy: #{result.strategy}"
            context = result.outcomes.first&.context&.transform_keys(&:to_sym) || {}
            out << "Run ID: #{value(context[:run_id])}"
            out << "Run started at: #{value(context[:run_started_at])}"
            out << "Reviewed plan SHA256: #{value(context[:plan_sha256])}"
            out << "Plan generated at: #{value(context[:plan_generated_at])}"
            out << "Rule version: #{value(context[:rule_version])}"
            out.concat(evidence_key)
            out << 'Record evidence below is saved plan context, not a post-apply audit.'
            counts = result.counts
            out << "Groups: #{counts.empty? ? 'none' : counts.map { |status, n| "#{status} #{n}" }.join(', ')}"
            out << ''
            result.outcomes.each { |outcome| out.concat(outcome_lines(outcome)) }
            out.concat(apply_next_steps(result))
            out.join("\n")
          end

          def outcome_lines(outcome)
            context = outcome.context.transform_keys(&:to_sym)
            lines   = ["#{outcome.ascii_name}  #{outcome.status}#{": #{outcome.reason}" if outcome.reason}"]
            lines << "  context: run_id=#{value(context[:run_id])}  plan_generated_at=#{value(context[:plan_generated_at])}  rule_version=#{value(context[:rule_version])}"
            lines << "  decision=#{value(context[:decision])}  rule=#{value(context[:rule])}  " \
                     "approval_required=#{value(context[:approval_required])}  approved=#{value(context[:approved])}  " \
                     "billing_source=#{value(context[:billing_source])}"
            lines << "  planned keep: #{outcome.keep || '(none)'}"
            lines << '  saved plan evidence (KEEP/REMOVE are proposals, not execution results):'
            Array(context[:records]).each do |hash|
              record = Record.from_h(hash)
              tag    = if record.named_by?(outcome.keep) then 'KEEP  '
                    elsif context[:decision].to_s == 'manual' && !outcome.keep then '?     '
                    else 'REMOVE'
                    end
              lines.concat(record_lines(record, tag))
            end
            Array(context[:notes]).each { |note| lines << "  note: #{note}" }
            lines << '  removal outcomes: none' if outcome.removals.empty?
            outcome.removals.each do |removal|
              detail  = removal.detail ? " - #{removal.detail}" : ''
              cleanup = removal.sender_cleanup ? "  sender_cleanup=#{removal.sender_cleanup}" : ''
              lines << format('  %-7s %s  %s%s%s', removal.status, removal.ref, spelled(removal.display_domain), cleanup, detail)
            end
            lines << "  exact index: #{outcome.index_claim || 'no result reported (not needed, skipped or dry run)'}"
            lines << "  kept record verified: #{outcome.verify_state || 'no result reported (see errors; may be not applicable)'}"
            outcome.errors.each { |error| lines << "  error: #{error}" }
            lines << ''
            lines
          end

          def apply_next_steps(result)
            lines = []
            if result.attention?
              lines << 'Some groups were skipped or did not complete; see above. Fix the plan or the'
              lines << 'record, then run --apply again. Regenerate and review the plan if its evidence changed.'
            end
            lines << '--yes does not approve plan groups; set approved=true after reviewing required approvals.'
            if result.dry_run
              lines << 'Dry run. Run again without --dry-run to remove the eligible records.'
              lines << 'No collision-summary or successful deletion events are written by a dry run.'
              lines << 'domain.remove previews may be written to the observation trail; preview failures may also be audited.'
            else
              lines << 'Audit: domain.resolve_collision records each group outcome, including skipped groups,'
              lines << 'with saved context and run_id; domain.remove records each deletion separately.'
              lines << 'Audit detail arrays are capped at 25 entries; counts, run_id and plan SHA256 link to the full console/JSON evidence.'
              lines << 'removed_audit_failed means deletion committed but its individual audit write failed; the group is partial.'
              lines << 'Keep this output and the reviewed plan together for reconstruction.'
              lines << 'Next, with the application still stopped:'
              lines << '  bin/ots domains backfill-ascii-index --apply'
            end
            lines
          end

          def value(item)
            item.nil? || item.to_s.empty? ? '(none)' : item.to_s
          end

          def list(items)
            items.empty? ? '-' : items.join(',')
          end

          def spelled(name)
            return name.to_s if name.to_s.ascii_only?

            "#{name} #{name.dump}"
          end

          def date(epoch)
            return 'unknown' if epoch.nil?

            Time.at(epoch.to_i).utc.strftime('%Y-%m-%dT%H:%M:%SZ')
          rescue StandardError
            'invalid'
          end
        end
      end
    end
  end
end
