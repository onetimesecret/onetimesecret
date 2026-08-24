# spec/integration/all/colonel_backup_status_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'
require 'colonel/application'

RSpec.describe 'Colonel backup status', type: :integration do
  STATUS_PREFIX = 'ots:backup:status:'

  def strategy_result_for(user)
    double(
      'StrategyResult',
      session: {},
      user: user,
      metadata: { ip: '127.0.0.1' },
      auth_method: 'sessionauth',
    )
  end

  def colonel
    @colonel ||= begin
      customer          = Onetime::Customer.create!(email: "colonel-#{SecureRandom.hex(4)}@example.com")
      customer.role     = 'colonel'
      customer.verified = 'true'
      customer.save
      customer
    end
  end

  def write_status(job, suffix: '', overrides: {})
    fields = {
      'event' => 'ok',
      'ts' => '1700000000',
      'host' => 'eu-db-01',
      'unit' => "ots-backup-#{job}.service",
      'job' => job,
      'file' => "/var/backups/#{job}.tar.gz",
      'bytes' => '1048576',
      'sha256' => 'a' * 64,
      'mode' => '',
      'removed' => '',
      'candidates' => '',
      'shipped' => '',
      'remote' => '',
      'duration_secs' => '10',
      'error' => '',
      'version' => '0.2.3',
      'scheduled' => 'enabled',
    }.merge(overrides)

    fields.each { |field, value| Familia.dbclient.hset("#{STATUS_PREFIX}#{job}#{suffix}", field, value) }
  end

  def status
    logic = ColonelAPI::Logic::Colonel::GetBackupStatus.new(strategy_result_for(colonel), {})
    logic.raise_concerns
    logic.process
  end

  it 'reads only recognized status hashes and returns missing jobs as not configured' do
    write_status('pg', overrides: { 'event' => 'fail', 'error' => 'disk full' })
    write_status('pg', suffix: ':last_ok', overrides: { 'ts' => '1699999000' })
    write_status('_check', overrides: { 'event' => 'fail', 'error' => 'must be ignored' })

    # Pin `Familia.dbclient` to this instrumented instance: the lane client may
    # resolve a fresh wrapper on each accessor call, which otherwise makes the
    # production read invisible to this example's spy.
    colonel
    client = Familia.dbclient
    allow(Familia).to receive(:dbclient).and_return(client)
    allow(client).to receive(:hgetall).and_call_original

    data = status

    expect(client).to have_received(:hgetall).with("#{STATUS_PREFIX}pg")
    expect(client).not_to have_received(:hgetall).with("#{STATUS_PREFIX}_check")

    jobs = data[:details][:jobs]
    expect(jobs.map { |job| job[:job] }).to eq(%w[pg valkey prune ship])
    expect(jobs.first).to include(configured: true)
    expect(jobs.first[:latest]).to include(event: 'fail', error: 'disk full')
    expect(jobs.first[:last_ok]).to include(event: 'ok', ts: 1_699_999_000, file: '/var/backups/pg.tar.gz')
    expect(jobs.first[:latest]).to include(shipped: '', remote: '')
    expect(jobs.first[:last_ok]).to include(shipped: '', remote: '')
    expect(jobs.drop(1)).to all(include(configured: false, latest: nil, last_ok: nil))
  end

  it 'passes ship-job shipped and remote fields through verbatim' do
    ship_overrides = {
      'shipped' => '2',
      'candidates' => '7',
      'remote' => 's3:onetime-eu/backups/',
      'file' => '',
      'bytes' => '25806368',
    }
    write_status('ship', overrides: ship_overrides)
    write_status('ship', suffix: ':last_ok', overrides: ship_overrides)

    ship_job = status[:details][:jobs].find { |entry| entry[:job] == 'ship' }

    expect(ship_job[:configured]).to be(true)
    expect(ship_job[:latest]).to include(
      event: 'ok',
      shipped: '2',
      candidates: '7',
      remote: 's3:onetime-eu/backups/',
      file: '',
      bytes: '25806368',
    )
    expect(ship_job[:last_ok]).to include(shipped: '2', remote: 's3:onetime-eu/backups/')
  end

  it 'nulls an error exceeding the 4096-byte text cap while preserving the rest of the record' do
    oversized_error = 'e' * 4_097
    write_status('pg', overrides: { 'event' => 'fail', 'error' => oversized_error })

    pg_job = status[:details][:jobs].find { |entry| entry[:job] == 'pg' }

    expect(pg_job[:latest]).to include(
      event: 'fail',
      error: nil,
      ts: 1_700_000_000,
      host: 'eu-db-01',
      file: '/var/backups/pg.tar.gz',
      bytes: '1048576',
      version: '0.2.3',
      scheduled: 'enabled',
    )
  end

  it 'nulls malformed shipped and remote values' do
    write_status('ship', overrides: { 'shipped' => '2x', 'remote' => "s3:bucket\nextra" })

    ship_job = status[:details][:jobs].find { |entry| entry[:job] == 'ship' }

    expect(ship_job[:latest]).to include(shipped: nil, remote: nil)
  end

  it 'normalizes malformed hash values, preserves long valid errors, and does not trust a malformed last_ok event' do
    long_error = 'x' * 2_049
    write_status('valkey', overrides: {
      'event' => 'unexpected',
      'ts' => 'not-a-timestamp',
      'error' => "two\nlines",
      'scheduled' => 'sometimes',
      'bytes' => '-1',
    })
    write_status('valkey', suffix: ':last_ok', overrides: { 'event' => 'fail' })
    write_status('pg', overrides: { 'event' => 'fail', 'error' => long_error, 'ts' => '9' * 21 })

    valkey_job = status[:details][:jobs].find { |entry| entry[:job] == 'valkey' }
    pg_job     = status[:details][:jobs].find { |entry| entry[:job] == 'pg' }

    expect(valkey_job[:configured]).to be(true)
    expect(valkey_job[:latest]).to include(event: nil, ts: nil, error: nil, scheduled: nil, bytes: nil)
    expect(valkey_job[:last_ok]).to be_nil
    expect(pg_job[:latest]).to include(error: long_error, ts: nil)
  end

  it 'propagates Valkey read failures instead of reporting a job as not configured' do
    # See the access pinning in the recognized-hashes example above. Create the
    # actor before stubbing so Customer persistence cannot consume this failure.
    colonel
    client = Familia.dbclient
    allow(Familia).to receive(:dbclient).and_return(client)
    allow(client).to receive(:hgetall).and_call_original
    allow(client).to receive(:hgetall)
      .with("#{STATUS_PREFIX}pg")
      .and_raise(StandardError, 'NOPERM this user has no permissions')

    expect { status }.to raise_error(StandardError, /NOPERM/)
  end
end
