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
            out << "Strategy: #{plan.strategy}"
            counts = plan.counts
            out << "Groups: #{counts[:groups]} (auto #{counts[:auto]}, manual #{counts[:manual]})  records: #{counts[:records]}  planned removals: #{counts[:removals]}"
            out << "Rules: #{counts[:rules].map { |rule, n| "#{rule} #{n}" }.join(', ')}" if counts[:groups].positive?
            out << ''
            plan.groups.each { |group| out.concat(group_lines(group)) }
            out.concat(plan_next_steps(plan))
            out.join("\n")
          end

          def group_lines(group)
            lines = []
            state = if group.skip
'SKIP'
else
(if group.manual?
group.approved ? 'MANUAL approved' : 'MANUAL'
else
'auto'
end)
end
            lines << "#{group.ascii_name}  #{state}: #{group.rule}"
            group.records.each do |record|
              tag = if record.named_by?(group.keep) then 'KEEP  '
                    elsif group.manual? && !group.keep then '?     '
                    else 'REMOVE'
                    end
              lines << "  #{tag} #{record_line(record)}"
            end
            group.notes.each { |note| lines << "  note: #{note}" }
            lines << ''
            lines
          end

          def record_line(record)
            [
              format('%-28s', record.ref),
              format('%-28s', spelled(record.display_domain)),
              "org=#{record.org_extid || record.org_id || '(none)'} #{record.org_state}",
              record.served ? 'served' : 'shadow',
              record.verification_state.to_s,
              record.dns_proof? ? "dns-confirmed #{date(record.verified_confirmed_at)}" : 'no dns confirmation',
              record.override? ? 'override' : nil,
              "receipts=#{record.receipts}",
              "configs=#{record.configs.empty? ? '-' : record.configs.join(',')}",
              "brand=#{record.brand}",
              "created #{date(record.created)}",
            ].compact.join('  ')
          end

          def plan_next_steps(plan)
            return ['No collision groups. Nothing to resolve.'] if plan.groups.empty?

            lines = []
            if plan.manual_groups.any?
              lines << "#{plan.manual_groups.size} groups need a decision. In the plan file set the group's keep to the"
              lines << 'extid of the record to keep and approved to true, or skip to true.'
            end
            lines << 'Review the plan, then with the application stopped:'
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
            out << "Mode: #{result.dry_run ? 'DRY RUN (nothing written)' : 'APPLY'}"
            out << "Strategy: #{result.strategy}"
            counts = result.counts
            out << "Groups: #{counts.empty? ? 'none' : counts.map { |status, n| "#{status} #{n}" }.join(', ')}"
            out << ''
            result.outcomes.each { |outcome| out.concat(outcome_lines(outcome)) }
            out.concat(apply_next_steps(result))
            out.join("\n")
          end

          def outcome_lines(outcome)
            lines = ["#{outcome.ascii_name}  #{outcome.status}#{": #{outcome.reason}" if outcome.reason}"]
            lines << "  keep   #{outcome.keep}" if outcome.keep && !outcome.skipped?
            outcome.removals.each do |removal|
              detail = removal.detail ? " - #{removal.detail}" : ''
              lines << format('  %-7s %s  %s%s', removal.status, removal.ref, spelled(removal.display_domain), detail)
            end
            lines << "  exact index: #{outcome.index_claim}" if outcome.index_claim
            lines << "  kept record verified: #{outcome.verify_state}" if outcome.verify_state
            outcome.errors.each { |error| lines << "  error: #{error}" }
            lines << ''
            lines
          end

          def apply_next_steps(result)
            lines = []
            if result.attention?
              lines << 'Some groups were skipped or did not complete; see above. Fix the plan or the'
              lines << 'record, then run --apply again.'
            end
            if result.dry_run
              lines << 'Dry run. Run again without --dry-run to remove the records.'
            else
              lines << 'Next, with the application still stopped:'
              lines << '  bin/ots domains backfill-ascii-index --apply'
            end
            lines
          end

          def spelled(name)
            return name.to_s if name.to_s.ascii_only?

            "#{name} #{name.dump}"
          end

          def date(epoch)
            return 'unknown' if epoch.nil?

            Time.at(epoch.to_i).utc.strftime('%Y-%m-%d')
          rescue StandardError
            'invalid'
          end
        end
      end
    end
  end
end
