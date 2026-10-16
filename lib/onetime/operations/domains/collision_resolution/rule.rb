# lib/onetime/operations/domains/collision_resolution/rule.rb
#
# frozen_string_literal: true

module Onetime
  module Operations
    module Domains
      class CollisionResolution
        # Which record of a collision group to keep. Pure: reads Records,
        # touches no datastore.
        #
        # The rule, in order. The first step that names exactly one record
        # decides; a step that names several sends the group to an operator.
        #
        #   1. A record whose organization no longer exists is removed.
        #      With no other record left the group is removed outright
        #      (:all_orphans); with one left it is kept (:only_owned).
        #   2. Exactly one record has a passing TXT check on file
        #      (verified_confirmed_at): keep it (:dns_proof). Several:
        #      :manual_several_dns_proofs.
        #   3. Exactly one record has ownership_verified, by the strategy's
        #      check or a colonel override: keep it (:ownership_verified).
        #      Several: :manual_several_verified.
        #   4. Exactly one record is in use (Record#in_use?): keep it
        #      (:in_use). Several: :manual_several_in_use.
        #   5. None is in use. Keep the record a request resolves to today
        #      (:served_tiebreak), or, when none does, the oldest
        #      (:oldest_tiebreak). Nothing is lost either way.
        #
        # Steps 2 and 3 prefer ownership evidence over use: a record that
        # proved DNS control wins over a record that was used without it,
        # and the plan says so in its notes.
        module Rule
          # Version 2 requires billing snapshots and explicit approval for protected removals.
          VERSION = 2

          MANUAL_RULES = [:manual_several_dns_proofs, :manual_several_verified, :manual_several_in_use].freeze

          Decision = Data.define(:decision, :rule, :keep, :remove, :notes) do
            def manual?
              decision == :manual
            end
          end

          extend self

          # @param records [Array<Record>] the records sharing one A-label
          # @return [Decision] keep and remove hold domain_ids
          def decide(records)
            orphans    = records.select(&:orphan?)
            candidates = records - orphans
            keep, rule = choose(candidates)

            if MANUAL_RULES.include?(rule)
              return Decision.new(decision: :manual, rule: rule, keep: nil, remove: [], notes: notes_for(records, nil, orphans))
            end

            remove = (records - [keep].compact).map(&:domain_id)
            Decision.new(decision: :auto, rule: rule, keep: keep&.domain_id, remove: remove, notes: notes_for(records, keep, orphans))
          end

          # @return [Array(Record, nil), Symbol]
          def choose(candidates)
            return [nil, :all_orphans] if candidates.empty?
            return [candidates.first, :only_owned] if candidates.size == 1

            proven = candidates.select(&:dns_proof?)
            return [proven.first, :dns_proof] if proven.size == 1
            return [nil, :manual_several_dns_proofs] if proven.size > 1

            verified = candidates.select { |record| record.ownership_verified == true }
            return [verified.first, :ownership_verified] if verified.size == 1
            return [nil, :manual_several_verified] if verified.size > 1

            used = candidates.select(&:in_use?)
            return [used.first, :in_use] if used.size == 1
            return [nil, :manual_several_in_use] if used.size > 1

            served = candidates.select { |record| record.served == true }
            return [served.first, :served_tiebreak] if served.size == 1

            [candidates.min_by { |record| record.created.to_i }, :oldest_tiebreak]
          end

          # What an operator should know before approving the decision.
          def notes_for(records, keep, orphans)
            notes = orphans.map do |record|
              if record.org_state == :dangling
                "#{record.ref} names organization #{record.org_id}, which cannot be loaded; it is removed (billing unknown: approval required)"
              else
                "#{record.ref} has no organization; it is removed"
              end
            end
            return notes unless keep

            notes << "kept record #{keep.ref} belongs to an archived organization" if keep.org_state == :archived
            (records - [keep]).reject(&:orphan?).each do |record|
              notes << "#{record.ref} answers for the name today; after the removal #{keep.ref} does" if record.served
              notes << "#{record.ref} has #{record.receipts} receipts; the receipts keep their share_domain" if record.receipts.to_i.positive?
              notes << "#{record.ref} has brand settings; they are deleted with the record" if record.brand
              notes << "#{record.ref} has #{record.configs.join(', ')} config; deleted with the record" if record.configs.any?
            end
            notes
          end
        end
      end
    end
  end
end
