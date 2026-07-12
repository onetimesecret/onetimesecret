# spec/unit/setup/doctor_bundle_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'socket'
require 'tmpdir'

# Golden-file test for the support-bundle format (install-onboarding C9,
# problem-space R0.2). The bundle is the artifact operators attach to bug
# reports, so its shape is a contract:
#
#   - the entry list is FIXED — fixtures/bundle_manifest.golden is the
#     single source of truth; `cmd_bundle` in bin/setup writes the same
#     list into manifest.txt. Extend all three together.
#   - env-names.txt must never contain values (names only) — that is the
#     sanitization promise the doctor output makes.
#
# This shells out to the real `bin/setup --doctor --bundle` (the doctor runs
# its probes against whatever this machine has; probe outcomes don't matter
# here, only the bundle format).
RSpec.describe 'bin/setup --doctor --bundle' do
  def repo_root
    File.expand_path('../../..', __dir__)
  end

  def golden_entries
    File.readlines(
      File.join(__dir__, 'fixtures', 'bundle_manifest.golden'), chomp: true
    ).reject(&:empty?)
  end

  def generate_bundle(bundle_dir)
    env = { 'OTS_BUNDLE_DIR' => bundle_dir }
    # Doctor failures (services down on this machine) must not block bundle
    # creation — that is the point of a diagnostic bundle. Ignore exit status.
    Open3.capture2e(env, File.join(repo_root, 'bin', 'setup'), '--doctor', '--bundle', chdir: repo_root)
    archives = Dir[File.join(bundle_dir, 'ots-doctor-bundle-*.tar.gz')]
    expect(archives.size).to eq(1), "expected exactly one bundle archive, got: #{archives.inspect}"
    archives.first
  end

  it 'produces an archive matching the golden entry list, with no env values leaked' do
    Dir.mktmpdir('ots-bundle-spec') do |bundle_dir|
      archive = generate_bundle(bundle_dir)

      listing, status = Open3.capture2('tar', '-tzf', archive)
      expect(status).to be_success

      entries   = listing.split("\n").map { |path| File.basename(path) }
      root_dirs = listing.split("\n").map { |path| path.split('/').first }.uniq
      expect(root_dirs.size).to eq(1) # everything under one bundle dir

      files = entries.reject { |name| name.start_with?('ots-doctor-bundle-') }.sort
      expect(files).to eq(golden_entries)

      Dir.mktmpdir('ots-bundle-extract') do |extract_dir|
        system('tar', '-xzf', archive, '-C', extract_dir, exception: true)
        bundle_root = Dir[File.join(extract_dir, 'ots-doctor-bundle-*')].first

        manifest = File.readlines(File.join(bundle_root, 'manifest.txt'), chomp: true)
                       .reject { |line| line.start_with?('#') || line.empty? }
        expect(manifest.sort).to eq(golden_entries)

        env_names = File.read(File.join(bundle_root, 'env-names.txt'))
        expect(env_names).not_to include('='), 'env-names.txt must contain variable names only, never values'

        # Guard against hostnames short enough to appear inside ordinary
        # words ("mac" in "macOS") — the leak check only makes sense for
        # distinctive hostnames.
        hostname = Socket.gethostname
        if hostname.length >= 6
          system_txt = File.read(File.join(bundle_root, 'system.txt'))
          expect(system_txt).not_to include(hostname), 'system.txt must not leak the hostname'
        end
      end
    end
  end
end
