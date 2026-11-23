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
#     single source of truth; `cmd_bundle` in tools/setup/setup.sh writes the same
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

  it 'produces a restricted archive matching the golden list, without logs' do
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
        expect(entries).not_to include('logs.txt')
        expect(File.stat(archive).mode & 0o077).to eq(0), 'bundle must be readable only by its owner'

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

  it 'writes the default bundle beneath a private directory in tmp' do
    output_dir = File.join(repo_root, 'tmp', 'ots-doctor-bundles')
    created_dir = !Dir.exist?(output_dir)
    before = Dir[File.join(output_dir, 'ots-doctor-bundle-*.tar.gz')]
    new_archives = []
    begin
      output, status = Open3.capture2e({ 'OTS_BUNDLE_DIR' => nil },
                                       File.join(repo_root, 'bin', 'setup'),
                                       '--doctor', '--bundle', chdir: repo_root)
      new_archives = Dir[File.join(output_dir, 'ots-doctor-bundle-*.tar.gz')] - before
      expect(status).to be_success, output
      expect(new_archives.size).to eq(1)
      expect(File.stat(output_dir).mode & 0o077).to eq(0)
      expect(File.stat(new_archives.first).mode & 0o077).to eq(0)
    ensure
      new_archives.each { |archive| File.delete(archive) }
      Dir.rmdir(output_dir) if created_dir && Dir.exist?(output_dir) && Dir.empty?(output_dir)
    end
  end

  it 'refuses a planted regular-file archive symlink without writing to its target' do
    Dir.mktmpdir('ots-bundle-symlink') do |scratch|
      output_dir = File.join(scratch, 'shared')
      shim_dir = File.join(scratch, 'bin')
      Dir.mkdir(output_dir)
      File.chmod(0o700, output_dir)
      Dir.mkdir(shim_dir)
      target = File.join(scratch, 'target')
      File.write(target, 'unchanged')

      # The shim plants the link as soon as cmd_bundle creates its random
      # work directory, before the doctor probes and archive creation.
      File.write(File.join(shim_dir, 'mktemp'), <<~'SH')
        #!/usr/bin/env bash
        result=$("$OTS_TEST_REAL_MKTEMP" "$@") || exit $?
        ln -s "$OTS_TEST_TARGET" "$result.tar.gz"
        printf '%s\n' "$result"
      SH
      File.chmod(0o700, File.join(shim_dir, 'mktemp'))
      real_mktemp = ENV.fetch('PATH').split(File::PATH_SEPARATOR)
                        .map { |dir| File.join(dir, 'mktemp') }
                        .find { |path| File.executable?(path) }
      expect(real_mktemp).not_to be_nil

      env = {
        'OTS_BUNDLE_DIR' => output_dir,
        'OTS_TEST_REAL_MKTEMP' => real_mktemp,
        'OTS_TEST_TARGET' => target,
        'PATH' => "#{shim_dir}:#{ENV.fetch('PATH')}",
      }
      output, status = Open3.capture2e(env, File.join(repo_root, 'bin', 'setup'),
                                       '--doctor', '--bundle', chdir: repo_root)
      expect(status).not_to be_success
      expect(output).to include('Could not write bundle archive safely')
      expect(File.read(target)).to eq('unchanged')
      planted_links = Dir[File.join(output_dir, 'ots-doctor-bundle-*.tar.gz')]
      expect(planted_links.size).to eq(1)
      expect(File.symlink?(planted_links.first)).to be(true)
      expect(File.readlink(planted_links.first)).to eq(target)
    end
  end

  it 'removes an archive when tar fails after writing partial output' do
    Dir.mktmpdir('ots-bundle-tar-failure') do |scratch|
      output_dir = File.join(scratch, 'out')
      shim_dir = File.join(scratch, 'bin')
      Dir.mkdir(output_dir)
      File.chmod(0o700, output_dir)
      Dir.mkdir(shim_dir)
      File.write(File.join(shim_dir, 'tar'), <<~'SH')
        #!/usr/bin/env bash
        printf 'partial archive'
        exit 2
      SH
      File.chmod(0o700, File.join(shim_dir, 'tar'))

      env = { 'OTS_BUNDLE_DIR' => output_dir, 'PATH' => "#{shim_dir}:#{ENV.fetch('PATH')}" }
      output, status = Open3.capture2e(env, File.join(repo_root, 'bin', 'setup'),
                                       '--doctor', '--bundle', chdir: repo_root)
      expect(status).not_to be_success
      expect(output).to include('Could not write bundle archive safely')
      expect(Dir.children(output_dir)).to be_empty
    end
  end

  { 'readable' => 0o755, 'non-sticky shared' => 0o777, 'sticky shared' => 0o1777 }.each do |label, mode|
    it "refuses a #{label} output directory" do
      Dir.mktmpdir('ots-bundle-shared') do |scratch|
        output_dir = File.join(scratch, 'shared')
        Dir.mkdir(output_dir)
        File.chmod(mode, output_dir)

        # A special-file symlink in a sticky directory must never reach tar.
        if mode == 0o1777
          fifo = File.join(scratch, 'fifo')
          system('mkfifo', fifo, exception: true)
          File.symlink(fifo, File.join(output_dir, 'planted.tar.gz'))
        end

        original_entries = Dir.children(output_dir)
        output, status = Open3.capture2e({ 'OTS_BUNDLE_DIR' => output_dir },
                                         File.join(repo_root, 'bin', 'setup'),
                                         '--doctor', '--bundle', chdir: repo_root)
        expect(status).not_to be_success
        expect(output).to include('must be owned by this user and private (mode 0700)')
        expect(Dir.children(output_dir)).to eq(original_entries)
      end
    end
  end

  { 'output directory' => :output, 'ancestor directory' => :ancestor }.each do |label, location|
    it "refuses a macOS ACL grant on the #{label}" do
      skip 'macOS ACL regression' unless RUBY_PLATFORM.include?('darwin')

      Dir.mktmpdir('ots-bundle-acl') do |scratch|
        output_dir = File.join(scratch, 'out')
        Dir.mkdir(output_dir)
        File.chmod(0o700, output_dir)
        acl_dir = location == :output ? output_dir : scratch
        begin
          system('chmod', '+a', 'everyone allow add_file,delete_child', acl_dir, exception: true)
          expect(File.stat(acl_dir).mode & 0o777).to eq(0o700)

          output, status = Open3.capture2e({ 'OTS_BUNDLE_DIR' => output_dir },
                                           File.join(repo_root, 'bin', 'setup'),
                                           '--doctor', '--bundle', chdir: repo_root)
          expect(status).not_to be_success
          expect(output).to include('directory with an ACL')
          expect(Dir.children(output_dir)).to be_empty
        ensure
          system('chmod', '-N', acl_dir, exception: true)
        end
      end
    end
  end
end
