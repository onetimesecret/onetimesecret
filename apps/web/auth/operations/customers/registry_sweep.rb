# apps/web/auth/operations/customers/registry_sweep.rb
#
# frozen_string_literal: true

module Auth
  module Operations
    module Customers
      # The three global registries a deep purge preflight sweeps, read ONCE
      # with pipelined field reads and reused by every deep preflight of the
      # same purge.
      #
      # Deep discovery needs little from each registry row: whether an
      # organization's `owner_id`, its `members` set or the target's own
      # membership row names the purge target; which organization each
      # membership row and custom domain belongs to; and which membership rows
      # name the target. Loading every record to answer that (an EXISTS and an
      # HGETALL per row, one round trip at a time, and a full Familia object
      # for each) is what made `bin/ots customers purge-one` take minutes and
      # a core against a registry of hundreds of thousands of workspaces, and
      # a purge ran that sweep three times: the initial plan, Org::Delete's
      # capability recheck and the post-teardown revalidation.
      #
      # The sweep holds identifiers only. Consumers re-load the records they
      # act on, so the evidence a plan is built from is always live; the sweep
      # only says where to look. {#refreshed} lists the registries again and
      # probes just the identifiers it has not seen, so the post-teardown check
      # still sees a row written during the purge at the cost of one registry
      # listing per class rather than a full re-read.
      #
      # A registry that cannot be read is recorded in {#failures} under its
      # name; the preflight turns that into the matching `*_scan_failed`
      # blocker and the data captured before the failure stays partial, which
      # fails closed (an organization missing from a partial listing reads as
      # unregistered).
      class RegistrySweep
        BATCH_SIZE    = 500
        LISTING_BATCH = 1000

        attr_reader :customer_objid,
          :organization_ids,
          :referenced_org_ids,
          :membership_ids,
          :membership_objids_by_org,
          :target_membership_objids,
          :domain_ids,
          :domain_objids_by_org,
          :failures

        # @param customer_objid [String] purge target
        # @param previous [RegistrySweep, nil] an earlier sweep for the same
        #   target whose per-row results are reused for every identifier it
        #   already listed; only identifiers new since then are probed
        # @return [RegistrySweep]
        def self.capture(customer_objid:, previous: nil)
          Capture.new(customer_objid.to_s, previous).call
        end

        # rubocop:disable-next Metrics/ParameterLists -- one value object, built only by Capture and specs
        def initialize(customer_objid:, organization_ids: [], referenced_org_ids: [], membership_ids: [],
                       membership_objids_by_org: {}, target_membership_objids: [], domain_ids: [],
                       domain_objids_by_org: {}, failures: {})
          @customer_objid           = customer_objid.to_s
          @organization_ids         = Set.new(organization_ids.map(&:to_s)).freeze
          @referenced_org_ids       = Set.new(referenced_org_ids.map(&:to_s)).freeze
          @membership_ids           = Set.new(membership_ids.map(&:to_s)).freeze
          @membership_objids_by_org = freeze_groups(membership_objids_by_org)
          @target_membership_objids = target_membership_objids.map(&:to_s).uniq.freeze
          @domain_ids               = Set.new(domain_ids.map(&:to_s)).freeze
          @domain_objids_by_org     = freeze_groups(domain_objids_by_org)
          @failures                 = failures.to_h { |registry, message| [registry.to_sym, message.to_s] }.freeze
          freeze
        end

        # @return [RegistrySweep] a sweep over the registries as they are now,
        #   probing only identifiers this sweep did not list
        def refreshed
          self.class.capture(customer_objid: @customer_objid, previous: self)
        end

        # @param registry [Symbol] :organizations, :memberships or :domains
        # @return [Boolean]
        def failed?(registry)
          @failures.key?(registry.to_sym)
        end

        # @return [Array<String>] membership objids recorded for the organization
        def membership_objids_for(org_id)
          @membership_objids_by_org.fetch(org_id.to_s, [])
        end

        # @return [Array<String>] custom domain objids whose `org_id` named the organization
        def domain_objids_for(org_id)
          @domain_objids_by_org.fetch(org_id.to_s, [])
        end

        private

        def freeze_groups(groups)
          groups.to_h { |org_id, objids| [org_id.to_s, objids.map(&:to_s).uniq.freeze] }.freeze
        end

        # One capture. Each registry is listed from its `instances` sorted set,
        # then the rows new since `previous` are probed in pipelined batches of
        # HMGET/ZRANGE for the few fields discovery needs. Values are decoded
        # the way Familia decodes a field: JSON when the stored value is JSON,
        # the raw string otherwise.
        class Capture
          def initialize(customer_objid, previous)
            @customer_objid = customer_objid
            @previous       = previous
            @failures       = {}
          end

          def call
            organization_ids, referenced        = sweep_organizations
            membership_ids, by_org, target_rows = sweep_memberships
            domain_ids, domains_by_org          = sweep_domains

            RegistrySweep.new(
              customer_objid: @customer_objid,
              organization_ids: organization_ids,
              referenced_org_ids: referenced,
              membership_ids: membership_ids,
              membership_objids_by_org: by_org,
              target_membership_objids: target_rows,
              domain_ids: domain_ids,
              domain_objids_by_org: domains_by_org,
              failures: @failures,
            )
          end

          private

          def reusable(registry)
            previous = @previous
            previous unless previous.nil? || previous.failed?(registry)
          end

          def sweep_organizations
            previous   = reusable(:organizations)
            ids        = Set.new
            referenced = Set.new(previous&.referenced_org_ids || [])
            klass      = Onetime::Organization
            target_row = Onetime::OrganizationMembership

            list(klass) do |batch|
              batch.each { |objid| ids << objid }
              fresh = previous ? batch.reject { |objid| previous.organization_ids.include?(objid) } : batch
              next if fresh.empty?

              org_replies = klass.dbclient.pipelined do |pipe|
                fresh.each do |objid|
                  pipe.hmget(klass.dbkey(objid), 'owner_id')
                  pipe.zrange(klass.dbkey(objid, :members), 0, -1)
                end
              end
              row_replies = target_row.dbclient.pipelined do |pipe|
                fresh.each do |objid|
                  pipe.hmget(target_row.dbkey(target_row.composite_objid(objid, @customer_objid)), 'status')
                end
              end

              fresh.each_with_index do |objid, index|
                owner_id   = decode(org_replies[index * 2]&.first)
                member_ids = Array(org_replies[(index * 2) + 1]).map { |raw| decode(raw) }
                status     = decode(row_replies[index]&.first)
                next unless owner_id == @customer_objid ||
                            member_ids.include?(@customer_objid) ||
                            status == 'active'

                referenced << objid
              end
            end

            [ids, referenced]
          rescue StandardError => ex
            @failures[:organizations] = ex.class.name
            [ids, referenced]
          end

          def sweep_memberships
            previous    = reusable(:memberships)
            ids         = Set.new
            by_org      = Hash.new { |hash, key| hash[key] = [] }
            previous&.membership_objids_by_org&.each { |org_id, objids| by_org[org_id].concat(objids) }
            target_rows = (previous&.target_membership_objids || []).dup
            klass       = Onetime::OrganizationMembership

            list(klass) do |batch|
              batch.each { |objid| ids << objid }
              fresh = previous ? batch.reject { |objid| previous.membership_ids.include?(objid) } : batch
              next if fresh.empty?

              replies = klass.dbclient.pipelined do |pipe|
                fresh.each { |objid| pipe.hmget(klass.dbkey(objid), 'organization_objid', 'customer_objid') }
              end

              fresh.each_with_index do |objid, index|
                org_id, customer_objid = Array(replies[index]).map { |raw| decode(raw) }
                # A registry entry whose hash is gone has no organization; the
                # per-row load the old scan did returned nil for it too.
                next if org_id.to_s.empty?

                by_org[org_id] << objid unless by_org[org_id].include?(objid)
                target_rows << objid if customer_objid == @customer_objid
              end
            end

            [ids, by_org, target_rows]
          rescue StandardError => ex
            @failures[:memberships] = ex.class.name
            [ids, by_org, target_rows]
          end

          def sweep_domains
            previous = reusable(:domains)
            ids      = Set.new
            by_org   = Hash.new { |hash, key| hash[key] = [] }
            previous&.domain_objids_by_org&.each { |org_id, objids| by_org[org_id].concat(objids) }
            klass    = Onetime::CustomDomain

            list(klass) do |batch|
              batch.each { |objid| ids << objid }
              fresh = previous ? batch.reject { |objid| previous.domain_ids.include?(objid) } : batch
              next if fresh.empty?

              replies = klass.dbclient.pipelined do |pipe|
                fresh.each { |objid| pipe.hmget(klass.dbkey(objid), 'org_id') }
              end

              fresh.each_with_index do |objid, index|
                org_id = decode(replies[index]&.first)
                next if org_id.empty?

                by_org[org_id] << objid unless by_org[org_id].include?(objid)
              end
            end

            [ids, by_org]
          rescue StandardError => ex
            @failures[:domains] = ex.class.name
            [ids, by_org]
          end

          # Yields the registry's identifiers in batches. ZSCAN may repeat an
          # element while the set changes underneath it, so a batch is deduped
          # against everything yielded so far.
          def list(klass)
            seen  = Set.new
            batch = []
            klass.instances.each(batch_size: LISTING_BATCH) do |raw|
              objid = raw.to_s
              next if objid.empty? || !seen.add?(objid)

              batch << objid
              next if batch.size < BATCH_SIZE

              yield batch
              batch = []
            end
            yield batch unless batch.empty?
          end

          def decode(raw)
            return '' if raw.nil? || raw == ''

            Familia::JsonSerializer.parse(raw).to_s
          rescue Familia::SerializerError
            raw.to_s
          end
        end
        private_constant :Capture
      end
    end
  end
end
