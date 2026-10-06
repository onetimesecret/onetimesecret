# spec/unit/lanes/image_log_defaults_guard_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'open3'

# Static guard: the lane runner's log capture and quieting stay on the test
# side of the tree (#4683).
#
# `tests/lanes/run --capture-logs` / `--quiet` work by exporting LANES_*
# variables that spec/logging.test.yaml turns into a `destinations` block,
# plus LOG_LEVEL / DEBUG_LOGGERS floors. None of that changes a deployed
# process as long as (a) nothing copied into the image reads a LANES_*
# variable or names the test logging config, and (b) nothing that builds or
# configures the image sets RACK_ENV=test or those floors. Nothing would
# fail if either stopped being true: a container would start, just without
# its console log. This scans the tracked files for both.
#
# Two file sets, both from `git ls-files` (a developer's untracked
# etc/logging.yaml or .env is not what ships):
#
#   runtime files - the Dockerfile's own COPY sources that hold code or
#                   config a Ruby or shell process reads at run time;
#   image config  - the Dockerfiles, docker/, the deployment compose files,
#                   the s6 services and entrypoints, and the env examples.
#
# The runtime set is derived from the Dockerfile, so a new COPY source has
# to be classified here before this passes again.
#
# What it does not cover: compose.test.yml and compose.e2e.yml (test
# services, not the app image), and frontend sources.
RSpec.describe 'OCI image log defaults guard' do
  repo_root = File.expand_path('../../..', __dir__)

  # COPY sources scanned as runtime files.
  runtime_sources = %w[
    apps bin config.ru etc lib migrations
    docker/entrypoints/entrypoint.sh docker/entrypoints/healthcheck.sh docker/s6/services
    tools/setup/lib.sh tools/setup/setup.sh
  ].freeze

  # COPY sources not scanned: build manifests and frontend sources, which no
  # Ruby process reads its logging settings from.
  unscanned_sources = %w[
    .ruby-version Gemfile Gemfile.lock package.json pnpm-lock.yaml pnpm-workspace.yaml
    eslint.config.ts tsconfig.json vite.config.ts locales public src
  ].freeze

  # Test-side directories. `COPY apps` brings apps/*/spec and apps/*/try
  # along; those are test files and may name the runner's variables.
  test_side = %r{\A(?:spec|tests|try)/|\Aapps/.+/(?:spec|try)/}

  image_config_paths = %w[
    Dockerfile docker docker-compose.yml .env.example .env.reference etc/examples
  ].freeze

  # LANES_* names a runtime file may mention, by file. setup.sh reads
  # LANES_NO_AUTOSTART in its `--test` mode to leave test services to the
  # caller; it has no bearing on logging.
  #
  # lib/tasks/spec.rake requires the runner's rspec formatter support. Only
  # the Rakefile loads lib/tasks, and the Dockerfile copies neither the
  # Rakefile nor tests/ (pinned below).
  lanes_allowlist = {
    'tools/setup/setup.sh' => %w[LANES_NO_AUTOSTART],
    'lib/tasks/spec.rake' => %w[tests/lanes/support],
  }.freeze

  runtime_rules = {
    'reads a lane runner variable' => /LANES_[A-Z0-9_]+/,
    'names the test logging config' => /logging\.test\b/,
    'loads lane runner support code' => %r{tests/lanes/support},
  }.freeze

  image_config_rules = {
    'reads a lane runner variable' => /LANES_[A-Z0-9_]+/,
    'names the test logging config' => /logging\.test\b/,
    'invokes the lane runner' => %r{tests/lanes/run|--capture-logs},
    'sets RACK_ENV to test' => /\bRACK_ENV\s*[=:]\s*["']?(?:\$\{RACK_ENV:-)?test\b/,
    'sets a log level floor of error or fatal' => /\b(?:DEFAULT_)?LOG_LEVEL\s*[=:]\s*["']?(?:\$\{\w+:-)?(?:error|fatal)\b/i,
    'sets DEBUG_LOGGERS' => /\bDEBUG_LOGGERS\s*[=:]\s*["']?(?:\$\{\w+:-)?[A-Za-z]/,
  }.freeze

  define_method(:repo_root) { repo_root }

  def tracked(*paths)
    out, status = Open3.capture2('git', '-C', repo_root, 'ls-files', '-z', '--', *paths)
    raise "git ls-files failed for #{paths.inspect}" unless status.success?

    out.split("\0")
  end

  # A full-line `#` comment is prose, except in YAML: the logging configs are
  # rendered through ERB first, and ERB runs a tag inside a YAML comment.
  def code_lines(path, text)
    yaml = path.end_with?('.yaml', '.yml') && path.start_with?('etc/')
    text.each_line.with_index(1).reject { |line, _| !yaml && line.match?(/\A\s*#/) }
  end

  # @return [Array<String>] one "path:line: what (text)" entry per offence
  def offences(files, rules, allow: {})
    files.flat_map do |path|
      full = File.join(repo_root, path)
      next [] unless File.file?(full)

      text = File.binread(full)
      next [] if text.include?("\0")

      text = text.force_encoding('UTF-8').scrub
      code_lines(path, text).flat_map do |line, number|
        rules.filter_map do |what, pattern|
          # No rule has a capture group, so scan returns the matched text.
          hits = line.scan(pattern) - allow.fetch(path, [])
          next if hits.empty?

          "#{path}:#{number}: #{what} (#{line.strip[0, 120]})"
        end
      end
    end
  end

  def dockerfile_copy_sources
    text = File.read(File.join(repo_root, 'Dockerfile')).gsub(/\\\n/, ' ')
    text.each_line.grep(/\A\s*(?:COPY|ADD)\s/).reject { |line| line.include?('--from=') }.flat_map do |line|
      line.split.drop(1).reject { |token| token.start_with?('--') }[0..-2]
    end.map { |source| source.chomp('/') }.uniq.sort
  end

  let(:runtime_files) { tracked(*runtime_sources).grep_v(test_side).grep_v(/\.md\z/) }
  let(:image_config_files) { tracked(*image_config_paths).grep_v(/\.md\z/) }

  describe 'the scanned file sets' do
    it 'cover every source the Dockerfile copies from the build context' do
      sources = dockerfile_copy_sources

      expect(sources).to include('lib', 'etc', 'apps', 'bin')
      expect(sources - runtime_sources - unscanned_sources)
        .to be_empty, "Dockerfile COPY sources this guard has not classified: #{(sources - runtime_sources - unscanned_sources).inspect}"
    end

    it 'copy no test-side directory into the image' do
      copied = dockerfile_copy_sources.select { |source| "#{source}/".match?(test_side) }

      expect(copied).to be_empty, "Dockerfile copies a test-side directory: #{copied.inspect}"
    end

    # lib/tasks/spec.rake (copied with lib) requires tests/lanes/support, and
    # is loaded only by the Rakefile.
    it 'do not copy the Rakefile, the only loader of lib/tasks' do
      loaders = tracked('lib/onetime', 'lib/onetime.rb', 'bin', 'config.ru', 'apps').grep_v(test_side).select do |path|
        full = File.join(repo_root, path)
        File.file?(full) && File.binread(full).match?(%r{lib/tasks|tasks/\*\*/\*\.rake})
      end

      expect(dockerfile_copy_sources).not_to include('Rakefile')
      expect(loaders).to be_empty, "Runtime files that load lib/tasks: #{loaders.inspect}"
    end

    it 'are not empty and include the files the guard exists for' do
      expect(runtime_files.size).to be > 100
      expect(runtime_files).to include(
        'lib/onetime/initializers/setup_loggers.rb',
        'lib/onetime/utils/config_resolver.rb',
        'etc/defaults/logging.defaults.yaml',
        'docker/entrypoints/entrypoint.sh',
        'config.ru',
      )
      expect(runtime_files.grep(%r{\Adocker/s6/services/})).not_to be_empty
      expect(runtime_files.grep(test_side)).to be_empty

      expect(image_config_files).to include(
        'Dockerfile', 'docker/base.dockerfile', 'docker-compose.yml', '.env.example', '.env.reference',
        'docker/compose/docker-compose.simple.yml', 'docker/compose/docker-compose.full.yml'
      )
      expect(image_config_files.grep(%r{\Adocker/variants/.+\.dockerfile\z})).not_to be_empty
    end
  end

  # The scanner has to be able to find what it looks for.
  describe 'the scanner' do
    it 'reports the test logging config, which does read the capture variables, by file and line' do
      found = offences(['spec/logging.test.yaml'], runtime_rules)

      expect(found.grep(/\Aspec\/logging\.test\.yaml:\d+: reads a lane runner variable .*LANES_APP_LOG_FILE/)).not_to be_empty
      expect(found.grep(/LANES_APP_LOG_CONSOLE/)).not_to be_empty
    end

    it 'reports the lane runner itself' do
      expect(offences(['tests/lanes/run'], runtime_rules).size).to be > 5
    end

    it 'reports the spec helper, which loads the capture support code' do
      found = offences(['spec/spec_helper.rb'], runtime_rules)

      expect(found.grep(/\Aspec\/spec_helper\.rb:\d+: loads lane runner support code/)).not_to be_empty
    end

    it 'drops an allowlisted name and keeps any other on the same file' do
      rules = { 'reads a lane runner variable' => /LANES_[A-Z0-9_]+/ }

      expect(offences(['tests/lanes/run'], rules, allow: { 'tests/lanes/run' => %w[LANES_NO_AUTOSTART] }).join)
        .to include('LANES_APP_LOG_FILE')
      expect(offences(['tools/setup/setup.sh'], rules)).not_to be_empty
      expect(offences(['tools/setup/setup.sh'], rules, allow: lanes_allowlist)).to be_empty
    end

    it 'matches each image config rule against a line that breaks it, and not its comment' do
      breaking = {
        'reads a lane runner variable' => 'ENV LANES_APP_LOG_CONSOLE=off',
        'names the test logging config' => 'COPY spec/logging.test.yaml ./etc/logging.yaml',
        'invokes the lane runner' => 'RUN tests/lanes/run unit --capture-logs',
        'sets RACK_ENV to test' => '      - RACK_ENV=${RACK_ENV:-test}',
        'sets a log level floor of error or fatal' => 'ENV LOG_LEVEL=fatal',
        'sets DEBUG_LOGGERS' => 'DEBUG_LOGGERS="App:error,Auth:error"',
      }

      expect(breaking.keys).to match_array(image_config_rules.keys)
      breaking.each do |what, line|
        expect(line).to match(image_config_rules.fetch(what)), what
        expect(code_lines('Dockerfile', "# #{line}\n").to_a).to be_empty
      end

      ['ENV RACK_ENV=production \\', '      - RACK_ENV=${RACK_ENV:-production}', 'DEFAULT_LOG_LEVEL=info', 'LOG_LEVEL=', 'DEBUG_LOGGERS='].each do |line|
        expect(image_config_rules.values.grep(->(pattern) { line.match?(pattern) })).to be_empty, line
      end
    end

    it 'scans YAML comment lines under etc/, where an ERB tag still runs' do
      expect(code_lines('etc/defaults/logging.defaults.yaml', "# <%= ENV['LANES_APP_LOG_FILE'] %>\n").to_a.size).to eq(1)
    end

    it 'still needs each allowlist entry' do
      lanes_allowlist.each do |path, names|
        text = File.read(File.join(repo_root, path))
        names.each { |name| expect(text).to include(name), "#{path} no longer mentions #{name}; drop it from the allowlist" }
      end
    end
  end

  describe 'files copied into the image' do
    it 'read no lane runner variable and do not name the test logging config' do
      found = offences(runtime_files, runtime_rules, allow: lanes_allowlist)

      expect(found).to be_empty, "Test-run log settings reachable from the image:\n  #{found.join("\n  ")}"
    end

    # ConfigResolver looks for apps/**/spec/{name}.test.yaml after
    # spec/{name}.test.yaml, and `COPY apps` would carry such a file.
    it 'include no logging.test.yaml under apps/' do
      found = tracked('apps').grep(%r{/logging\.test\.yaml\z})

      expect(found).to be_empty, "Test logging config inside a copied directory: #{found.inspect}"
    end
  end

  describe 'files that build or configure the image' do
    it 'set nothing that turns on the capture profile or the quiet floors' do
      found = offences(image_config_files, image_config_rules)

      expect(found).to be_empty, "Test-run log settings in image configuration:\n  #{found.join("\n  ")}"
    end

    it 'set RACK_ENV to production wherever a Dockerfile sets it' do
      dockerfiles = image_config_files.grep(/(?:\ADockerfile|\.dockerfile)\z/)
      assignments = dockerfiles.flat_map do |path|
        File.readlines(File.join(repo_root, path)).each_with_index.filter_map do |line, index|
          next if line.match?(/\A\s*#/)

          value = line[/\bRACK_ENV=(\S+)/, 1]
          ["#{path}:#{index + 1}", value] if value
        end
      end

      expect(assignments).not_to be_empty
      expect(assignments.reject { |_, value| value == 'production' })
        .to be_empty, "RACK_ENV is not production at: #{assignments.reject { |_, value| value == 'production' }.inspect}"
    end
  end

  describe 'the shipped logging defaults' do
    def rendered_defaults
      path = File.join(repo_root, 'etc', 'defaults', 'logging.defaults.yaml')
      YAML.safe_load(ERB.new(File.read(path)).result, permitted_classes: [Symbol, Date, Time], aliases: true)
    end

    around do |example|
      saved = ENV.to_h
      example.run
    ensure
      ENV.replace(saved)
    end

    it 'render the same destinations whatever the capture variables say' do
      %w[LANES_APP_LOG_CONSOLE LANES_APP_LOG_FILE LANES_MAIL_LOG_FILE].each { |name| ENV.delete(name) }
      unset = rendered_defaults.fetch('destinations')

      ENV['LANES_APP_LOG_CONSOLE'] = 'off'
      ENV['LANES_APP_LOG_FILE']    = '/nonexistent/captured.log'

      expect(rendered_defaults.fetch('destinations')).to eq(unset)
      expect(unset.fetch('console')).to include('enabled' => true, 'level' => nil)
      expect(unset.fetch('file')).to include('enabled' => false, 'path' => nil)
    end
  end
end
