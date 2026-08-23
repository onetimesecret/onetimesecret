# lib/tasks/spec_selection.rake
#
# frozen_string_literal: true

# spec:fast selection-equivalence guard
# =====================================
#
# spec:fast used to be 13 rspec processes: spec:unit, spec:cli, and one per
# apps/*/*/spec tree. It is now three (spec:root_fast, spec:apps_fast, and
# spec:apps_config_ru), and the whole value of that consolidation rests on
# those invocations selecting exactly the files the 13 selected. That equivalence is NOT something a
# reviewer can check by reading the globs: rspec resolves --pattern and
# --exclude-pattern separately against each checked path, so an include and an
# exclude that look symmetric can behave asymmetrically (see the HARD RULE in
# lib/tasks/spec.rake). This file mechanises the check.
#
#   rake spec:verify_selection        file-level, <1s, loads zero spec files
#   rake spec:verify_selection:deep   example-ID level, ~35s, 16 rspec dry-runs
#
# The cheap task is the one meant to run everywhere (pre-commit, every CI job
# that touches spec plumbing). It re-derives the LEGACY 13-invocation selection
# from the same Dir.glob('apps/*/*/spec') that APP_SPECS uses, so a new app tree
# is picked up by the oracle and by the consolidated pattern in the same commit
# — the oracle cannot go stale by omission. The deep task exists for the cases
# the file list cannot see: metadata filters, --tag semantics, shared examples.
#
# See also: docs/adr/adr-007-test-process-boundaries.md

require 'rspec/core'

