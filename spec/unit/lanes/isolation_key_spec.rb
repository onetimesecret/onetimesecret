# spec/unit/lanes/isolation_key_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'socket'
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

  module_function

  def repo_root
    File.expand_path('../../..', __dir__)
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

  before do
    major = probe.path_bash_major
    floor = probe.bash_floor
    skip "bash #{floor}+ is not on PATH (macOS: brew install bash)" if major.nil? || major < floor
  end

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
end
