# lib/onetime/operations/domains/collision_resolution/plan.rb
#
# frozen_string_literal: true

require 'json'
require 'time'

module Onetime
  module Operations
    module Domains
      class CollisionResolution
        # A plan file is not for this operation (missing keys, a group with
        # no records, a wrong rule version).
        class InvalidPlan < StandardError; end

        # One collision group in a plan.
        #
        # @!attribute decision [r] Symbol — :auto (the rule decided) or
        #   :manual (an operator decides)
        # @!attribute keep [r] String, nil — a reference (extid or objid) to
        #   the record to keep; nil for a manual group until the operator
        #   fills it in, and for a group removed outright
        # @!attribute remove [r] Array<String> — references to the records
        #   to remove; may be empty in an edited manual group, apply derives
        #   it from keep
        # @!attribute approved [r] Boolean — explicit approval of a manual
        #   decision or removal protected by cached billing evidence
        # @!attribute skip [r] Boolean — apply leaves the group alone
        Group = Data.define(:ascii_name, :decision, :rule, :keep, :remove, :notes, :records, :approved, :skip) do
          def manual?
            decision == :manual
          end

          def record(reference)
            records.find { |record| record.named_by?(reference) }
          end

          def keep_record
            keep.nil? ? nil : record(keep)
          end

          def protected_removals
            (records - [keep_record].compact).select(&:billing_protected?)
          end

          def approval_required?
            manual? || protected_removals.any?
          end

          def approval_pending?
            approval_required? && !approved
          end

          def to_h
            {
              ascii_name: ascii_name,
              decision: decision.to_s,
              rule: rule.to_s,
              keep: keep,
              remove: remove,
              approved: approved,
              approval_required: approval_required?,
              skip: skip,
              notes: notes,
              records: records.map(&:to_h),
            }
          end

          def self.from_h(hash)
            h = hash.transform_keys(&:to_sym)
            raise InvalidPlan, 'a group has no ASCII name' if h[:ascii_name].to_s.empty?

            records = Array(h[:records]).map { |record| Record.from_h(record) }
            raise InvalidPlan, "group #{h[:ascii_name]} has no records" if records.empty?

            new(
              ascii_name: h[:ascii_name].to_s,
              decision: h[:decision].to_s == 'manual' ? :manual : :auto,
              rule: h[:rule].to_s.empty? ? :unknown : h[:rule].to_sym,
              keep: h[:keep].to_s.empty? ? nil : h[:keep].to_s,
              remove: Array(h[:remove]).map(&:to_s),
              notes: Array(h[:notes]).map(&:to_s),
              records: records,
              approved: h[:approved] == true,
              skip: h[:skip] == true,
            )
          end
        end

        # The plan: every collision group with its facts and decision.
        #
        # @!attribute strategy [r] String — the domain validation strategy
        #   the plan was made under (approximated, passthrough, ...)
        Plan = Data.define(:generated_at, :rule_version, :strategy, :groups) do
          def auto_groups
            groups.reject(&:manual?)
          end

          def manual_groups
            groups.select(&:manual?)
          end

          def group(ascii_name)
            groups.find { |group| group.ascii_name == ascii_name }
          end

          # Whether an operator still has to decide a group.
          def attention?
            groups.any? { |group| !group.skip && (group.approval_pending? || (group.manual? && group.keep.nil?)) }
          end

          def counts
            {
              groups: groups.size,
              auto: auto_groups.size,
              manual: manual_groups.size,
              approval_required: groups.count(&:approval_required?),
              approval_pending: groups.count { |group| !group.skip && group.approval_pending? },
              records: groups.sum { |group| group.records.size },
              removals: auto_groups.sum { |group| group.remove.size },
              rules: groups.map { |group| group.rule.to_s }.tally,
            }
          end

          def to_h
            {
              rule_version: rule_version,
              generated_at: generated_at,
              strategy: strategy,
              counts: counts,
              groups: groups.map(&:to_h),
            }
          end

          def to_json(*)
            JSON.pretty_generate(to_h, *)
          end

          # @param hash [Hash] a parsed plan file
          # @raise [InvalidPlan]
          def self.from_h(hash)
            raise InvalidPlan, 'the plan is not a JSON object' unless hash.is_a?(Hash)

            h = hash.transform_keys(&:to_sym)
            unless h[:rule_version].to_i == Rule::VERSION
              raise InvalidPlan, "the plan has rule_version #{h[:rule_version].inspect}; this command applies version #{Rule::VERSION}"
            end
            raise InvalidPlan, 'the plan has no groups array' unless h[:groups].is_a?(Array)

            groups = h[:groups].map { |group| Group.from_h(group) }
            dupes  = groups.map(&:ascii_name).tally.select { |_, n| n > 1 }.keys
            raise InvalidPlan, "the plan lists #{dupes.join(', ')} more than once" if dupes.any?

            new(
              generated_at: h[:generated_at].to_s,
              rule_version: Rule::VERSION,
              strategy: h[:strategy].to_s,
              groups: groups,
            )
          end

          # @param json [String]
          # @raise [InvalidPlan] on malformed JSON too
          def self.parse(json)
            from_h(JSON.parse(json))
          rescue JSON::ParserError => ex
            raise InvalidPlan, "the plan is not valid JSON: #{ex.message}"
          end
        end
      end
    end
  end
end