# Selection modelling helpers. Namespaced rather than top-level defs because
# every .rake file under lib/tasks shares one main object.
module SpecSelection
  extend self

  # Model ONE `rspec` invocation's file selection, without loading a single
  # spec file: build the Configuration object the CLI builds and read
  # files_to_run. That is the same code path `exe/rspec` uses, so this tracks
  # rspec-core's globbing semantics through upgrades instead of reimplementing
  # them.
  #
  # Seeding files_or_directories_to_run with default_path is load-bearing, not
  # boilerplate. Configuration#files_or_directories_to_run= only appends
  # default_path when $0 is literally 'rspec', and under rake it is not; skip it
  # and every glob is resolved relative to the repo root alone — symmetrically,
  # which hides exactly the include/exclude asymmetry this guard exists to
  # catch. Measured: the known-leaky single-invocation form reports its 52 extra
  # integration files with the seed and reports zero without it.
  #
  # @param pattern [String] rspec --pattern value (comma-separated globs)
  # @param exclude_pattern [String, nil] rspec --exclude-pattern value
  # @return [Array<String>] repo-relative spec file paths, sorted and unique
  def files(pattern:, exclude_pattern: nil)
    cfg                             = RSpec::Core::Configuration.new
    cfg.pattern                     = pattern
    cfg.exclude_pattern             = exclude_pattern if exclude_pattern
    cfg.files_or_directories_to_run = cfg.default_path
    cfg.files_to_run.map { |f| f.delete_prefix("#{Dir.pwd}/") }.sort.uniq
  end

  # The 13 rspec invocations spec:fast used to spawn, re-derived from the
  # filesystem rather than transcribed. The per-app half mirrors the
  # RSpec::Core::RakeTask bodies in lib/tasks/spec.rake's spec:apps namespace,
  # which are still live tasks for targeted runs — so this oracle stays honest
  # as long as those tasks exist.
  #
  # @return [Array<Hash>] invocation descriptors
  def legacy_invocations
    invocations = [
      { name: 'unit', pattern: 'spec/unit/**/*_spec.rb' },
      { name: 'cli',  pattern: 'spec/cli/**/*_spec.rb' },
    ]
    Dir.glob('apps/*/*/spec').sort.each do |path|
      invocations << {
        name: path.split('/')[1..2].join('_'),
        pattern: "#{path}/**/*_spec.rb",
        exclude_pattern: "#{path}/integration/**/*_spec.rb",
        tags: APPS_FAST_TAG_FILTERS,
      }
    end
    invocations
  end

  # The invocations spec:fast spawns today. Patterns come from the constants
  # the rake tasks themselves use, so the guard can never verify a pattern the
  # lane does not run.
  #
  # @return [Array<Hash>] invocation descriptors
  def fast_invocations
    [
      { name: 'root_fast', pattern: ROOT_FAST_PATTERN },
      {
        name: 'apps_fast',
        pattern: APPS_FAST_PATTERN,
        exclude_pattern: APPS_FAST_EXCLUDE,
        tags: APPS_FAST_TAG_FILTERS,
      },
      {
        name: 'apps_config_ru',
        pattern: 'apps/web/core/spec/controllers/{config_generator,page_bootstrap_me}_spec.rb',
      },
    ]
  end

  # Files root_fast picks up that NO legacy invocation ever claimed.
  #
  # spec/lib/onetime/jobs/workers/*_spec.rb arrived with #3810 and were run by
  # no lane at all — not spec:fast, not an integration lane, not spec:api. They
  # are adopted by root_fast here. Stating the adoption as a pattern rather than
  # a file list means a third spec/lib file is covered automatically, while
  # dropping spec/lib from ROOT_FAST_PATTERN still fails the guard loudly.
  ADOPTED_PATTERN = 'spec/lib/**/*_spec.rb'

  # Spec files that are knowingly run by NO lane. Every entry is drift being
  # tolerated, not a category — the list is printed on every successful run so
  # it cannot quietly become permanent, and a fourth orphan fails the task.
  #
  # These three sit directly in apps/web/billing/spec/integration/ with no mode
  # subdirectory. APPS_FAST_EXCLUDE drops them from spec:fast, and every
  # integration lane dispatches on apps/*/*/spec/integration/<mode>, so nothing
  # matches them. Only the manual `rake vcr:billing:verify` (whole billing tree)
  # ever loads them. Placing them means moving them under integration/full/ or
  # giving the integration tasks a mode-less bucket — a lane membership decision
  # for the billing tree, not something a rake consolidation should decide.
  UNRUN_SPECS = %w[
    apps/web/billing/spec/integration/pending_federation_spec.rb
    apps/web/billing/spec/integration/stripe_client_spec.rb
    apps/web/billing/spec/integration/webhook_validator_spec.rb
  ].freeze

  # Every *_spec.rb in the repo, bucketed by the lane that runs it. Buckets, not
  # tasks: spec/integration/full is legitimately run by spec:integration:full,
  # full:postgres and full:agnostic_on_pg, and that is not double-claiming.
  #
  # The integration bucket is enumerated per mode directory instead of globbing
  # spec/integration/** wholesale, so a new mode directory nothing dispatches
  # (spec/integration/staging/, say) shows up as an orphan rather than being
  # silently absorbed.
  #
  # @return [Hash{String => Array<String>}] lane name => claimed files
  def lane_claims
    integration  = INTEGRATION_MODES.flat_map do |mode|
      Dir.glob("spec/integration/#{mode}/**/*_spec.rb") +
        Dir.glob("apps/*/*/spec/integration/#{mode}/**/*_spec.rb")
    end
    integration += Dir.glob('spec/integration/all/**/*_spec.rb')
    integration += Dir.glob('apps/*/*/spec/integration/full_mfa/**/*_spec.rb')

    {
      'spec:fast' => fast_invocations.flat_map { |inv| files(**inv.except(:name, :tags)) }.sort.uniq,
      'spec:integration' => integration.sort.uniq,
      'spec:api' => Dir.glob('spec/api/**/*_spec.rb').sort.uniq,
    }
  end

  # Assemble the command line for one invocation descriptor. Mirrors
  # RSpec::Core::RakeTask#spec_command's flag order closely enough that the
  # dry-run exercises the same rspec argument parsing the lane does.
  #
  # @param inv [Hash] invocation descriptor
  # @param out [String] path for the JSON formatter
  # @return [String] shell command
  def dry_run_command(inv, out)
    parts = ['bundle exec rspec', "--pattern '#{inv[:pattern]}'"]
    parts << "--exclude-pattern '#{inv[:exclude_pattern]}'" if inv[:exclude_pattern]
    parts << inv[:tags] if inv[:tags]
    parts << "--dry-run --format json --out #{out}"
    parts.join(' ')
  end

  # Environment for the dry-runs.
  #
  # AUTH_DATABASE_URL is pinned OFF, not merely set: spec/support/
  # postgres_mode_suite_database.rb treats a postgres:// value there as "PG is
  # available" and stops excluding :postgres_database, which changes the counted
  # example total on both sides of the diff. The fast lane never has a database,
  # so unset is the honest model — and pinning it means a developer with a
  # direnv-loaded AUTH_DATABASE_URL gets the same answer CI does.
  #
  # @return [Hash{String => String, nil}]
  DRY_RUN_ENV = {
    'RACK_ENV' => 'test',
    'AUTHENTICATION_MODE' => 'simple',
    'AUTH_DATABASE_URL' => nil,
    'AUTH_DATABASE_URL_MIGRATIONS' => nil,
  }.freeze
end

