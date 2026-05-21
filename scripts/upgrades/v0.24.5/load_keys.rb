#!/usr/bin/env ruby
# frozen_string_literal: true

# Loads migrated data into Valkey/Redis from transformed JSONL files.
# Processes both transformed records and index commands (ZADD/HSET/etc).
#
# Record-loading strategy: replay the typed payload (fields_b64 / value_b64 /
# members / zmembers) emitted by dump_keys.rb via native commands. This is
# the only load representation — there is no DUMP/RESTORE fallback (Redis 8
# source produces RDB v12 blobs that Valkey 8 rejects). Records that arrive
# without a typed payload are recorded as soft errors and skipped.
#
# The loader DEL's the key before writing collection types (hash/set/zset/list)
# so re-runs are idempotent.
#
# Default: execute (writes to Valkey/Redis). Pass --dry-run to preview.
# This default is intentional: orchestrators (upgrade.sh, run_pipeline.sh) rely
# on the run_pipeline.sh contract that pipeline scripts default to execute and
# upgrade.sh's $DRY_RUN_FLAG ("--dry-run" when not executing) is forwarded here.
# See run_pipeline.sh header for the full contract; flipping this default would
# silently break upgrade.sh's dry-run propagation.
#
# Error handling: per-record soft errors (Base64 decode, JSON parse, single-key
# Redis errors not in HARD_ERROR_PATTERNS) are collected to @stats[model][:errors]
# and the run continues so all issues surface in one pass. HARD Redis errors
# (WRONGTYPE, NOAUTH, READONLY, LOADING, CLUSTERDOWN, MISCONF, OOM) abort the
# run immediately with exit code 2 — these indicate
# environment misconfiguration or structural data conflict where continuing
# would compound damage or amount to retry-spam against a broken environment.
# Exit codes: 0 clean, 1 soft errors only, 2 hard error fail-fast.
#
# Usage:
#   ruby scripts/upgrades/v0.24.5/load_keys.rb [OPTIONS]
#
# Options:
#   --input-dir=DIR      Input directory with model subdirs (default: data/upgrades/v0.24.5)
#   --valkey-url=URL     Valkey/Redis URL (env: VALKEY_URL or REDIS_URL)
#   --model=NAME         Load only specific model (customer, organization, customdomain, receipt, secret)
#   --dry-run            Count records without loading
#   --skip-indexes       Load only transformed records (skip index commands)
#   --skip-records       Load only indexes (skip record loads)
#
# Models are loaded in dependency order: customer -> organization -> customdomain -> receipt -> secret
#
# Input files per model (in subdirs):
#   - {model}_transformed.jsonl: Records to load (typed payload per key type)
#   - {model}_indexes.jsonl: Redis commands to execute (ZADD, HSET, SADD, INCRBY)

require 'redis'
require 'json'
require 'base64'
require 'uri'
require 'set'

require_relative 'lib/progress'

# Assumes script is run from project root: ruby scripts/upgrades/v0.24.5/load_keys.rb
DEFAULT_DATA_DIR = 'data/upgrades/v0.24.5'

