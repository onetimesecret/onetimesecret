# spec/unit/quick_start_datastore_guard_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Static guard: the shipped `docker run` quick starts keep the datastore
# password-protected and off the host network.
#
# The compose stacks were hardened for audit item H-2 (Valkey published on
# 6379 with no password; docker/compose/docker-compose.simple.yml runs
# `--requirepass` and uses `expose:` instead of `ports:`). The README quick
# start, the Dockerfile RUNNING header and the CI job that runs the README
# verbatim describe the same deployment without compose, and a Redis/Valkey
# started with `-p 6379:6379` and no `--requirepass` hands every secret
# identifier, session ID and account record to anyone who can reach the port.
# This scans those blocks so the three cannot drift back.
RSpec.describe 'Docker quick start datastore guard' do
  repo_root = File.expand_path('../..', __dir__)

  quick_start_files = %w[
    README.md
    Dockerfile
    .github/workflows/compose-smoke.yml
  ].freeze

  define_method(:repo_root) { repo_root }

  # Shell commands from a file with `\`-continuations joined, comment and
  # prompt prefixes (the Dockerfile header is `#     $ docker run ...`)
  # stripped, numbered by the line the command starts on.
  #
  # @return [Array<Array(Integer, String)>] [line, command] pairs
  def commands(path)
    text      = File.read(File.join(repo_root, path))
    joined    = []
    continued = false
    text.each_line.with_index(1) do |line, number|
      line = line.sub(/\A\s*#\s*(?:\$\s*)?/, '').sub(/\A\s*\$\s*/, '').rstrip
      if continued
        joined.last[1] << ' ' << line.chomp('\\').strip
      else
        joined << [number, line.chomp('\\').strip]
      end
      continued = line.end_with?('\\')
    end
    joined
  end

  # `docker run` commands whose image is redis or valkey (the app's own
  # `docker run` mentions redis only inside its REDIS_URL value).
  def datastore_runs(path)
    commands(path).select do |_, text|
      text.match?(/\bdocker run\b/) &&
        text.split.any? { |token| token.match?(%r{\A(?:redis|valkey|valkey/valkey)(?::\S+)?\z}) }
    end
  end

  it 'scans the files the guard exists for' do
    quick_start_files.each do |path|
      expect(datastore_runs(path)).not_to be_empty, "#{path}: no `docker run` of a redis/valkey image found"
    end
  end

  it 'does not publish the datastore port on the host' do
    offences = quick_start_files.flat_map do |path|
      datastore_runs(path).select { |_, text| text.match?(/(?:\s-p|--publish)[\s=]\S*6379/) }
        .map { |line, text| "#{path}:#{line}: #{text[0, 120]}" }
    end

    expect(offences).to be_empty, "datastore published on the host:\n#{offences.join("\n")}"
  end

  it 'starts the datastore with --requirepass' do
    offences = quick_start_files.flat_map do |path|
      datastore_runs(path).reject { |_, text| text.include?('--requirepass') }
        .map { |line, text| "#{path}:#{line}: #{text[0, 120]}" }
    end

    expect(offences).to be_empty, "datastore started without --requirepass:\n#{offences.join("\n")}"
  end

  it 'gives the app a datastore URL that carries the password' do
    offences = quick_start_files.flat_map do |path|
      commands(path).flat_map do |line, text|
        # A quoted value may hold a `$(cat ...)` with a space in it.
        text.scan(/(?:REDIS|VALKEY)_URL=(?:"[^"]*"|'[^']*'|\S+)/)
          .grep(%r{redis://})
          .grep_v(%r{redis://[^@/]*@})
          .map { |assignment| "#{path}:#{line}: #{assignment}" }
      end
    end

    expect(offences).to be_empty, "datastore URL without a password:\n#{offences.join("\n")}"
  end
end