namespace :spec do
  desc 'Verify spec:fast selects exactly what the legacy 13-invocation fan-out did'
  task :verify_selection do
    legacy  = SpecSelection.legacy_invocations
      .flat_map { |inv| SpecSelection.files(**inv.except(:name, :tags)) }
      .sort.uniq
    claims  = SpecSelection.lane_claims
    current = claims.fetch('spec:fast')
    adopted = SpecSelection.files(pattern: SpecSelection::ADOPTED_PATTERN)

    dropped           = legacy - current
    added             = (current - legacy) - adopted
    missing_adoptions = adopted - current

    unless dropped.empty? && added.empty? && missing_adoptions.empty?
      abort <<~MSG
        spec:fast selection drift — the consolidated invocations no longer
        select what the legacy per-tree invocations select.

          dropped (legacy ran these, spec:fast no longer does):
        #{dropped.empty? ? '    (none)' : dropped.map { |f| "    #{f}" }.join("\n")}

          added (spec:fast runs these, no legacy invocation did, and they are
          not covered by the documented adoption #{SpecSelection::ADOPTED_PATTERN}):
        #{added.empty? ? '    (none)' : added.map { |f| "    #{f}" }.join("\n")}

          adopted but no longer selected (ROOT_FAST_PATTERN lost spec/lib?):
        #{missing_adoptions.empty? ? '    (none)' : missing_adoptions.map { |f| "    #{f}" }.join("\n")}

        Fix the patterns in lib/tasks/spec.rake, or — if the change is
        deliberate — update this guard in the same commit.
      MSG
    end

    # Orphan/overlap check. A spec file that no lane runs is invisible drift:
    # it passes review, passes CI, and is never executed. That is exactly how
    # spec/lib/onetime/jobs/workers/*_spec.rb sat unrun since #3810.
    all     = Dir.glob('{spec,apps}/**/*_spec.rb').sort
    orphans = all - claims.values.flatten - SpecSelection::UNRUN_SPECS
    unless orphans.empty?
      abort <<~MSG
        spec files claimed by no lane (they never run):
        #{orphans.map { |f| "    #{f}" }.join("\n")}

        Place each one: add its directory to a lane in lib/tasks/spec.rake, or
        move the file under a directory an existing lane already claims.
      MSG
    end

    # Loud on success, not silent: a tolerated orphan that stops being reported
    # is indistinguishable from one that was fixed.
    stale = SpecSelection::UNRUN_SPECS - all
    abort "UNRUN_SPECS lists files that no longer exist: #{stale}" unless stale.empty?
    unless SpecSelection::UNRUN_SPECS.empty?
      warn "note: #{SpecSelection::UNRUN_SPECS.size} spec files are knowingly run by no lane:"
      SpecSelection::UNRUN_SPECS.each { |f| warn "    #{f}" }
    end

    overlaps = claims.values.flatten.tally.select { |_, count| count > 1 }.keys
    unless overlaps.empty?
      abort <<~MSG
        spec files claimed by more than one lane (they run twice, in two
        environments, and disagree about which one owns their fixtures):
        #{overlaps.map { |f| "    #{f}" }.join("\n")}
      MSG
    end

    puts format(
      'spec:fast selection OK — %d files (%d adopted from spec/lib), %d integration, %d api, %d total',
      current.size,
      adopted.size,
      claims.fetch('spec:integration').size,
      claims.fetch('spec:api').size,
      all.size,
    )
  end

  namespace :verify_selection do
    desc 'Verify spec:fast runs the same EXAMPLE IDs as the legacy fan-out (slow: 17 dry-runs)'
    task :deep do
      require 'json'

      outdir = 'tmp/spec_selection'
      mkdir_p outdir

      collect = ->(invocations, label) do
        invocations.flat_map do |inv|
          out = File.join(outdir, "#{label}_#{inv[:name]}.json")
          sh SpecSelection::DRY_RUN_ENV, SpecSelection.dry_run_command(inv, out)
          JSON.parse(File.read(out)).fetch('examples').map { |ex| ex.fetch('id') }
        end
      end

      # The legacy fan-out never ran spec/lib (see ADOPTED_PATTERN), so the
      # oracle gets it as a 14th invocation. Without it the diff reports the
      # adoption as drift on every run and the guard becomes noise.
      legacy  = collect.call(
        SpecSelection.legacy_invocations +
          [{ name: 'adopted', pattern: SpecSelection::ADOPTED_PATTERN }],
        'legacy',
      )
      current = collect.call(SpecSelection.fast_invocations, 'fast')

      missing = legacy - current
      extra   = current - legacy

      puts format(
        'legacy=%d (uniq %d)  spec:fast=%d (uniq %d)  missing=%d  extra=%d',
        legacy.size,
        legacy.uniq.size,
        current.size,
        current.uniq.size,
        missing.size,
        extra.size,
      )

      unless missing.empty? && extra.empty?
        abort <<~MSG
          spec:fast example drift.

            missing (legacy executed, spec:fast does not) — first 20 of #{missing.size}:
          #{missing.first(20).map { |id| "    #{id}" }.join("\n")}

            extra (spec:fast executes, legacy did not) — first 20 of #{extra.size}:
          #{extra.first(20).map { |id| "    #{id}" }.join("\n")}
        MSG
      end

      # Duplicate IDs across invocations mean a file is loaded twice, which is
      # the file-level overlap check restated at example granularity — it also
      # catches a shared-example host pulled in by two patterns.
      dupes = current.tally.select { |_, count| count > 1 }.keys
      abort "spec:fast executes #{dupes.size} example IDs twice: #{dupes.first(20)}" unless dupes.empty?

      puts "spec:fast example selection OK — #{current.size} examples"
    end
  end
end
