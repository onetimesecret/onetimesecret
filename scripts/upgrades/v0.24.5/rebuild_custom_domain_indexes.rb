#!/usr/bin/env ruby
# frozen_string_literal: true

# Rebuild ALL CustomDomain index structures from the canonical :object hashes.
#
# Invariant: the only input is the set of custom_domain:<objid>:object hashes
# discovered by SCAN. Target structures (instances, display_domain_index,
# display_domains, owners, extid_lookup, organization:*:domains) are never
# read as input. Every step writes to a temp key and atomic-swaps onto the
# final key.
#
# Usage:
#   bundle exec ruby scripts/upgrades/v0.24.5/rebuild_custom_domain_indexes.rb [OPTIONS]
#   CONFIRM=yes bundle exec ruby ... --execute
#
# Options:
#   --execute   Apply changes (requires CONFIRM=yes). Default: dry-run.
#   --verbose   Show per-command and progress output
#   --help      Show this help
#
# Operational warning: run during a maintenance window or with CustomDomain
# write traffic paused. A `.destroy!` that runs between rebuild_instances's
# SCAN and its atomic swap can reintroduce the destroyed objid as a phantom
# into the rebuilt instances sorted set. Writes through the live code path
# don't lose data (Familia's save paths maintain indexes), but concurrent
# destroys race with the rebuild.
#
# Dry-run limitation: rebuild_display_domain_index delegates to Familia's
# internal SCAN+atomic-swap, which does not surface through this script's
# CommandLog. Dry-run correctly reports every other step command-by-command;
# for display_domain_index it reports only that the rebuild would run.

require 'onetime'
require 'onetime/models'