class KeyLoader
  # Models in dependency order with their target databases
  MODELS = {
    'customer' => { db: 0 },
    'organization' => { db: 0 },
    'customdomain' => { db: 0 },
    'receipt' => { db: 0, dir: 'metadata' },
    'secret' => { db: 0 },
  }.freeze

  VALID_COMMANDS = %w[ZADD HSET SADD INCRBY].freeze

  # Redis errors that abort the run immediately. Continuing past these either
  # compounds data corruption (WRONGTYPE: every subsequent same-keyspace write
  # fails the same way), is impossible (NOAUTH, READONLY), or means the input
  # itself is broken (DUMP payload checksum). See header for full rationale.
  HARD_ERROR_PATTERNS = [
    /\AWRONGTYPE/,
    /\ANOAUTH/,
    /\AREADONLY/,
    /\ALOADING/,
    /\ACLUSTERDOWN/,
    /\AMISCONF/,
    /\AOOM\b/,
    /DUMP payload version or checksum/,
  ].freeze

  class HardLoadError < StandardError
    attr_reader :model_name, :key, :original
    def initialize(message, model_name:, key:, original:)
      super(message)
      @model_name = model_name
      @key        = key
      @original   = original
    end
  end

  def initialize(input_dir:, valkey_url:, model: nil, dry_run: false, skip_indexes: false, skip_records: false)
    @input_dir     = input_dir
    @valkey_url    = valkey_url
    @target_model  = model
    @dry_run       = dry_run
    @skip_indexes  = skip_indexes
    @skip_records  = skip_records
    @redis_clients = {}

    # Track unique keys for reconciliation
    @record_keys = Set.new
    @index_keys  = Set.new

    @stats = Hash.new do |h, k|
      h[k] = {
        records_restored: 0,
        records_skipped: 0,
        indexes_executed: 0,
        indexes_skipped: 0,
        errors: [],
      }
    end
  end

  def run
    validate_options
    models_to_load = determine_models

    if models_to_load.empty?
      puts 'No models to load.'
      return @stats
    end

    puts "Loading #{models_to_load.join(', ')} from #{@input_dir}"
    puts "Target: #{@valkey_url.sub(/:[^:@]*@/, ':***@')}"
    puts "Mode: #{mode_description}"
    puts

    models_to_load.each do |model_name|
      dir_override = MODELS[model_name][:dir]
      load_model(model_name, dir_override)
    end

    print_summary
    exit_with_status
  rescue HardLoadError => ex
    warn ''
    warn "FATAL: hard error during #{ex.model_name} load — aborting before further damage."
    warn "  key:   #{ex.key.inspect}"
    warn "  error: #{ex.original.message}"
    warn ''
    warn 'Hard errors (WRONGTYPE, NOAUTH, READONLY, LOADING, CLUSTERDOWN, MISCONF,'
    warn 'OOM, corrupt DUMP) indicate environment misconfiguration or structural'
    warn 'data conflict where continuing would compound damage. Investigate the'
    warn 'cause above, then re-run.'
    print_summary
    exit 2
  ensure
    close_connections
  end

  private

  def validate_options
    unless Dir.exist?(@input_dir)
      raise ArgumentError, "Input directory not found: #{@input_dir}"
    end

    if @target_model && !MODELS.key?(@target_model)
      raise ArgumentError, "Unknown model: #{@target_model}. Valid models: #{MODELS.keys.join(', ')}"
    end

    if @skip_indexes && @skip_records
      raise ArgumentError, 'Cannot specify both --skip-indexes and --skip-records'
    end
  end

  def determine_models
    if @target_model
      [@target_model]
    else
      MODELS.keys
    end
  end

  def mode_description
    parts = []
    parts << 'dry-run' if @dry_run
    parts << 'records only' if @skip_indexes
    parts << 'indexes only' if @skip_records
    parts << 'full load' if parts.empty?
    parts << "pipeline=#{pipeline_batch_size}" if pipeline_enabled?
    parts.join(', ')
  end

  # Pipelining is opt-in via OTS_MIGRATION_PIPELINE.
  #   unset / 0 / false / no / off -> off (default; per-record round trips)
  #   1 / true / yes / on          -> on, batch size 500
  #   <positive integer>           -> on, that batch size
  # Memoized per loader so we read ENV once at startup.
  def pipeline_batch_size
    return @pipeline_batch_size if defined?(@pipeline_batch_size)
    raw = ENV['OTS_MIGRATION_PIPELINE'].to_s.strip.downcase
    @pipeline_batch_size =
      if raw.empty? || %w[0 false no off].include?(raw)
        0
      elsif (parsed = Integer(raw, exception: false)) && parsed > 0
        parsed
      elsif %w[1 true yes on].include?(raw)
        500
      else
        0
      end
  end

  def pipeline_enabled?
    pipeline_batch_size > 0
  end

  def load_model(model_name, dir_name = nil)
    dir_name ||= model_name
    puts "=== Loading #{model_name} (via #{dir_name}) ==="
    model_dir  = File.join(@input_dir, dir_name)

    unless Dir.exist?(model_dir)
      if @dry_run
        puts "  No data directory yet: #{model_dir}"
      else
        raise "Directory not found: #{model_dir} — did Phase 2 complete?"
      end
      return
    end

    # Load transformed records (typed-payload replay)
    unless @skip_records
      transformed_file = File.join(model_dir, "#{model_name}_transformed.jsonl")
      if File.exist?(transformed_file)
        load_transformed_records(model_name, transformed_file)
      else
        msg = "Missing transformed file: #{transformed_file} (Phase 2 artifact). " \
              'Re-run Phase 2, or pass --skip-records if loading indexes only is intentional.'
        warn "  ERROR: #{msg}"
        @stats[model_name][:errors] << { error: msg, file: transformed_file }
      end
    end

    # Execute index commands
    unless @skip_indexes
      indexes_file = File.join(model_dir, "#{model_name}_indexes.jsonl")
      if File.exist?(indexes_file)
        execute_index_commands(model_name, indexes_file)
      else
        msg = "Missing indexes file: #{indexes_file} (Phase 2 artifact). " \
              'Re-run Phase 2, or pass --skip-indexes if loading records only is intentional.'
        warn "  ERROR: #{msg}"
        @stats[model_name][:errors] << { error: msg, file: indexes_file }
      end
    end

    puts
  end

  def load_transformed_records(model_name, file_path)
    puts "  Loading records from #{File.basename(file_path)}..."
    target_db = MODELS[model_name][:db]
    redis     = get_redis(target_db)
    progress  = Upgrade::ProgressReporter.new("#{model_name} RESTORE")

    if pipeline_enabled?
      puts "    Pipelining record loads in batches of #{pipeline_batch_size}"
      batch = []
      File.foreach(file_path) do |line|
        record   = JSON.parse(line, symbolize_names: true)
        prepared = prepare_record(model_name, record)
        next unless prepared

        batch << prepared
        if batch.size >= pipeline_batch_size
          flush_record_batch(model_name, redis, batch)
          progress.tick(batch.size)
          batch.clear
        end
      rescue JSON::ParserError => ex
        @stats[model_name][:errors] << { error: "JSON parse error: #{ex.message}" }
      end
      unless batch.empty?
        flush_record_batch(model_name, redis, batch)
        progress.tick(batch.size)
      end
    else
      File.foreach(file_path) do |line|
        record = JSON.parse(line, symbolize_names: true)
        restore_record(model_name, redis, record)
        progress.tick
      rescue JSON::ParserError => ex
        @stats[model_name][:errors] << { error: "JSON parse error: #{ex.message}" }
      end
    end

    progress.finish
    puts "    Records restored: #{@stats[model_name][:records_restored]}"
    puts "    Records skipped: #{@stats[model_name][:records_skipped]}" if @stats[model_name][:records_skipped] > 0
  end

  def restore_record(model_name, redis, record)
    prepared = prepare_record(model_name, record)
    return unless prepared

    apply_record(redis, prepared)
    @record_keys << prepared[:key]
    @stats[model_name][:records_restored] += 1
  rescue Redis::CommandError => ex
    op = prepared ? prepared[:kind].to_s.upcase : 'LOAD'
    key = prepared && prepared[:key]
    fatal_if_hard_redis_error!(ex, model_name: model_name, key: key, op: op)
    @stats[model_name][:records_skipped] += 1
    @stats[model_name][:errors] << { key: key, error: "#{op} failed: #{ex.message}" }
  end

  # Validate, decode, and produce a load descriptor ready for either single-
  # shot or pipelined execution. Per-record soft errors (missing payload,
  # base64 decode) are recorded against @stats here so both code paths get
  # identical error semantics. Returns nil for skip; in dry-run mode the key
  # is counted as loaded and nil returned.
  #
  # Descriptor shapes (`:kind` discriminator):
  #   { kind: :hash,    key:, fields:    Hash<String,String>, pttl: }
  #   { kind: :string,  key:, value:     String,              pttl: }
  #   { kind: :set,     key:, members:   Array<String>,       pttl: }
  #   { kind: :zset,    key:, pairs:     Array<[Float,String]>,pttl: }
  #   { kind: :list,    key:, members:   Array<String>,       pttl: }
  #
  # `pttl` is 0 for "no expiry" or a positive PEXPIRE value in milliseconds.
  def prepare_record(model_name, record)
    key    = record[:key]
    ttl_ms = record[:ttl_ms]

    unless key
      @stats[model_name][:records_skipped] += 1
      @stats[model_name][:errors] << { key: key, error: 'Missing key' }
      return nil
    end

    if @dry_run
      @record_keys << key
      @stats[model_name][:records_restored] += 1
      return nil
    end

    pttl = ttl_ms.to_i == -1 ? 0 : ttl_ms.to_i

    if (fields_b64 = record[:fields_b64])
      fields = decode_fields_b64(model_name, key, fields_b64)
      return nil unless fields
      return { kind: :hash, key: key, fields: fields, pttl: pttl }
    end

    if (value_b64 = record[:value_b64])
      value = decode_b64(model_name, key, value_b64, 'value_b64')
      return nil unless value
      return { kind: :string, key: key, value: value, pttl: pttl }
    end

    if (zmembers = record[:zmembers])
      pairs = zmembers.map { |entry| [entry[1].to_f, entry[0].to_s] }
      return { kind: :zset, key: key, pairs: pairs, pttl: pttl }
    end

    if (members = record[:members])
      kind = record[:type].to_s == 'list' ? :list : :set
      return { kind: kind, key: key, members: members.map(&:to_s), pttl: pttl }
    end

    @stats[model_name][:records_skipped] += 1
    @stats[model_name][:errors] << { key: key, error: 'No typed payload (missing fields_b64/value_b64/members/zmembers)' }
    nil
  end

  def decode_b64(model_name, key, value, label)
    Base64.strict_decode64(value.to_s)
  rescue ArgumentError => ex
    @stats[model_name][:records_skipped] += 1
    @stats[model_name][:errors] << { key: key, error: "Base64 decode failed (#{label}): #{ex.message}" }
    nil
  end

  def decode_fields_b64(model_name, key, fields_b64)
    result = {}
    fields_b64.each do |field, encoded|
      result[field.to_s] = Base64.strict_decode64(encoded.to_s)
    end
    result
  rescue ArgumentError => ex
    @stats[model_name][:records_skipped] += 1
    @stats[model_name][:errors] << { key: key, error: "Base64 decode failed (fields_b64): #{ex.message}" }
    nil
  end

  # Single-shot apply (non-pipelined path). Returns nil; raises Redis::CommandError
  # on failure for the surrounding rescue to handle.
  def apply_record(redis, prepared)
    push_load_commands(redis, prepared)
  end

  # Push the redis commands required to load `prepared` against `target`
  # (either a Redis client for single-shot or a pipeline accumulator). Returns
  # the count of commands pushed so the pipelined caller can map results back
  # to the originating record.
  #
  # All collection types DEL the key first so re-runs are idempotent
  # (HSET/SADD/ZADD/RPUSH would otherwise leave stale fields/members behind
  # from a prior partial load).
  def push_load_commands(target, prepared)
    case prepared[:kind]
    when :hash    then push_hash(target, prepared)
    when :string  then push_string(target, prepared)
    when :set     then push_set(target, prepared)
    when :zset    then push_zset(target, prepared)
    when :list    then push_list(target, prepared)
    else
      raise ArgumentError, "Unknown load kind: #{prepared[:kind].inspect}"
    end
  end

  def push_hash(target, prepared)
    target.del(prepared[:key])
    if prepared[:fields].empty?
      1
    else
      target.hset(prepared[:key], prepared[:fields])
      if prepared[:pttl] > 0
        target.pexpire(prepared[:key], prepared[:pttl])
        3
      else
        2
      end
    end
  end

  def push_string(target, prepared)
    if prepared[:pttl] > 0
      target.set(prepared[:key], prepared[:value], px: prepared[:pttl])
    else
      target.set(prepared[:key], prepared[:value])
    end
    1
  end

  def push_set(target, prepared)
    target.del(prepared[:key])
    if prepared[:members].empty?
      1
    else
      target.sadd(prepared[:key], prepared[:members])
      if prepared[:pttl] > 0
        target.pexpire(prepared[:key], prepared[:pttl])
        3
      else
        2
      end
    end
  end

  def push_zset(target, prepared)
    target.del(prepared[:key])
    if prepared[:pairs].empty?
      1
    else
      target.zadd(prepared[:key], prepared[:pairs])
      if prepared[:pttl] > 0
        target.pexpire(prepared[:key], prepared[:pttl])
        3
      else
        2
      end
    end
  end

  def push_list(target, prepared)
    target.del(prepared[:key])
    if prepared[:members].empty?
      1
    else
      target.rpush(prepared[:key], prepared[:members])
      if prepared[:pttl] > 0
        target.pexpire(prepared[:key], prepared[:pttl])
        3
      else
        2
      end
    end
  end

  def flush_record_batch(model_name, redis, prepared_batch)
    return if prepared_batch.empty?

    # Each prepared record may push 1+ commands (DEL + write + PEXPIRE for
    # collection types; SET for strings). Track per-record command counts so
    # we can attribute pipeline results back to the originating record.
    # exception: false preserves the per-key error granularity of the
    # non-pipelined path.
    command_counts = []
    results = redis.pipelined(exception: false) do |pipe|
      prepared_batch.each do |prepared|
        command_counts << push_load_commands(pipe, prepared)
      end
    end

    cursor = 0
    prepared_batch.each_with_index do |prepared, idx|
      n = command_counts[idx]
      record_results = results[cursor, n]
      cursor += n

      error = record_results.find { |r| r.is_a?(Redis::CommandError) }
      key = prepared[:key]
      if error
        op = prepared[:kind].to_s.upcase
        fatal_if_hard_redis_error!(error, model_name: model_name, key: key, op: op)
        @stats[model_name][:records_skipped] += 1
        @stats[model_name][:errors] << { key: key, error: "#{op} failed: #{error.message}" }
      else
        @record_keys << key
        @stats[model_name][:records_restored] += 1
      end
    end
  end

  def execute_index_commands(model_name, file_path)
    puts "  Executing indexes from #{File.basename(file_path)}..."
    target_db = MODELS[model_name][:db]
    redis     = get_redis(target_db)
    progress  = Upgrade::ProgressReporter.new("#{model_name} indexes")

    if pipeline_enabled?
      puts "    Pipelining index commands in batches of #{pipeline_batch_size}"
      batch = []
      File.foreach(file_path) do |line|
        cmd      = JSON.parse(line, symbolize_names: true)
        prepared = prepare_index_command(model_name, cmd)
        next unless prepared

        batch << prepared
        if batch.size >= pipeline_batch_size
          flush_index_batch(model_name, redis, batch)
          progress.tick(batch.size)
          batch.clear
        end
      rescue JSON::ParserError => ex
        @stats[model_name][:errors] << { error: "JSON parse error: #{ex.message}" }
      end
      unless batch.empty?
        flush_index_batch(model_name, redis, batch)
        progress.tick(batch.size)
      end
    else
      File.foreach(file_path) do |line|
        cmd = JSON.parse(line, symbolize_names: true)
        execute_command(model_name, redis, cmd)
        progress.tick
      rescue JSON::ParserError => ex
        @stats[model_name][:errors] << { error: "JSON parse error: #{ex.message}" }
      end
    end

    progress.finish
    puts "    Index commands executed: #{@stats[model_name][:indexes_executed]}"
    puts "    Index commands skipped: #{@stats[model_name][:indexes_skipped]}" if @stats[model_name][:indexes_skipped] > 0
  end

  def execute_command(model_name, redis, cmd)
    prepared = prepare_index_command(model_name, cmd)
    return unless prepared

    command, key, args = prepared
    case command
    when 'ZADD'   then redis.zadd(key, *args)
    when 'HSET'   then redis.hset(key, *args)
    when 'SADD'   then redis.sadd(key, *args)
    when 'INCRBY' then redis.incrby(key, args.first.to_i)
    end

    @index_keys << key
    @stats[model_name][:indexes_executed] += 1
  rescue Redis::CommandError => ex
    fatal_if_hard_redis_error!(ex, model_name: model_name, key: key, op: command)
    @stats[model_name][:indexes_skipped] += 1
    @stats[model_name][:errors] << { key: key, command: command, error: ex.message }
  end

  # Validate an index command and produce a [command, key, args] triple ready
  # for either single-shot or pipelined execution. Per-cmd soft errors are
  # recorded here so both paths get identical error semantics. Returns nil
  # for skip; in dry-run mode the key is counted as executed and nil returned.
  def prepare_index_command(model_name, cmd)
    command = cmd[:command]
    key     = cmd[:key]
    args    = cmd[:args]

    unless VALID_COMMANDS.include?(command)
      @stats[model_name][:indexes_skipped] += 1
      @stats[model_name][:errors] << { key: key, error: "Unknown command: #{command}" }
      return nil
    end

    unless key && args.is_a?(Array)
      @stats[model_name][:indexes_skipped] += 1
      @stats[model_name][:errors] << { key: key, error: 'Missing key or args' }
      return nil
    end

    if @dry_run
      @index_keys << key
      @stats[model_name][:indexes_executed] += 1
      return nil
    end

    [command, key, args]
  end

  def flush_index_batch(model_name, redis, prepared)
    return if prepared.empty?

    results = redis.pipelined(exception: false) do |pipe|
      prepared.each do |command, key, args|
        case command
        when 'ZADD'   then pipe.zadd(key, *args)
        when 'HSET'   then pipe.hset(key, *args)
        when 'SADD'   then pipe.sadd(key, *args)
        when 'INCRBY' then pipe.incrby(key, args.first.to_i)
        end
      end
    end

    results.each_with_index do |result, idx|
      command, key, _args = prepared[idx]
      if result.is_a?(Redis::CommandError)
        fatal_if_hard_redis_error!(result, model_name: model_name, key: key, op: command)
        @stats[model_name][:indexes_skipped] += 1
        @stats[model_name][:errors] << { key: key, command: command, error: result.message }
      else
        @index_keys << key
        @stats[model_name][:indexes_executed] += 1
      end
    end
  end

  def fatal_if_hard_redis_error!(ex, model_name:, key:, op:)
    return unless HARD_ERROR_PATTERNS.any? { |pattern| ex.message.match?(pattern) }
    raise HardLoadError.new(
      "#{op} failed on #{key.inspect} (#{model_name}): #{ex.message}",
      model_name: model_name, key: key, original: ex,
    )
  end

  # Larger timeouts than the 1s default — pipelined batches of 500 writes and
  # PEXPIRE on large hashes/zsets routinely take >1s. Matches dump_keys.rb and
  # the other heavy data-moving scripts in this directory.
  def get_redis(db)
    @redis_clients[db] ||= begin
      uri      = URI.parse(@valkey_url)
      uri.path = "/#{db}"
      client   = Redis.new(
        url: uri.to_s,
        connect_timeout: 10,
        read_timeout: 30,
        write_timeout: 10,
        reconnect_attempts: [0.5, 1.0, 2.0],
      )
      client.ping # Verify connection
      client
    rescue Redis::CannotConnectError => ex
      warn "Failed to connect to Redis (DB #{db}): #{ex.message}"
      exit 1
    end
  end

  def close_connections
    @redis_clients.each_value(&:close)
    @redis_clients.clear
  end

  def print_summary
    puts '=' * 60
    puts 'LOAD SUMMARY'
    puts '=' * 60
    puts

    total_records = 0
    total_indexes = 0
    total_errors  = 0

    @stats.each do |model_name, stats|
      puts "#{model_name}:"
      puts "  Records restored:      #{stats[:records_restored]}"
      puts "  Records skipped:       #{stats[:records_skipped]}" if stats[:records_skipped] > 0
      puts "  Index commands:        #{stats[:indexes_executed]}"
      puts "  Index commands skipped: #{stats[:indexes_skipped]}" if stats[:indexes_skipped] > 0
      puts "  Errors:                #{stats[:errors].size}" if stats[:errors].any?
      puts

      total_records += stats[:records_restored]
      total_indexes += stats[:indexes_executed]
      total_errors  += stats[:errors].size
    end

    puts '-' * 60
    puts 'TOTALS:'
    puts "  Records restored:      #{total_records}"
    puts "  Index commands:        #{total_indexes}"
    puts "  Total errors:          #{total_errors}"
    puts

    # Reconciliation: compare expected vs actual key counts
    print_reconciliation

    return unless total_errors > 0

    puts 'ERRORS (first 20):'
    error_count = 0
    @stats.each do |model_name, stats|
      stats[:errors].each do |err|
        break if error_count >= 20

        puts "  [#{model_name}] #{err}"
        error_count += 1
      end
      break if error_count >= 20
    end
    puts "  ... and #{total_errors - 20} more" if total_errors > 20
  end

  def print_reconciliation
    puts '-' * 60
    puts 'RECONCILIATION (Script Accounting):'
    puts

    record_count = @record_keys.size
    index_count  = @index_keys.size
    total_unique = (@record_keys | @index_keys).size

    overlap     = @record_keys & @index_keys
    overlap_count = overlap.size

    puts '  Keys tracked by this script:'
    puts "    Record keys (loaded):    #{record_count}"
    puts "    Index keys (commands):   #{index_count}"
    puts "    Total unique keys:       #{total_unique}"
    puts "    Overlap (both):          #{overlap_count}"

    if overlap_count > 0
      puts
      puts '  Overlap analysis:'

      # Group overlapping keys by prefix pattern
      patterns = Hash.new { |h, k| h[k] = [] }
      overlap.each do |key|
        # Classify by key structure: "model:{id}:suffix" -> "model:*:suffix"
        pattern = key.gsub(/:[a-f0-9]{20,}:/, ':*:')
                     .gsub(/:[a-f0-9-]{36}:/, ':*:')
                     .gsub(/:\d+:/, ':*:')
        patterns[pattern] << key
      end

      patterns.sort_by { |_p, keys| -keys.size }.each do |pattern, keys|
        puts "    #{pattern}: #{keys.size} keys"
        keys.first(3).each { |k| puts "      e.g. #{k}" }
        puts "      ... and #{keys.size - 3} more" if keys.size > 3
      end

      puts
      puts '  NOTE: Overlap occurs when a key is both loaded from typed payload'
      puts '  and targeted by an index command (ZADD/HSET/SADD). This is safe'
      puts '  if the index command is additive (ZADD to a sorted set) or if'
      puts '  it intentionally overwrites (HSET fields). Verify the patterns'
      puts '  above match expected cross-model relationships.'
    end

    if @dry_run
      puts
      puts '  Mode: dry-run (no data written to Redis)'
    end
    puts
    puts '  To verify: scripts/upgrades/v0.24.5/info.sh --target'
    puts
  end

  def exit_with_status
    total_errors = @stats.values.sum { |s| s[:errors].size }
    exit(1) if total_errors > 0
  end
