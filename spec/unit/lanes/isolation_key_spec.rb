# spec/unit/lanes/isolation_key_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require_relative '../../support/lane_probe'
require 'open3'
require 'socket'
require 'tempfile'
require 'tmpdir'

# Regression harness for the datastore isolation key in tests/lanes/run.
#
# Two halves, both of which fail silently when they break — which is the
# reason they are tested at all:
#
#   1. The key. It derives the valkey DB index and the PG database suffix
#      from lane + overlays + repo root. When it was the repo root alone,
#      `unit` and `full-sqlite` in one checkout shared a datastore and
#      contaminated each other's fixtures (#4168); a regression here does
#      not raise, it just makes two runs agree on an index.
#   2. The owner marker's staleness test. The marker now stores the whole
#      composed key, and the runner has to strip the lane and overlay
#      fields back off before asking whether the owner's checkout still
#      exists. Skip that strip and every live foreign owner looks like a
#      path that does not exist, i.e. stale — the collision guard then
#      fails OPEN, taking over a database another run is using while
#      reporting success. That is strictly worse than having no guard.
#
# Method: run the real `tests/lanes/run`. `--print-key` reports the derived
# addressing without touching a service, which is what makes the key half
# cheap; the marker half needs a real valkey and gets one, on a pinned
# index far from anything a derived key would pick.
module LaneIsolationProbe
  # Well outside the range this worktree's lanes derive, and cleaned up in
  # an `after` hook. Two indexes so the two marker examples cannot see each
  # other's leftovers, whatever order they run in.
  PINNED_OWNER_IDX  = 65011
  PINNED_ACTIVE_IDX = 65012
  # A pair: a two-worker run's own index and the one its worker 2 borrows.
  PINNED_WORKER_IDX = 65013
  # Both marker examples expect their runner invocation to ABORT, so what
  # the run would have executed is irrelevant — but it is not free to leave
  # unspecified. The guards are deliberately best-effort (a protocol hiccup
  # proceeds rather than aborts), and this spec runs inside the unit lane's
  # own spec:fast, where a fail-open on a bare `run unit` invocation would
  # recurse into a FULL nested unit lane — seven minutes of tryouts and
  # rspec captured into one example's failure message, regenerating
  # generated/ mid-suite as it goes. `--only` caps that worst case at one
  # small rspec file while changing nothing under test: the owner marker
  # and liveness token blocks both sit upstream of the --only branch.
  ONLY_TARGET       = 'spec/unit/lanes/hermetic_boundary_spec.rb'
  VALKEY_PORT       = 2163
  # The `unit` lane's preflight builds its required-port list from its own
  # env, so a marker example needs both of these up or it never reaches the
  # block under test. Autostart is refused below rather than triggered:
  # a spec must not start containers.
  LANE_PORTS        = [VALKEY_PORT, 2156].freeze

  extend LaneProbe

  module_function

  def lane_services_up?
    return @lane_services_up if defined?(@lane_services_up)

    @lane_services_up = LANE_PORTS.all? do |port|
      TCPSocket.new('127.0.0.1', port).close
      true
    rescue SystemCallError
      false
    end
  end

  # 'CI' => nil UNSETS it in the child. Load-bearing: a non-empty CI makes
  # the runner short-circuit to index 0 for everything, which is the CI
  # parity contract and would make every example here pass vacuously (all
  # indexes equal 0, and no marker is ever written). The behavior under
  # test is the local one.
  def run(*args, env: {})
    Open3.capture2e(
      { 'CI' => nil, 'LANES_NO_AUTOSTART' => '1' }.merge(env),
      runner, *args, chdir: repo_root
    )
  end

  # `--only` runs one process, so a run that needs a second worker cannot
  # take it and loses the cap ONLY_TARGET buys: a guard that failed open
  # would start the whole lane, nested. A deadline is the cap instead. The
  # run gets its own process group, signalled whole when time is up, since
  # the lane's tasks and the runner's refresher are in it too.
  def run_with_deadline(*args, env: {}, deadline: 60)
    Tempfile.create('ots-lane-run') do |log|
      pid    = Process.spawn(
        { 'CI' => nil, 'LANES_NO_AUTOSTART' => '1' }.merge(env),
        runner,
        *args,
        chdir: repo_root,
        pgroup: true,
        in: File::NULL,
        [:out, :err] => log,
      )
      waiter = Process.detach(pid)
      unless waiter.join(deadline)
        begin
          Process.kill('TERM', -pid)
          Process.kill('KILL', -pid) unless waiter.join(10)
        rescue Errno::ESRCH
          nil
        end
        raise "tests/lanes/run #{args.join(' ')} was still running after #{deadline}s:\n#{File.read(log.path)}"
      end
      [File.read(log.path), waiter.value]
    end
  end

  # `--print-key` prints one line of `k=v` fields; the key field is last
  # because its value contains no spaces but does contain the repo path.
  def print_key(*args)
    output, status = run(*args, '--print-key')
    raise "tests/lanes/run #{args.join(' ')} --print-key failed:\n#{output}" unless status.success?

    output.scan(/(\w+)=(\S*)/).to_h
  end

  # A lane env file cannot be reached from here and the calling shell's
  # exports are scrubbed, so the only way to pin an index from outside is a
  # readonly export the scrub's `unset` cannot clear. The same BASH_ENV
  # fixture mechanism hermetic_boundary_spec.rb uses for its readonly
  # functions, and it keeps these examples off whatever index this worktree
  # actually derives.
  def with_pinned_index(index)
    Dir.mktmpdir('ots-lane-pin') do |dir|
      rc = File.join(dir, 'pin.bash')
      File.write(rc, "export LANES_DATASTORE_DB=#{index}\nreadonly LANES_DATASTORE_DB\n")
      yield rc
    end
  end

  # Minimal RESP client. Deliberately not the app's connection: these
  # examples assert on a runner-internal key in a database the app never
  # opens, and going through Familia would tie them to whatever connection
  # state the surrounding suite happens to have left behind.
  def valkey(index, *commands)
    sock = TCPSocket.new('127.0.0.1', VALKEY_PORT)
    sock.write(encode('SELECT', index.to_s))
    read_reply(sock)
    commands.map do |command|
      sock.write(encode(*command))
      read_reply(sock)
    end.last
  ensure
    sock&.close
  end

  def encode(*args)
    args.map(&:to_s).inject("*#{args.size}\r\n") { |out, a| out + "$#{a.bytesize}\r\n#{a}\r\n" }
  end

  def read_reply(sock)
    line = sock.gets.chomp
    return nil if line == '$-1'
    return line[1..] unless line.start_with?('$')

    sock.read(Integer(line[1..]) + 2).chomp
  end