module Onetime
  class CustomDomain
    module IndexRebuilder
      module_function

      # Familia 2.6.0 moved atomic_swap out of the Indexing::RebuildStrategies
      # module and into Familia::AtomicOperations as a module function.
      ATOMIC_SWAP = Familia::AtomicOperations

      def run(execute: false, verbose: false, io: $stdout)
        log = CommandLog.new(execute: execute, io: io, verbose: verbose)
        log.banner
        started = Familia.now

        counts = {}
        counts[:instances]            = rebuild_instances(log)
        counts[:display_domain_index] = rebuild_display_domain_index(log)
        counts[:display_domains]      = rebuild_hashkey(log, CustomDomain.display_domains,
                                          ->(o) { [o.display_domain.to_s, o.identifier.to_s] })
        counts[:owners]               = rebuild_hashkey(log, CustomDomain.owners,
                                          ->(o) { [o.identifier.to_s, o.org_id.to_s] })
        counts[:extid_lookup]         = rebuild_extid_lookup(log)
        counts[:organization_domains] = rebuild_organization_domains(log)

        io.puts "\n=== Summary ==="
        counts.each { |k, v| io.puts format('%-24s %s', k, v) }
        io.puts format('%-24s %s', :commands_issued, log.total)
        io.puts format('%-24s %.2fs', :elapsed, Familia.now - started)
        counts.merge(commands: log.total)
      end

      # Invariant: instances is derived only from SCAN of :object keys.
      def rebuild_instances(log)
        dbc = CustomDomain.dbclient
        final_key = CustomDomain.instances.dbkey
        temp_key  = "#{final_key}:rebuild:#{Familia.now.to_i}"
        log.note "temp instances=#{temp_key}"
        count = 0
        dbc.scan_each(match: 'custom_domain:*:object') do |key|
          raw_objid = dbc.hget(key, 'objid')
          canonical = raw_objid ? (JSON.parse(raw_objid) rescue raw_objid) : nil
          if canonical.nil? || canonical.to_s.empty?
            log.warn "skip: no :object.objid for #{key}"
            next
          end
          ts_raw = dbc.hget(key, 'updated') || dbc.hget(key, 'created')
          score  = ts_raw ? ((JSON.parse(ts_raw) rescue ts_raw).to_f) : Familia.now.to_f
          log.zadd(temp_key, score, canonical.to_s)
          count += 1
        end
        log.swap(temp_key, final_key, label: :instances)
        count
      end

      # Invariant: Familia's auto-rebuild reads clean instances + :object hashes.
      # Familia performs its own internal SCAN + atomic swap for this structure,
      # so the command sequence is not visible in dry-run output. See header.
      def rebuild_display_domain_index(log)
        final_key = CustomDomain.display_domain_index.dbkey
        log.note "rebuild_display_domain_index final=#{final_key} (internal: SCAN + DEL + RENAME via Familia)"
        return 0 unless log.execute?

        CustomDomain.rebuild_display_domain_index
      end

      # Invariant: manual class_hashkey reconstructed from clean instances only.
      def rebuild_hashkey(log, hashkey, pair_proc)
        final_key = hashkey.dbkey
        temp_key  = "#{final_key}:rebuild:#{Familia.now.to_i}"
        label     = final_key.split(':').last.to_sym
        log.note "temp #{label}=#{temp_key}"
        count = 0
        CustomDomain.instances.members.each_slice(100) do |batch|
          CustomDomain.load_multi(batch).compact.each do |obj|
            pair = pair_proc.call(obj) or next
            field, value = pair
            next if field.empty? || value.empty?

            log.hset(temp_key, field, hashkey.serialize_value(value))
            count += 1
          end
        end
        log.swap(temp_key, final_key, label: label)
        count
      end

      # Invariant: extid_lookup[extid] = serialized objid. Read extid directly
      # from the :object hash to avoid deriver security checks on seeded/corrupt data.
      def rebuild_extid_lookup(log)
        dbc = CustomDomain.dbclient
        hashkey = CustomDomain.extid_lookup
        final_key = hashkey.dbkey
        temp_key  = "#{final_key}:rebuild:#{Familia.now.to_i}"
        log.note "temp extid_lookup=#{temp_key}"
        count = 0
        CustomDomain.instances.members.each do |objid|
          raw = dbc.hget("custom_domain:#{objid}:object", 'extid')
          extid = raw ? (JSON.parse(raw) rescue raw) : nil
          next if extid.nil? || extid.to_s.empty?

          log.hset(temp_key, extid.to_s, hashkey.serialize_value(objid.to_s))
          count += 1
        end
        log.swap(temp_key, final_key, label: :extid_lookup)
        count
      end

      # Invariant: per-org sorted sets built from (objid, org_id, created) tuples
      # in clean instances; pre-existing keys without a live org are deleted.
      def rebuild_organization_domains(log)
        dbc = CustomDomain.dbclient
        old_keys = []
        dbc.scan_each(match: 'organization:*:domains') { |k| old_keys << k }
        log.note "organization_domains existing_keys=#{old_keys.size}"

        orgs_seen = {}
        count = 0
        CustomDomain.instances.members.each_slice(100) do |batch|
          CustomDomain.load_multi(batch).compact.each do |obj|
            next if obj.org_id.to_s.empty?

            temp = (orgs_seen[obj.org_id] ||= "organization:#{obj.org_id}:domains:rebuild:#{Familia.now.to_i}")
            score = obj.created ? obj.created.to_f : Familia.now.to_f
            log.zadd(temp, score, obj.identifier.to_s)
            count += 1
          end
        end
        orgs_seen.each { |oid, temp| log.swap(temp, "organization:#{oid}:domains", label: :org_swap) }
        old_keys.each do |k|
          oid = k[/\Aorganization:([^:]+):domains\z/, 1]
          log.del(k, label: :org_orphan) unless oid && orgs_seen.key?(oid)
        end
        count
      end

      class CommandLog
        attr_reader :total

        def initialize(execute:, io:, verbose:)
          @execute = execute
          @io      = io
          @verbose = verbose
          @total   = 0
          @counts  = Hash.new(0)
          @dbc     = CustomDomain.dbclient
        end

        def execute? = @execute

        def banner
          @io.puts(@execute ? '[EXECUTE] Applying changes:' : '[DRY-RUN] Would execute the following:')
        end

        def note(msg)  = (@verbose || !@execute) && @io.puts("# #{msg}")
        def warn(msg)  = @io.puts("# WARN #{msg}")

        def hset(key, field, value)
          emit("HSET #{key} #{field} #{value.inspect}")
          bump(key)
          @dbc.hset(key, field, value) if @execute
        end

        def zadd(key, score, member)
          emit("ZADD #{key} #{score} #{member}")
          bump(key)
          @dbc.zadd(key, score, member) if @execute
        end

        def del(key, label: nil)
          emit("DEL #{key}")
          bump(label || key)
          @dbc.del(key) if @execute
        end

        def swap(temp_key, final_key, label:)
          if !@execute && @counts[temp_key].zero?
            emit("# SKIP-SWAP #{label} (empty temp)")
            return
          end
          emit("DEL #{final_key}")
          emit("RENAME #{temp_key} #{final_key}")
          bump(label)
          ATOMIC_SWAP.atomic_swap(temp_key, final_key, @dbc) if @execute
        end

        private

        def emit(line)
          @io.puts(line)
          @total += 1
        end

        def bump(label) = @counts[label.to_s] += 1
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  execute = ARGV.include?('--execute')
  verbose = ARGV.include?('--verbose') || ARGV.include?('-v')
  if ARGV.include?('--help') || ARGV.include?('-h')
    puts File.read(__FILE__).lines.take_while { |l| l.start_with?('#') || l.chomp.empty? }.join
    exit 0
  end
  if execute && ENV['CONFIRM'] != 'yes'
    warn 'Refusing: --execute requires CONFIRM=yes.'
    exit 2
  end
  OT.boot! :cli
  abort 'Boot failed: OT.conf is nil' unless OT.conf
  begin
    Onetime::CustomDomain::IndexRebuilder.run(execute: execute, verbose: verbose)
    exit 0
  rescue StandardError => ex
    warn "[rebuild_custom_domain_indexes] #{ex.class}: #{ex.message}"
    warn ex.backtrace.first(10).join("\n") if verbose
    exit 1
  end
end
