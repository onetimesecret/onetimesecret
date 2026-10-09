# spec/unit/lanes/worker_env_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'open3'

# tests/lanes/support/worker-env: the shim that hands one worker of a lane
# run its environment and execs the command (#4551). It is the single place
# the per-worker derivation happens for the task side — parallel_rspec
# reaches it through PARALLEL_TESTS_EXECUTABLE, the unit lane's tasks file
# calls it by worker number — so what it computes has to agree with what
# tests/lanes/run claimed (owner marker, liveness token, --print-key) for
# the same base index and worker count. The last example here is that
# agreement; the rest pin the shim's own contract.
#
# Every example runs the real shim with a controlled environment and `env`
# (or printf, for the argv rewrite) as the command, so nothing here needs
# a service or a lane.
module LaneWorkerEnvProbe
  module_function

  def repo_root
    File.expand_path('../../..', __dir__)
  end

  def shim
    File.join(repo_root, 'tests', 'lanes', 'support', 'worker-env')
  end

  def runner
    File.join(repo_root, 'tests', 'lanes', 'run')
  end

  def bash_floor
    @bash_floor ||= Integer(File.read(File.join(repo_root, '.bash-version')).strip)
  end

  def path_bash_major
    return @path_bash_major if defined?(@path_bash_major)

    out, status = Open3.capture2e('bash', '-c', 'echo "${BASH_VERSINFO[0]}"')
    @path_bash_major = status.success? ? Integer(out.strip, exception: false) : nil
  end

  # The shim with exactly the given environment (plus PATH, so it can find
  # bash and the command). Merged stdout+stderr and the status.
  def run(k, env, *command)
    Open3.capture2e(
      { 'PATH' => ENV.fetch('PATH') }.merge(env),
      shim, k.to_s, *command, unsetenv_others: true, chdir: repo_root
    )
  end

  # The environment the command received, as a hash.
  def worker_env(k, env)
    output, status = run(k, env, 'env')
    raise "worker-env #{k} failed:\n#{output}" unless status.success?

    output.lines.filter_map do |line|
      line.match(/\A([A-Za-z_][A-Za-z0-9_]*)=(.*)\n?\z/) { |m| [m[1], m[2]] }
    end.to_h
  end

  # The command's argv after the shim's rewrite, one element per line.
  def argv(k, env, *args)
    output, status = run(k, env, 'printf', '%s\n', *args)
    raise "worker-env #{k} failed:\n#{output}" unless status.success?

    output.lines.map(&:chomp)
  end

  def print_key(*args)
    output, status = Open3.capture2e(
      { 'CI' => nil, 'LANES_NO_AUTOSTART' => '1' }, runner, *args, '--print-key', chdir: repo_root
    )
    raise "tests/lanes/run #{args.join(' ')} --print-key failed:\n#{output}" unless status.success?

    output.scan(/(\w+)=(\S*)/).to_h
  end
end

