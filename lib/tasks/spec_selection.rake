# lib/tasks/spec_selection.rake
#
# frozen_string_literal: true

# spec:fast selection-equivalence guard
# =====================================
#
# spec:fast used to be 13 rspec processes: spec:unit, spec:cli, and one per
# apps/*/*/spec tree. It is now three (spec:root_fast, spec:apps_fast, and
# spec:apps_config_ru) plus the two billing lanes' one each (spec:billing,
# which took the billing trees out of spec:fast, and spec:integration:billing,
# which runs the billing app's mode-less integration files), and the whole
# value of that consolidation rests on those invocations selecting, between
# them, exactly the files the 13 selected — each file once. That equivalence
# is NOT something a reviewer can check by reading the globs: rspec resolves
# --pattern and --exclude-pattern separately against each checked path, so an
# include and an exclude that look symmetric can behave asymmetrically (see
# the HARD RULE in lib/tasks/spec.rake). This file mechanises the check.
#
#   rake spec:verify_selection        file-level, <1s, loads zero spec files
#   rake spec:verify_selection:deep   example-ID level, ~35s, 20 rspec dry-runs
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
  # An invocation given directories instead of a pattern (spec:billing) is
  # modelled with those directories as the checked paths and rspec's default
  # pattern, which is what `rspec <dir>...` does.
  #
  # @param pattern [String, nil] rspec --pattern value (comma-separated globs)
  # @param exclude_pattern [String, nil] rspec --exclude-pattern value
  # @param paths [Array<String>, nil] directories on the command line
  # @return [Array<String>] repo-relative spec file paths, sorted and unique
  def files(pattern: nil, exclude_pattern: nil, paths: nil)
    cfg                             = RSpec::Core::Configuration.new
    cfg.pattern                     = pattern if pattern
    cfg.exclude_pattern             = exclude_pattern if exclude_pattern
    cfg.files_or_directories_to_run = paths || cfg.default_path
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

  # The legs spec:fast runs are FAST_LEGS (lib/tasks/spec.rake); this guard
  # models a selection for each of them. The names cannot be derived — each
  # descriptor's pattern is handwritten — so agreement is asserted instead:
  # a leg added to FAST_LEGS without a descriptor here would run unverified,
  # and every check below would silently under-count what spec:fast covers.
  def assert_legs_modeled!
    modeled = fast_invocations.map { |inv| "spec:#{inv[:name]}" }
    return if modeled == FAST_LEGS

    abort <<~MSG
      spec:verify_selection models the legs #{modeled.inspect}
      but spec:fast runs FAST_LEGS #{FAST_LEGS.inspect}
      (lib/tasks/spec.rake). Add a descriptor to SpecSelection.fast_invocations
      for the new leg — or remove the stale one — in the same commit, so the
      selection guard covers exactly what the lane runs.
    MSG
  end

  # The invocations spec:fast spawns today. Patterns come from the constants
  # the rake tasks themselves use, so the guard can never verify a pattern the
  # lane does not run. Names must mirror FAST_LEGS — see assert_legs_modeled!.
  #
  # @return [Array<Hash>] invocation descriptors
  def fast_invocations
    [
      { name: 'root_fast', pattern: ROOT_FAST_PATTERN, exclude_pattern: ROOT_FAST_EXCLUDE },
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

  # The billing lane's invocation (spec:billing), from the constants the task
  # uses. Together with fast_invocations it must select what the legacy
  # fan-out selected: the billing trees moved, they did not stop running.
  #
  # @return [Hash] invocation descriptor
  def billing_invocation
    { name: 'billing', paths: BILLING_SPEC_PATHS, exclude_pattern: BILLING_SPEC_EXCLUDE }
  end

  # The billing-integration lane's invocation (spec:integration:billing): the
  # files the task passes, expanded from the same pattern at load.
  #
  # @return [Hash] invocation descriptor
  def billing_integration_invocation
    { name: 'billing_integration', paths: BILLING_INTEGRATION_SPEC_FILES }
  end

  # Files the lanes pick up that NO legacy invocation ever claimed.
  #
  # spec/lib/onetime/jobs/workers/*_spec.rb arrived with #3810 and were run by
  # no lane at all — not spec:fast, not an integration lane, not spec:api. They
  # are adopted by root_fast. The mode-less files directly under
  # apps/web/billing/spec/integration/ were never dispatched either: the
  # legacy per-app invocation excluded the whole integration/ subtree and
  # every integration task reads integration/<mode>. The billing-integration
  # lane adopts them. Stating each adoption as a pattern rather than a file
  # list means another file in either place is covered automatically, while
  # a lane that stops selecting them still fails the guard loudly.
  ADOPTED_PATTERNS = %w[
    spec/lib/**/*_spec.rb
    apps/web/billing/spec/integration/*_spec.rb
  ].freeze

  # @return [Array<String>] every adopted file, sorted and unique
  def adopted_files
    ADOPTED_PATTERNS.flat_map { |pattern| files(pattern: pattern) }.sort.uniq
  end

  # Spec files that are knowingly run by NO lane. Every entry is drift being
  # tolerated, not a category — the list is printed on every successful run so
  # it cannot quietly become permanent, and a new orphan fails the task. Empty
  # since the billing-integration lane adopted the three mode-less billing
  # integration files; it stays so that the next tolerated orphan has a named
  # place.
  UNRUN_SPECS = %w[].freeze

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
    integration += Dir.glob('apps/*/*/spec/integration/full_saml_platform/**/*_spec.rb')

    {
      'spec:fast' => fast_invocations.flat_map { |inv| files(**inv.except(:name, :tags)) }.sort.uniq,
      'spec:billing' => files(**billing_invocation.except(:name)),
      'spec:integration:billing' => files(**billing_integration_invocation.except(:name)),
      'spec:integration' => integration.sort.uniq,
      'spec:api' => Dir.glob('spec/api/**/*_spec.rb').sort.uniq,
    }
  end

  # Assemble the command line for one invocation descriptor. Mirrors
  # RSpec::Core::RakeTask#spec_command's flag order closely enough that the
  # dry-run exercises the same rspec argument parsing the lane does; a
  # descriptor with paths mirrors spec:billing's `sh` instead.
  #
  # @param inv [Hash] invocation descriptor
  # @param out [String] path for the JSON formatter
  # @return [String] shell command
  def dry_run_command(inv, out)
    parts = ['bundle exec rspec']
    parts << (inv[:paths] ? inv[:paths].join(' ') : "--pattern '#{inv[:pattern]}'")
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
  desc 'Verify spec:fast + the two billing lanes select exactly what the legacy 13-invocation fan-out did'
  task :verify_selection do
    SpecSelection.assert_legs_modeled!

    legacy              = SpecSelection.legacy_invocations
      .flat_map { |inv| SpecSelection.files(**inv.except(:name, :tags)) }
      .sort.uniq
    claims              = SpecSelection.lane_claims
    fast                = claims.fetch('spec:fast')
    billing             = claims.fetch('spec:billing')
    billing_integration = claims.fetch('spec:integration:billing')
    current             = (fast + billing + billing_integration).sort.uniq
    adopted             = SpecSelection.adopted_files

    dropped           = legacy - current
    added             = (current - legacy) - adopted
    missing_adoptions = adopted - current

    unless dropped.empty? && added.empty? && missing_adoptions.empty?
      abort <<~MSG
        spec:fast + spec:billing + spec:integration:billing selection drift —
        the three lanes' invocations no longer select, between them, what the
        legacy per-tree invocations select.

          dropped (legacy ran these, no lane does now):
        #{dropped.empty? ? '    (none)' : dropped.map { |f| "    #{f}" }.join("\n")}

          added (a lane runs these, no legacy invocation did, and they are
          not covered by the documented adoptions #{SpecSelection::ADOPTED_PATTERNS.join(', ')}):
        #{added.empty? ? '    (none)' : added.map { |f| "    #{f}" }.join("\n")}

          adopted but no longer selected (ROOT_FAST_PATTERN lost spec/lib, or
          BILLING_INTEGRATION_SPEC_PATTERN lost the mode-less billing files?):
        #{missing_adoptions.empty? ? '    (none)' : missing_adoptions.map { |f| "    #{f}" }.join("\n")}

        Fix the patterns in lib/tasks/spec.rake, or — if the change is
        deliberate — update this guard in the same commit.
      MSG
    end

    # Each billing lane exists to run its trees, so an empty claim is a broken
    # constant, not a lane with nothing to do. (A billing file that another
    # lane also selects is caught by the overlap check below.)
    abort 'spec:billing selects no files: check BILLING_SPEC_PATHS in lib/tasks/spec.rake' if billing.empty?
    if billing_integration.empty?
      abort 'spec:integration:billing selects no files: check BILLING_INTEGRATION_SPEC_PATTERN in lib/tasks/spec.rake'
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
      'spec:fast selection OK — %d files, %d billing, %d billing integration (%d adopted among them), ' \
      '%d integration, %d api, %d total',
      fast.size,
      billing.size,
      billing_integration.size,
      adopted.size,
      claims.fetch('spec:integration').size,
      claims.fetch('spec:api').size,
      all.size,
    )
  end

  namespace :verify_selection do
    desc 'Verify spec:fast + the two billing lanes run the same EXAMPLE IDs as the legacy fan-out (slow: 20 dry-runs)'
    task :deep do
      require 'json'

      SpecSelection.assert_legs_modeled!

      outdir = 'tmp/spec_selection'
      mkdir_p outdir

      collect = ->(invocations, label) do
        invocations.flat_map do |inv|
          out = File.join(outdir, "#{label}_#{inv[:name]}.json")
          sh SpecSelection::DRY_RUN_ENV, SpecSelection.dry_run_command(inv, out)
          JSON.parse(File.read(out)).fetch('examples').map { |ex| ex.fetch('id') }
        end
      end

      # The legacy fan-out never ran the adopted files (see ADOPTED_PATTERNS),
      # so the oracle gets one more invocation per adoption. Without them the
      # diff reports the adoptions as drift on every run and the guard
      # becomes noise.
      adoptions = SpecSelection::ADOPTED_PATTERNS.each_with_index.map do |pattern, i|
        { name: "adopted_#{i}", pattern: pattern }
      end
      legacy    = collect.call(SpecSelection.legacy_invocations + adoptions, 'legacy')
      # All three lanes on the current side: the billing trees moved out of
      # spec:fast, so spec:fast alone would report them as missing.
      current   = collect.call(
        SpecSelection.fast_invocations + [SpecSelection.billing_invocation, SpecSelection.billing_integration_invocation],
        'fast',
      )

      missing = legacy - current
      extra   = current - legacy

      puts format(
        'legacy=%d (uniq %d)  spec:fast+spec:billing+spec:integration:billing=%d (uniq %d)  missing=%d  extra=%d',
        legacy.size,
        legacy.uniq.size,
        current.size,
        current.uniq.size,
        missing.size,
        extra.size,
      )

      unless missing.empty? && extra.empty?
        abort <<~MSG
          spec:fast + spec:billing example drift.

            missing (legacy executed, neither lane does) — first 20 of #{missing.size}:
          #{missing.first(20).map { |id| "    #{id}" }.join("\n")}

            extra (a lane executes, legacy did not) — first 20 of #{extra.size}:
          #{extra.first(20).map { |id| "    #{id}" }.join("\n")}
        MSG
      end

      # Duplicate IDs across invocations mean a file is loaded twice, which is
      # the file-level overlap check restated at example granularity — it also
      # catches a shared-example host pulled in by two patterns, or a billing
      # file both lanes load.
      dupes = current.tally.select { |_, count| count > 1 }.keys
      abort "the lanes execute #{dupes.size} example IDs twice: #{dupes.first(20)}" unless dupes.empty?

      puts "spec:fast + spec:billing example selection OK — #{current.size} examples"
    end
  end
end
