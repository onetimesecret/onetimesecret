# spec/unit/lanes/datastore_pool_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# The bounded connection pool spec_helper and try/support/test_helpers.rb
# install for a process that never runs SetupConnectionPool
# (tests/lanes/support/datastore_pool.rb).
#
# Without it, every Familia.dbclient lookup in a unit spec opened a fresh
# connection (familia 2.12 fallback, delano/familia#456): one datastore-heavy
# spec file exhausted the ephemeral port range on macOS and the lane runner
# reported the test valkey lost mid-run. Each example here starts from the
# pre-install state, no provider and no registered pool, and puts the
# process's own pool back afterwards.
RSpec.describe Lanes::DatastorePool do
  include OnetimeStateHelpers

  let(:lookups) { 50 }
  let(:installed) { [] }

  around do |example|
    snapshot = snapshot_familia_pool_config

    Familia.connection_provider = nil
    Onetime::Runtime.update_infrastructure(database_pool: nil)
    example.run
  ensure
    restore_familia_pool_config(snapshot)
  end

  after { installed.each { |pool| pool.shutdown(&:close) } }

  def install!(uri: Familia.uri, **)
    described_class.install!(uri:, **).tap { |pool| installed << pool }
  end

  def registered_pool
    Onetime::Runtime.infrastructure.database_pool
  end

  # The server-side id of the connection a lookup returns. Distinct ids mean
  # distinct sockets.
  def connection_ids(count)
    Array.new(count) { Familia.dbclient.call('CLIENT', 'ID') }
  end

  # Where a client would connect, read from its configuration: no command
  # is sent, so nothing reaches the address.
  def target_of(client)
    client.connection.values_at(:host, :port, :db)
  end

  it 'serves repeated Familia.dbclient lookups from one pooled connection' do
    install!

    expect(connection_ids(lookups).uniq.size).to eq(1)
  end

  it 'registers the pool so with_pinned_dbclient resolves lookups to the pinned connection' do
    pool = install!

    pinned_served = Onetime.with_pinned_dbclient { |pinned| Familia.dbclient.equal?(pinned) }
    expect([registered_pool, pinned_served]).to eq([pool, true])
  end

  # Before install! took a URI, the tryouts helper installed the pool while
  # Familia.uri still read 127.0.0.1:6379 (the development datastore), and
  # its billing guard probed Familia.dbclient before setting the test URI:
  # that probe left a connection to 6379 in the pool for the whole run.
  context 'with Familia.uri still at its 127.0.0.1:6379 default' do
    let(:test_uri) { Familia.uri.to_s }
    let(:default_uri) { 'redis://127.0.0.1:6379/0' }

    before do
      test_uri
      Familia.uri = default_uri
    end

    it 'makes the URI it is given Familia.uri' do
      install!(uri: test_uri)

      expect(Familia.uri.to_s).to eq(test_uri)
    end

    it 'connects every pooled client to that URI, even after Familia.uri changes' do
      pool        = install!(uri: test_uri)
      Familia.uri = default_uri

      targets = pool.with { |first| pool.with { |second| [first, second].map { |conn| target_of(conn) } } }
      expect(targets).to eq([target_of(Familia.create_dbclient(test_uri))] * 2)
    end
  end

  it 'builds connections with the reconnect attempts a booted pool uses' do
    pool = install!

    delays = pool.with { |conn| Array.new(5) { |attempt| conn._client.config.retriable?(attempt) } }
    expect(delays).to eq([*Onetime::DATABASE_RECONNECT_ATTEMPTS, nil])
  end

  it 'takes the size and timeout it is given' do
    pool = install!(size: 3, timeout: 7)

    expect([pool.size, pool.instance_variable_get(:@timeout)]).to eq([3, 7])
  end

  it 'leaves a provider that is already installed alone' do
    provider = ->(_uri) { :owned_elsewhere }

    Familia.connection_provider = provider

    expect([described_class.install!(uri: Familia.uri), Familia.connection_provider, registered_pool]).to eq([nil, provider, nil])
  end

  it 'refuses a FAMILIA_POOL_SIZE that is not an integer' do
    original                 = ENV.fetch('FAMILIA_POOL_SIZE', nil)
    ENV['FAMILIA_POOL_SIZE'] = 'abc'

    expect { described_class.install!(uri: Familia.uri) }.to raise_error(ArgumentError)
  ensure
    if original.nil?
      ENV.delete('FAMILIA_POOL_SIZE')
    else
      ENV['FAMILIA_POOL_SIZE'] = original
    end
  end

  # The behaviour the pool exists to replace, kept small: five sockets, each
  # closed. A familia release that reuses fallback connections makes this
  # example fail, which is the cue to revisit whether the pool is still
  # needed.
  it 'without it, the fallback opens a connection per lookup' do
    clients = Array.new(5) { Familia.dbclient }

    expect(clients.map { |client| client.call('CLIENT', 'ID') }.uniq.size).to eq(5)
  ensure
    clients&.each(&:close)
  end
end
