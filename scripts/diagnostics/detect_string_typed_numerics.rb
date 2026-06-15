# scripts/diagnostics/detect_string_typed_numerics.rb
#
# Read-only diagnostic for issue #3424. Scans Secret and Receipt records in
# Redis and reports any whose numeric fields are stored as JSON *strings*
# (e.g. "604800") instead of JSON numbers (604800).
#
# WHY THIS IS A DISTINCT CHECK FROM check_raw_email_fields.rb (#3016):
#   #3016 looks for values that are not valid JSON at all (a bare,
#   unquoted string). This bug is the mirror image: the value IS valid
#   JSON, but it is a JSON string where the V3 API schema requires a JSON
#   number. Familia v2 storage is type-preserving, so a field written as a
#   Ruby String anywhere upstream round-trips as a String forever, and the
#   strict z.number() V3 schema then rejects the whole secret payload — the
#   recipient sees "no longer available" for a secret that was never
#   consumed.
#
# The safe_dump boundary cast (lib/onetime/models/{secret,receipt}/features/
# safe_dump_fields.rb) makes the API serve correct numbers regardless, so
# this scan is for finding and locating the corruption at rest, not for
# restoring availability. It does NOT modify any data.
#
# The per-record signature is the useful part for root-causing: created and
# updated are float epoch seconds written by Familia on every save, so a
# record whose `updated` is a clean number while `lifespan`/`created` are
# strings was poisoned at creation and saved since; an all-strings record
# was written once and never re-saved through the model.
#
# Usage standalone:
#   bundle exec ruby scripts/diagnostics/detect_string_typed_numerics.rb
#
# Usage from bin/console (does NOT auto-run; call explicitly):
#   load 'scripts/diagnostics/detect_string_typed_numerics.rb'
#   Diagnostics::DetectStringTypedNumerics.run(verbose: true)
#
# frozen_string_literal: true

module Diagnostics
  module DetectStringTypedNumerics
    extend self

    # Numeric fields stored on each model (derived safe_dump fields like
    # secret_ttl on Secret or metadata_ttl on Receipt are computed from these
    # and need no separate check).
    MODELS = {
      'secret' => { match: 'secret:*:object', fields: %w[lifespan created updated] },
      'receipt' => { match: 'receipt:*:object', fields: %w[secret_ttl lifespan created updated] },
    }.freeze

    # True when a stored Redis value is valid JSON whose parsed Ruby type is
    # a String. That is the #3424 poison: "604800" parses to the String
    # "604800", not the Integer 604800.
    #
    # Returns false for:
    #   - nil / empty (unset field)
    #   - bare JSON numbers ("604800" without quotes parses to a number)
    #   - bare non-JSON strings (those are #3016's concern; parse raises here)
    def string_typed_numeric?(raw)
      return false if raw.nil? || raw.empty?

      Familia::JsonSerializer.parse(raw).is_a?(String)
    rescue JSON::ParserError, Familia::SerializerError
      false
    end

    # Given a model's raw hgetall hash, return the subset of the supplied
    # numeric field names whose stored value is a JSON string.
    def poisoned_fields(fields, field_names)
      field_names.select { |name| string_typed_numeric?(fields[name]) }
    end

    # scan_count is the Redis SCAN COUNT hint per iteration; raise it for
    # large keyspaces to reduce round-trips (at the cost of longer
    # individual SCAN calls on the server).
    def run(sample_limit: 10, verbose: false, scan_count: 200)
      redis  = Familia.dbclient
      report = {}

      MODELS.each do |model, spec|
        report[model] = scan_model(redis, model, spec, sample_limit, scan_count)
      end

      print_report(report, sample_limit, verbose)
      report
    end

    private

    def scan_model(redis, model, spec, sample_limit, scan_count)
      result = { total: 0, poisoned: 0, by_field: Hash.new(0), samples: [] }

      redis.scan_each(match: spec[:match], count: scan_count) do |key|
        next unless redis.type(key) == 'hash'

        result[:total] += 1
        if (result[:total] % 1000).zero?
          $stderr.print "\rScanned #{result[:total]} #{model} records..."
        end

        fields = redis.hgetall(key)
        bad    = poisoned_fields(fields, spec[:fields])
        next if bad.empty?

        result[:poisoned]                         += 1
        bad.each { |name| result[:by_field][name] += 1 }
        next unless result[:samples].size < sample_limit

        result[:samples] << {
          key: key,
          poisoned_fields: bad,
          stored: bad.to_h { |name| [name, fields[name]] },
          # Signature: was `updated` healed by a later save while other fields
          # stayed poisoned? Helps distinguish poisoned-at-create from a writer
          # that bypasses the model entirely.
          updated_healthy: !string_typed_numeric?(fields['updated']) && !fields['updated'].to_s.empty?,
        }
      end

      $stderr.print "\r" if result[:total] >= 1000
      result
    end

    def print_report(report, sample_limit, verbose)
      puts '=' * 60
      puts 'String-Typed Numeric Field Diagnostic (#3424)'
      puts '=' * 60
      puts

      total_poisoned = report.values.sum { |r| r[:poisoned] }

      report.each do |model, r|
        puts "#{model}: #{r[:poisoned]} poisoned of #{r[:total]} scanned"
        r[:by_field].sort.each { |name, count| puts "    #{name}: #{count}" }
      end
      puts

      if total_poisoned.zero?
        puts '(No string-typed numeric fields found — keyspace is clean.)'
        return
      end

      report.each do |model, r|
        next if r[:samples].empty?

        puts '-' * 60
        puts "Sample #{model} records (#{[r[:poisoned], sample_limit].min} of #{r[:poisoned]}):"
        puts '-' * 60
        r[:samples].each_with_index do |sample, i|
          puts "  #{i + 1}. key: #{sample[:key]}"
          puts "     poisoned: #{sample[:poisoned_fields].join(', ')}"
          puts "     updated healed by later save: #{sample[:updated_healthy]}"
          if verbose
            sample[:stored].each { |name, value| puts "       #{name}: #{value}" }
          end
          puts
        end
      end
    end
  end
end

# Auto-run only on direct execution. Deliberately NOT keyed on defined?(OT):
# requiring this file (e.g. from a tryout) must not trigger a full keyspace
# scan. From a console, call Diagnostics::DetectStringTypedNumerics.run.
if __FILE__ == $PROGRAM_NAME
  require_relative '../../lib/onetime'
  OT.boot! :cli
  Diagnostics::DetectStringTypedNumerics.run(verbose: true)
end
