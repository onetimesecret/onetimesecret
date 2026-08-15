# spec/unit/lanes/datastore_claim_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'tmpdir'
require 'fileutils'

# Regression harness for the per-worktree datastore index in tests/lanes/run
# (#4168).
#
# The index starts as a checksum of the repo root, which maps many paths onto
# 1023 slots — so two worktrees CAN derive the same one, and a collision that
# goes unnoticed reproduces exactly the cross-run fixture contamination the
# whole feature exists to prevent. The claim registry is what makes a
# collision loud, and its failure mode is silence, so it needs a test that
# fails rather than a comment that explains.
#
# Method matches hermetic_boundary_spec.rb: run the real `tests/lanes/run
# selftest` and read LANES_DATASTORE_DB out of the environment the task
# process actually received. The registry lives under `${HOME}/.cache`, and
# HOME is keep-listed, so pointing it at a tmpdir gives each example its own
# registry without touching the developer's.
module LaneClaimProbe
  ROOT     = File.expand_path('../../..', __dir__)
  REGISTRY = File.join('.cache', 'onetime-lanes', 'db')

  module_function

  # The floor the runner enforces, read from the same pin file it reads.
  def bash_floor
    @bash_floor ||= Integer(File.read(File.join(ROOT, '.bash-version')).strip)
  end

  # A PATH the runner's `#!/usr/bin/env bash` resolves to a bash that meets
  # the floor. That shebang picks the FIRST bash on PATH, which on macOS is
  # Apple's frozen 3.2 — but bin/setup --test requires a newer one and it is
  # installed elsewhere on disk (brew install bash). So rather than give up
  # when the leading bash is too old, prepend the directory of a qualifying
  # bash. A too-old leading bash is not a reason to skip when a good one is
  # already installed; its total absence is an environment fault the spec
  # should surface, not hide.
  def runner_path
    @runner_path ||= begin
      base = ENV.fetch('PATH')
      dir  = qualifying_bash_dir(base)
      dir ? "#{dir}#{File::PATH_SEPARATOR}#{base}" : base
    end
  end

  # First bash at or above the floor: PATH entries in order (so a modern
  # bash already leading PATH, as on CI, is used as-is), then the standard
  # Homebrew prefixes, which sit outside the default PATH order on macOS.
  def qualifying_bash_dir(base)
    from_path = base.split(File::PATH_SEPARATOR).map { |d| File.join(d, 'bash') }
    candidates = (from_path + ['/opt/homebrew/bin/bash', '/usr/local/bin/bash']).uniq
    found = candidates.find do |bin|
      File.executable?(bin) && (major = bash_major(bin)) && major >= bash_floor
    end
    found && File.dirname(found)
  end

  def bash_major(bin)
    out, status = Open3.capture2e(bin, '-c', 'echo "${BASH_VERSINFO[0]}"')
    status.success? ? Integer(out.strip, exception: false) : nil
  end
end

RSpec.describe 'tests/lanes/run per-worktree datastore claim' do
  # `selftest` runs no application code and blanks the service URLs, so this
  # never needs a container — but LANES_NO_AUTOSTART is set anyway, because
  # a spec that can start containers is a spec that can hang CI.
  def assigned_index(home)
    out, status = Open3.capture2e(
      { 'HOME' => home, 'PATH' => LaneClaimProbe.runner_path, 'LANES_NO_AUTOSTART' => '1' },
      File.join(LaneClaimProbe::ROOT, 'tests', 'lanes', 'run'), 'selftest',
      unsetenv_others: true, chdir: LaneClaimProbe::ROOT
    )
    raise "selftest lane failed:\n#{out}" unless status.success?

    index = out[/^LANES_DATASTORE_DB=(\d+)$/, 1]
    raise "no LANES_DATASTORE_DB in lane environment:\n#{out}" if index.nil?

    Integer(index)
  end

  def claim_path(home, index)
    File.join(home, LaneClaimProbe::REGISTRY, index.to_s)
  end

  def seed_claim(home, index, owner)
    dir = File.join(home, LaneClaimProbe::REGISTRY)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, index.to_s), "#{owner}\n")
  end

  around do |example|
    Dir.mktmpdir('lane-claim-home') { |home| @home = home; example.run }
  end

  attr_reader :home

  it 'records the claim against the repo root that owns it' do
    index = assigned_index(home)

    expect(index).to be_between(1, 1023)
    expect(File.read(claim_path(home, index)).strip).to eq(LaneClaimProbe::ROOT)
  end

  it 'keeps the same index across runs, so a worktree keeps its data' do
    expect(assigned_index(home)).to eq(assigned_index(home))
  end

  # The case the registry exists for. Without it both worktrees would run
  # against one database and contaminate each other silently.
  it 'moves off an index a live checkout already holds' do
    derived = assigned_index(home)
    FileUtils.rm_rf(File.join(home, LaneClaimProbe::REGISTRY))

    Dir.mktmpdir('lane-claim-sibling') do |sibling|
      seed_claim(home, derived, sibling)

      expect(assigned_index(home)).not_to eq(derived)
      # The sibling's claim is left exactly as it was — probing must never
      # rewrite someone else's entry.
      expect(File.read(claim_path(home, derived)).strip).to eq(sibling)
    end
  end

  # Worktrees get deleted, and a registry that only ever accumulated would
  # push later worktrees further from their derived index for no reason.
  it 'reclaims an index whose owning checkout no longer exists' do
    derived = assigned_index(home)
    seed_claim(home, derived, File.join(home, 'worktree-that-was-removed'))

    expect(assigned_index(home)).to eq(derived)
    expect(File.read(claim_path(home, derived)).strip).to eq(LaneClaimProbe::ROOT)
  end
end
