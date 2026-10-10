# spec/unit/onetime/jobs/registry_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/jobs/registry'

# The one discovery of scheduled job classes (#4343). The expected set is
# derived from the job files on disk, not a hardcoded count: adding a job file
# must add a catalog row, and nothing else may.
#
# One file defines its class conditionally: catalog_retry_job.rb is wrapped in
# `if Onetime.billing_config.enabled?`, evaluated when the file is first
# required. In a process that loaded it with billing off there is no
# CatalogRetryJob to schedule or list, so the catalog has one row fewer.
RSpec.describe Onetime::Jobs::Registry do
  let(:job_files) do
    Dir.glob(File.join(Onetime::HOME, 'lib', 'onetime', 'jobs', 'scheduled', '**', '*_job.rb')).sort
  end

  let(:billing_gated_job_files) { %w[catalog_retry_job.rb] }

  # Job files whose class this process defined.
  let(:defined_job_files) do
    next job_files if defined?(Onetime::Jobs::Scheduled::CatalogRetryJob)

    job_files.reject { |file| billing_gated_job_files.include?(File.basename(file)) }
  end

  before { described_class.load_all! }

  it 'globs lib/onetime/jobs/scheduled/ and scheduled/maintenance/' do
    expect(described_class.job_files).to eq(job_files)
    expect(job_files.map { |file| File.basename(File.dirname(file)) }.uniq).to contain_exactly('scheduled', 'maintenance')
  end

  it 'lists exactly the classes defined in the job files, one per file' do
    sources = described_class.concrete_classes.map do |klass|
      file = Object.const_source_location(klass.name)&.first
      file ? File.expand_path(file) : "#{klass.name} (no source file)"
    end

    expect(sources).to match_array(defined_job_files.map { |file| File.expand_path(file) })
  end

  it 'derives each job_id from its class, matching the file name' do
    expected_ids = defined_job_files.map { |file| File.basename(file, '.rb').delete_suffix('_job') }

    expect(described_class.entries.map { |entry| entry['job_id'] }).to match_array(expected_ids)
  end

  it 'gives every job a unique id' do
    ids = described_class.entries.map { |entry| entry['job_id'] }
    expect(ids.uniq.size).to eq(ids.size)
  end

  it 'excludes the abstract MaintenanceJob' do
    expect(described_class.concrete_classes).not_to include(Onetime::Jobs::MaintenanceJob, Onetime::Jobs::ScheduledJob)
  end

  it 'skips anonymous subclasses, including ones that override .name' do
    stub = Class.new(Onetime::Jobs::ScheduledJob) do
      def self.name = 'PretendJob'
      def self.schedule(_scheduler) = nil
    end

    expect(described_class.concrete_classes).not_to include(stub)
    expect(described_class.entries.map { |entry| entry['job_id'] }).not_to include('pretend')
  end

  it 'groups MaintenanceJob subclasses as maintenance and the rest as scheduled' do
    groups = described_class.entries.to_h { |entry| [entry['job_id'], entry['group']] }

    expect(groups['heartbeat']).to eq('scheduled')
    expect(groups['phantom_cleanup']).to eq('maintenance')
    maintenance_dir = job_files.select { |file| file.include?('/scheduled/maintenance/') }
    expect(maintenance_dir.map { |file| groups[File.basename(file, '.rb').delete_suffix('_job')] }).to all(eq('maintenance'))
  end

  it 'resolves a job class from its id' do
    expect(described_class.job_class_for('heartbeat')).to eq(Onetime::Jobs::Scheduled::HeartbeatJob)
    expect(described_class.job_class_for('participation_gc'))
      .to eq(Onetime::Jobs::Scheduled::Maintenance::ParticipationGCJob)
    expect(described_class.job_class_for('nope')).to be_nil
  end
end