end

RSpec.describe 'tests/lanes/run datastore isolation key' do
  let(:probe) { LaneIsolationProbe }

  include_context 'with the lane runner bash'

  describe 'key composition' do
    it 'derives a different index for each lane in one checkout' do
      # The defect this whole feature exists to close: before lane joined
      # the key, every lane in a worktree got one index and one PG
      # database, so `unit` and `api` running together in one checkout
      # shared fixtures exactly the way two worktrees used to.
      indexes = %w[unit api full-sqlite disabled].to_h { |lane| [lane, probe.print_key(lane)['db']] }

      expect(indexes.values.uniq.size).to eq(indexes.size), "expected four distinct indexes, got #{indexes}"
      expect(indexes.values).to all(match(/\A\d+\z/))
      expect(indexes.values).not_to include('0')
    end

    it 'derives a different index for each overlay set of one lane' do
      # An overlay changes what the run writes (billing turns on a whole
      # subsystem's fixtures), so it has to change where the run writes.
      bare    = probe.print_key('full-sqlite')
      billing = probe.print_key('full-sqlite', '--overlay', 'billing')

      expect(bare['overlays']).to eq('none')
      expect(billing['overlays']).to eq('billing')
      expect(billing['db']).not_to eq(bare['db'])
    end

    it 'normalizes an overlay set before keying on it' do
      # Same environment, twice as many flags. A developer who repeats a
      # flag must not be handed a second, empty datastore — that is a new
      # bug wearing the isolation's clothes.
      once  = probe.print_key('full-sqlite', '--overlay', 'billing')
      twice = probe.print_key('full-sqlite', '--overlay', 'billing', '--overlay', 'billing')

      expect(twice['db']).to eq(once['db'])
      expect(twice['key']).to eq(once['key'])
    end

    it 'puts the repo root last so a path can never be misparsed' do
      # The owner marker recovers the path by stripping two fields, which
      # only works while the path is the field that runs to end-of-string.
      key = probe.print_key('unit')['key']

      expect(key).to eq("unit||#{probe.repo_root}")
      expect(key.split('|', 3).last).to eq(probe.repo_root)
    end

    it 'carries the index into the addressing the lane actually uses' do
      fields = probe.print_key('full-pg')

      expect(fields['redis']).to eq("redis://127.0.0.1:2163/#{fields['db']}")
      expect(fields['auth_db']).to end_with("_w#{fields['db']}")
    end
  end

  describe 'worker indexes' do
    # A run with N workers uses N indexes (#4551): worker 1 on the lane's own,
    # the rest on the ones after it, wrapping inside 1..65535. The runner
    # claims and prints the list; tests/lanes/support/worker-env derives each
    # member for the task side (worker_env_spec.rb checks the two agree).
    def shim_env(k, env)
      shim = File.join(probe.repo_root, 'tests', 'lanes', 'support', 'worker-env')
      output, status = Open3.capture2e(
        { 'PATH' => ENV.fetch('PATH') }.merge(env), shim, k.to_s, 'env', unsetenv_others: true, chdir: probe.repo_root
      )
      raise "worker-env #{k} failed:\n#{output}" unless status.success?

      output.lines.filter_map { |l| l.match(/\A([A-Za-z_][A-Za-z0-9_]*)=(.*)\n?\z/) { |m| [m[1], m[2]] } }.to_h
    end

    it 'lists one index per worker, the first being the lane\'s own' do
      fields = probe.print_key('unit', '--workers', '3')
      db     = Integer(fields['db'])

      expect(fields['workers']).to eq('3')
      expect(fields['worker_dbs']).to eq((0..2).map { |i| 1 + ((db - 1 + i) % 65535) }.join(','))
      expect(fields['worker_dbs'].split(',').first).to eq(fields['db'])
    end

    it 'wraps at 65535 rather than landing a worker on 0 or past the last database' do
      output, status = probe.with_pinned_index(65535) do |rc|
        probe.run('unit', '--workers', '2', '--print-key', env: { 'BASH_ENV' => rc })
      end
      expect(status).to be_success, output
      fields = output.scan(/(\w+)=(\S*)/).to_h

      expect(fields['db']).to eq('65535')
      expect(fields['worker_dbs']).to eq('65535,1')
    end

    it 'gives CI (base 0) the workers 0..N-1' do
      output, status = probe.run('api', '--workers', '3', '--print-key', env: { 'CI' => '1' })
      expect(status).to be_success, output
      fields = output.scan(/(\w+)=(\S*)/).to_h

      expect(fields['db']).to eq('0')
      expect(fields['worker_dbs']).to eq('0,1,2')
    end

    it 'reads a pinned index as a decimal, so 00 is the shared index to runner and shim alike' do
      # The runner tests the index as a string in places (`!= 0`) and the
      # shim does arithmetic on it; normalised once at validation, a pinned
      # `00` is 0 to both rather than isolated to one and shared to the other.
      # Pinned through an overlay, the documented way (with_pinned_index's
      # readonly export cannot be rewritten by the runner).
      name = "isolation-key-#{Process.pid}"
      path = File.join(probe.repo_root, 'tests', 'lanes', 'overlays', "#{name}.env")
      File.write(path, "LANES_DATASTORE_DB=00\n")
      begin
        output, status = probe.run('unit', '--overlay', name, '--workers', '2', '--print-key')
      ensure
        File.delete(path)
      end
      expect(status).to be_success, output
      fields = output.scan(/(\w+)=(\S*)/).to_h

      expect(fields['db']).to eq('0')
      expect(fields['worker_dbs']).to eq('0,1')
      expect(fields['redis']).to eq('redis://127.0.0.1:2163/0')
    end

    it 'runs --only as one worker whatever the lane declares' do
      expect(probe.print_key('unit')['workers']).to eq('2')
      fields = probe.print_key('unit', '--only', LaneIsolationProbe::ONLY_TARGET)
      expect(fields['workers']).to eq('1')
      expect(fields['worker_dbs']).to eq(fields['db'])
    end

    it 'hands each worker its own redis URL through the shim' do
      fields = probe.print_key('unit', '--workers', '3')
      env    = { 'LANES_WORKERS' => '3', 'LANES_DATASTORE_DB' => fields['db'], 'REDIS_URL' => fields['redis'] }

      urls = (1..3).map { |k| shim_env(k, env)['REDIS_URL'] }
      expect(urls).to eq(fields['worker_dbs'].split(',').map { |i| "redis://127.0.0.1:2163/#{i}" })
      expect(urls.first).to eq(fields['redis'])
    end
  end

  describe 'owner marker staleness' do
    before do
      skip 'test services (valkey 2163, rabbitmq 2156) are not up' unless probe.lane_services_up?
    end

    after do
      # The owner marker lives in the isolated database; the liveness token
      # lives in DB 0 under the index it is about, out of reach of the
      # flushes a lane run performs on its own database.
      [LaneIsolationProbe::PINNED_OWNER_IDX, LaneIsolationProbe::PINNED_ACTIVE_IDX].each do |index|
        probe.valkey(index, %w[DEL _lanes:owner])
        probe.valkey(0, ['DEL', "_lanes:active:#{index}"])
      end
    end

    it 'aborts when a composed marker names a checkout that still exists' do
      # The fail-open case, seeded: a foreign owner whose root is a real
      # directory. If the runner tested `-d` against the whole composed
      # value it would find no such directory, call this stale, take the
      # database over and run — silently sharing a datastore with the run
      # that owns it.
      index = LaneIsolationProbe::PINNED_OWNER_IDX
      probe.valkey(index, ['SET', '_lanes:owner', "otherlane||#{probe.repo_root}"])

      output, status = probe.with_pinned_index(index) do |rc|
        probe.run('unit', '--only', LaneIsolationProbe::ONLY_TARGET, env: { 'BASH_ENV' => rc })
      end

      expect(status.exitstatus).to eq(69), "expected a collision abort, got:\n#{output}"
      expect(output).to include("valkey DB #{index} is in use by another live run")
      expect(output).to include('lane=otherlane')
      expect(output).to include("root=#{probe.repo_root}")
      # And the marker is left alone: aborting is the whole point.
      expect(probe.valkey(index, %w[GET _lanes:owner])).to eq("otherlane||#{probe.repo_root}")
    end

    it 'takes over a composed marker whose checkout is gone' do
      # The other half of the same parse. Worktrees get deleted; their
      # markers do not, so an index whose owner no longer exists on disk
      # has to be reclaimable or every removed worktree burns one forever.
      #
      # The run is stopped immediately after the takeover by a live
      # foreign liveness token — this RSpec process, which is by
      # definition running — so the example costs one runner startup
      # rather than one lane.
      index = LaneIsolationProbe::PINNED_ACTIVE_IDX
      probe.valkey(index, ['SET', '_lanes:owner', 'otherlane||/nonexistent/worktree/removed-last-week'])
      probe.valkey(
        0,
        ['SET', "_lanes:active:#{index}",
         "#{Process.pid}|otherlane||/nonexistent/worktree/removed-last-week", 'EX', '60'],
      )

      output, status = probe.with_pinned_index(index) do |rc|
        probe.run('unit', '--only', LaneIsolationProbe::ONLY_TARGET, env: { 'BASH_ENV' => rc })
      end

      expect(status.exitstatus).to eq(69), "expected the liveness token to stop the run, got:\n#{output}"
      expect(output).to include("already holds valkey DB #{index} (pid #{Process.pid})")
      # The takeover happened before that abort: the marker is ours now.
      expect(probe.valkey(index, %w[GET _lanes:owner])).to eq("unit||#{probe.repo_root}")
    end
  end

  describe 'worker index claims' do
    # Worker 1 runs on the lane's own index; worker 2 borrows the next one,
    # which is some other lane's own index as often as not. The borrowed
    # index is claimed for the run only: claimed for good, it would turn
    # that other lane away after the run had ended, because the checkout
    # that wrote the marker still exists and the staleness test reads that
    # as a live owner.
    let(:own) { LaneIsolationProbe::PINNED_WORKER_IDX }
    let(:borrowed) { own + 1 }
    let(:unit_key) { "unit||#{probe.repo_root}" }
    # Held by this RSpec process, which is alive by definition, under a key
    # that is neither run's: it stops a run at the liveness token without
    # standing for the owner of any marker.
    let(:bystander) { "#{Process.pid}|otherlane||/nonexistent/bystander" }

    before do
      skip 'test services (valkey 2163, rabbitmq 2156) are not up' unless probe.lane_services_up?

      # A spec process killed before its after hook would leave these.
      [own, borrowed].each do |index|
        probe.valkey(index, %w[DEL _lanes:owner])
        probe.valkey(0, ['DEL', "_lanes:active:#{index}"])
      end
    end

    after do
      [own, borrowed].each do |index|
        probe.valkey(index, %w[DEL _lanes:owner])
        probe.valkey(0, ['DEL', "_lanes:active:#{index}"])
      end
    end

    it "keeps only the lane's own index past the run, so a later lane takes the borrowed one" do
      # Run A: unit, two workers, stopped at the liveness token for its own
      # index. The owner markers for both indexes are written before that.
      probe.valkey(0, ['SET', "_lanes:active:#{own}", bystander, 'EX', '60'])
      output, status = probe.with_pinned_index(own) do |rc|
        probe.run_with_deadline('unit', '--workers', '2', env: { 'BASH_ENV' => rc })
      end

      expect(status.exitstatus).to eq(69), "expected the liveness token to stop run A, got:\n#{output}"
      expect(output).to include("already holds valkey DB #{own} (pid #{Process.pid})")
      expect(probe.valkey(own, %w[GET _lanes:owner])).to eq(unit_key)
      expect(probe.valkey(own, %w[TTL _lanes:owner])).to eq('-1')
      expect(probe.valkey(borrowed, %w[GET _lanes:owner])).to eq(unit_key)
      expect(Integer(probe.valkey(borrowed, %w[TTL _lanes:owner]))).to be_between(1, 60)

      # Run B: simple, whose own index A borrowed. A holds no token there
      # (it stopped before claiming one), so its marker is stale: B takes it
      # over for good and is stopped only by the bystander's token.
      probe.valkey(0, ['DEL', "_lanes:active:#{own}"])
      probe.valkey(0, ['SET', "_lanes:active:#{borrowed}", bystander, 'EX', '60'])
      output, status = probe.with_pinned_index(borrowed) do |rc|
        probe.run('simple', '--only', LaneIsolationProbe::ONLY_TARGET, env: { 'BASH_ENV' => rc })
      end

      expect(status.exitstatus).to eq(69), "expected the liveness token to stop run B, got:\n#{output}"
      expect(output).not_to include('is in use by another live run')
      expect(output).to include("already holds valkey DB #{borrowed} (pid #{Process.pid})")
      expect(probe.valkey(borrowed, %w[GET _lanes:owner])).to eq("simple||#{probe.repo_root}")
      expect(probe.valkey(borrowed, %w[TTL _lanes:owner])).to eq('-1')
    end

    it 'turns a later lane away from a borrowed index while the run that borrowed it is live' do
      # The same marker, now backed by its run's token: a live process
      # holding the index under the marker's own key.
      probe.valkey(borrowed, ['SET', '_lanes:owner', unit_key, 'EX', '60'])
      probe.valkey(0, ['SET', "_lanes:active:#{borrowed}", "#{Process.pid}|#{unit_key}", 'EX', '60'])

      output, status = probe.with_pinned_index(borrowed) do |rc|
        probe.run('simple', '--only', LaneIsolationProbe::ONLY_TARGET, env: { 'BASH_ENV' => rc })
      end

      expect(status.exitstatus).to eq(69), "expected a collision abort, got:\n#{output}"
      expect(output).to include("valkey DB #{borrowed} is in use by another live run")
      expect(output).to include('lane=unit')
      expect(probe.valkey(borrowed, %w[GET _lanes:owner])).to eq(unit_key)
    end
  end
end
