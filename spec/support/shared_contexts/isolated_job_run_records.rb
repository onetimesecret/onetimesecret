# spec/support/shared_contexts/isolated_job_run_records.rb
#
# frozen_string_literal: true

require 'securerandom'

# For examples that read or write scheduler run records
# (Onetime::Jobs::JobRun, #4343) against the real test Valkey.
#
# Each example gets its own key namespace: KEY_PREFIX and SCHEDULER_KEY are
# stubbed to a random suffix, so concurrent spec processes and earlier examples
# cannot leak a record into this one. Every job key the example touches is
# collected through the module's own `key` accessor and deleted afterwards, by
# name; nothing scans the keyspace.
RSpec.shared_context 'with isolated job run records' do
  let(:job_run_namespace) { "spec:#{SecureRandom.hex(6)}" }
  let(:touched_job_run_keys) { [] }

  before do
    stub_const('Onetime::Jobs::JobRun::KEY_PREFIX', "jobs:run:#{job_run_namespace}")
    stub_const('Onetime::Jobs::JobRun::SCHEDULER_KEY', "jobs:scheduler:#{job_run_namespace}")
    touched_job_run_keys << Onetime::Jobs::JobRun::SCHEDULER_KEY

    allow(Onetime::Jobs::JobRun).to receive(:key).and_wrap_original do |original, job_id|
      original.call(job_id).tap { |dbkey| touched_job_run_keys << dbkey }
    end
  end

  after do
    keys = touched_job_run_keys.uniq
    Familia.dbclient.del(*keys) unless keys.empty?
  end
end