RSpec.describe 'tests/lanes/support/worker-env' do
  let(:probe) { LaneWorkerEnvProbe }
  let(:base_env) do
    {
      'LANES_WORKERS' => '3',
      'LANES_DATASTORE_DB' => '100',
      'REDIS_URL' => 'redis://127.0.0.1:2163/100',
      'VALKEY_URL' => 'valkey://127.0.0.1:2163',
      'LANES_RSPEC_STATUS_FILE' => '/x/y/rspec-status.txt',
    }
  end

  before do
    major = probe.path_bash_major
    floor = probe.bash_floor
    skip "bash #{floor}+ is not on PATH (macOS: brew install bash)" if major.nil? || major < floor
  end

  describe 'the worker index' do
    it 'is the lane index for worker 1 and the ones after it for the rest' do
      expect(probe.worker_env(1, base_env)['LANES_DATASTORE_DB']).to eq('100')
      expect(probe.worker_env(2, base_env)['LANES_DATASTORE_DB']).to eq('101')
      expect(probe.worker_env(3, base_env)['LANES_DATASTORE_DB']).to eq('102')
    end

    it 'wraps inside 1..65535 so no worker lands on 0 or past the last database' do
      env = base_env.merge('LANES_DATASTORE_DB' => '65535')
      expect(probe.worker_env(1, env)['LANES_DATASTORE_DB']).to eq('65535')
      expect(probe.worker_env(2, env)['LANES_DATASTORE_DB']).to eq('1')
      expect(probe.worker_env(3, env)['LANES_DATASTORE_DB']).to eq('2')
    end

    it 'gives CI (base 0) the workers 0..N-1' do
      env = base_env.merge('LANES_DATASTORE_DB' => '0')
      expect((1..3).map { |k| probe.worker_env(k, env)['LANES_DATASTORE_DB'] }).to eq(%w[0 1 2])
    end

    it 'exports LANES_WORKER as the worker number' do
      expect(probe.worker_env(2, base_env)['LANES_WORKER']).to eq('2')
    end
  end

  describe 'auto' do
    # parallel_tests sets TEST_ENV_NUMBER to "1".."N" under --first-is-1;
    # an empty or unset value is worker 1, never an error.
    it 'reads the worker number from TEST_ENV_NUMBER' do
      env = probe.worker_env('auto', base_env.merge('TEST_ENV_NUMBER' => '3'))
      expect(env['LANES_WORKER']).to eq('3')
      expect(env['LANES_DATASTORE_DB']).to eq('102')
    end

    it 'treats an empty or unset TEST_ENV_NUMBER as worker 1' do
      expect(probe.worker_env('auto', base_env.merge('TEST_ENV_NUMBER' => ''))['LANES_WORKER']).to eq('1')
      expect(probe.worker_env('auto', base_env)['LANES_WORKER']).to eq('1')
    end
  end

  describe 'the per-worker environment' do
    it 'rewrites REDIS_URL and VALKEY_URL to the worker index, with or without one already' do
      env = probe.worker_env(2, base_env)
      expect(env['REDIS_URL']).to eq('redis://127.0.0.1:2163/101')
      expect(env['VALKEY_URL']).to eq('valkey://127.0.0.1:2163/101')
    end

    it 'leaves a URL that is not the test valkey alone' do
      # The shim never sees one from the runner; this pins the anchor.
      env = probe.worker_env(2, base_env.merge('REDIS_URL' => 'redis://example.test:6379/0'))
      expect(env['REDIS_URL']).to eq('redis://example.test:6379/0')
    end

    it 'points the rspec status file at a per-worker file beside the lane\'s' do
      expect(probe.worker_env(2, base_env)['LANES_RSPEC_STATUS_FILE']).to eq('/x/y/rspec-status.w2.txt')
      expect(probe.worker_env(1, base_env)['LANES_RSPEC_STATUS_FILE']).to eq('/x/y/rspec-status.w1.txt')
    end

    it 'does not invent a status file when the lane has none' do
      env = probe.worker_env(2, base_env.reject { |k, _| k == 'LANES_RSPEC_STATUS_FILE' })
      expect(env).not_to have_key('LANES_RSPEC_STATUS_FILE')
    end
  end

  describe 'the --out rewrite' do
    it 'suffixes the results path in both argument shapes and touches nothing else' do
      argv = probe.argv(2, base_env, 'spec/x_spec.rb', '--out', 'tmp/results_fast.json',
                        '--out=tmp/other.json', '--format', 'progress')
      expect(argv).to eq(%w[spec/x_spec.rb --out tmp/results_fast_w2.json --out=tmp/other_w2.json --format progress])
    end

    it 'suffixes a path without .json the same way' do
      expect(probe.argv(3, base_env, '--out', 'tmp/results')).to eq(%w[--out tmp/results_w3.json])
    end
  end

  describe 'a serial run (LANES_WORKERS unset or 1)' do
    let(:serial) { base_env.reject { |k, _| k == 'LANES_WORKERS' } }

    it 'passes worker 1 through with only LANES_WORKER added' do
      env = probe.worker_env(1, serial)
      expect(env['LANES_WORKER']).to eq('1')
      expect(env['LANES_DATASTORE_DB']).to eq('100')
      expect(env['REDIS_URL']).to eq('redis://127.0.0.1:2163/100')
      expect(env['LANES_RSPEC_STATUS_FILE']).to eq('/x/y/rspec-status.txt')
      expect(probe.argv(1, serial, '--out', 'tmp/results.json')).to eq(%w[--out tmp/results.json])
    end

    it 'works without a datastore index at all' do
      env = probe.worker_env(1, {})
      expect(env['LANES_WORKER']).to eq('1')
      expect(env).not_to have_key('LANES_DATASTORE_DB')
    end

    it 'refuses a worker the run never claimed' do
      output, status = probe.run(2, serial, 'true')
      expect(status.exitstatus).to eq(64), output
      expect(output).to include("worker 2 is outside this run's 1..1")
    end
  end

  describe 'refusals' do
    it 'refuses a worker above LANES_WORKERS' do
      output, status = probe.run(4, base_env, 'true')
      expect(status.exitstatus).to eq(64), output
      expect(output).to include("worker 4 is outside this run's 1..3")
    end

    it 'refuses worker 0 and a non-numeric worker' do
      _, status = probe.run(0, base_env, 'true')
      expect(status.exitstatus).to eq(64)
      output, status = probe.run('x', base_env, 'true')
      expect(status.exitstatus).to eq(64), output
      expect(output).to include("worker index 'x' is not a decimal number")
    end

    it 'refuses to derive a worker index outside the runner' do
      output, status = probe.run(2, { 'LANES_WORKERS' => '2' }, 'true')
      expect(status.exitstatus).to eq(64), output
      expect(output).to include('LANES_DATASTORE_DB is unset')
    end

    it 'refuses a missing command' do
      output, status = Open3.capture2e({ 'PATH' => ENV.fetch('PATH') }, probe.shim, '1', unsetenv_others: true)
      expect(status.exitstatus).to eq(64), output
      expect(output).to include('usage: tests/lanes/support/worker-env')
    end
  end

  it 'derives the indexes tests/lanes/run claimed for the same run' do
    # The runner claims (and prints) the list; the shim derives one member
    # at a time from the base and the worker number. A formula change on
    # one side without the other would hand a worker an index nobody
    # claimed — a silent collision with whichever run owns it.
    fields = probe.print_key('unit', '--workers', '3')
    env    = { 'LANES_WORKERS' => '3', 'LANES_DATASTORE_DB' => fields['db'], 'REDIS_URL' => fields['redis'] }
    derived = (1..3).map { |k| probe.worker_env(k, env) }

    expect(derived.map { |e| e['LANES_DATASTORE_DB'] }).to eq(fields['worker_dbs'].split(','))
    expect(derived.map { |e| e['REDIS_URL'] }).to eq(fields['worker_dbs'].split(',').map { |i| "redis://127.0.0.1:2163/#{i}" })
  end
end
