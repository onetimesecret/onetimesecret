# try/unit/jobs/domain_refresh_job_try.rb
#
# frozen_string_literal: true

# Onetime::Jobs::Scheduled::DomainRefreshJob cursor walk.
#
# The job used to take the newest batch_size domains on every run, so any
# domain past the first batch never refreshed. It now resumes from a persisted
# cursor, one batch per run, and wraps at the end of the set.
#
# CustomDomain.instances / load_multi and Operations::VerifyDomain are swapped
# for in-memory stand-ins (restored at the end) so the walk is observable
# without Approximated or a populated domain set. The cursor itself is real.

require_relative '../../support/test_helpers'

OT.boot! :test

require 'onetime/operations/verify_domain'
require_relative '../../../lib/onetime/jobs/scheduled/domain_refresh_job'

RefreshJob = Onetime::Jobs::Scheduled::DomainRefreshJob

@orig_conf = OT.instance_variable_get(:@conf)
OT.instance_variable_set(:@conf, @orig_conf.merge(
  'jobs' => { 'domain_refresh' => { 'enabled' => true, 'batch_size' => 2, 'rate_limit' => 0 } },
))

# Newest-first id list, as revrangeraw would return it.
IDS = %w[d5 d4 d3 d2 d1].freeze

class FakeInstances
  def revrangeraw(start, stop) = IDS[start..stop] || []
end

class FakeVerify
  class << self
    attr_accessor :seen
  end
  self.seen = []

  def initialize(domains:, **) = @domains = domains

  def call
    self.class.seen << @domains
    Onetime::Operations::VerifyDomain::BulkResult.new(
      total: @domains.size, verified_count: 0, failed_count: 0,
      skipped_count: 0, results: [], duration_seconds: 0.0
    )
  end
end

@cd = Onetime::CustomDomain.singleton_class
@cd.send(:alias_method, :__orig_instances, :instances)
@cd.send(:alias_method, :__orig_load_multi, :load_multi)
@cd.send(:define_method, :instances) { FakeInstances.new }
@cd.send(:define_method, :load_multi) { |ids| ids }

@real_verify = Onetime::Operations::VerifyDomain
Onetime::Operations.send(:remove_const, :VerifyDomain)
Onetime::Operations.const_set(:VerifyDomain, FakeVerify)
FakeVerify.const_set(:BulkResult, @real_verify::BulkResult)

Familia.dbclient.del(RefreshJob::CURSOR_KEY)

def run_refresh
  RefreshJob.send(:refresh_domains)
  Familia.dbclient.get(RefreshJob::CURSOR_KEY).to_i
end

## next_offset advances by a full page and wraps on a short or empty one
[RefreshJob.send(:next_offset, 0, 2), RefreshJob.send(:next_offset, 4, 1), RefreshJob.send(:next_offset, 4, 0)]
#=> [2, 0, 0]

## Run 1 takes the newest batch and advances the cursor
run_refresh
#=> 2

## Run 2 resumes where run 1 stopped
run_refresh
#=> 4

## Run 3 reaches the short last page and wraps the cursor
run_refresh
#=> 0

## Every domain was refreshed exactly once across the three runs
FakeVerify.seen
#=> [%w[d5 d4], %w[d3 d2], %w[d1]]

## Run 4 starts over from the newest batch
run_refresh
FakeVerify.seen.last
#=> %w[d5 d4]

## A cursor past the end of the set (domains were removed) restarts at the top
Familia.dbclient.set(RefreshJob::CURSOR_KEY, '40')
run_refresh
[FakeVerify.seen.last, Familia.dbclient.get(RefreshJob::CURSOR_KEY).to_i]
#=> [%w[d5 d4], 2]

# Teardown
Familia.dbclient.del(RefreshJob::CURSOR_KEY)
Onetime::Operations.send(:remove_const, :VerifyDomain)
Onetime::Operations.const_set(:VerifyDomain, @real_verify)
@cd.send(:alias_method, :instances, :__orig_instances)
@cd.send(:alias_method, :load_multi, :__orig_load_multi)
@cd.send(:remove_method, :__orig_instances)
@cd.send(:remove_method, :__orig_load_multi)
OT.instance_variable_set(:@conf, @orig_conf)