end

def parse_args(args)
  options = {
    input_dir: DEFAULT_DATA_DIR,
    valkey_url: ENV['VALKEY_URL'] || ENV.fetch('REDIS_URL', nil),
    model: nil,
    dry_run: false,
    skip_indexes: false,
    skip_records: false,
  }

  args.each do |arg|
    case arg
    when /\A--input-dir=(.+)\z/
      options[:input_dir] = Regexp.last_match(1)
    when /\A--valkey-url=(.+)\z/
      options[:valkey_url] = Regexp.last_match(1)
    when /\A--model=(.+)\z/
      options[:model] = Regexp.last_match(1)
    when '--dry-run'
      options[:dry_run] = true
    when '--skip-indexes'
      options[:skip_indexes] = true
    when '--skip-records'
      options[:skip_records] = true
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby scripts/upgrades/v0.24.5/load_keys.rb [OPTIONS]

        Loads migrated data into Valkey/Redis from transformed JSONL files.

        Options:
          --input-dir=DIR      Input directory with model subdirs (default: data/upgrades/v0.24.5)
          --valkey-url=URL     Valkey/Redis URL (env: VALKEY_URL or REDIS_URL)
          --model=NAME         Load only specific model
          --dry-run            Count records without loading
          --skip-indexes       Load only transformed records (skip index commands)
          --skip-records       Load only indexes (skip record loads)
          --help               Show this help

        Models (loaded in dependency order, all into consolidated DB 0):
          customer       -> DB 0
          organization   -> DB 0
          customdomain   -> DB 0
          receipt        -> DB 0 (read from 'metadata' subdir)
          secret         -> DB 0

        Input files per model (in subdirs):
          {model}_transformed.jsonl   Records to load (typed payload per key type)
          {model}_indexes.jsonl       Redis commands (ZADD, HSET, SADD, INCRBY)

        Examples:
          # Load all models
          ruby load_keys.rb --valkey-url=redis://localhost:6379

          # Load single model
          ruby load_keys.rb --model=customer

          # Dry run to see counts
          ruby load_keys.rb --dry-run

          # Load only transformed records (no indexes)
          ruby load_keys.rb --skip-indexes

          # Load only indexes (no record loads)
          ruby load_keys.rb --skip-records
      HELP
      exit 0
    else
      warn "Unknown option: #{arg}"
      exit 1
    end
  end

  options
end

if __FILE__ == $PROGRAM_NAME
  options = parse_args(ARGV)

  loader = KeyLoader.new(
    input_dir: options[:input_dir],
    valkey_url: options[:valkey_url],
    model: options[:model],
    dry_run: options[:dry_run],
    skip_indexes: options[:skip_indexes],
    skip_records: options[:skip_records],
  )

  loader.run
end
