# try/unit/jobs/domain_refresh_job_try.rb
#
# frozen_string_literal: true

# Onetime::Jobs::Scheduled::DomainRefreshJob page walk.
#
# The job used to take the newest batch_size domains on every run, so any
# domain past the first batch never refreshed. It now derives one page per run
# from the clock (whole intervals since the epoch, modulo the page count), so
# the walk covers the full set with no persisted position.
#
# CustomDomain.instances / load_multi, Operations::VerifyDomain and Familia.now
# are swapped for in-memory stand-ins (restored at the end) so the walk is
# observable without Approximated, a populated domain set, or a real clock.

require_relative '../../support/test_helpers'

OT.boot! :test

require 'onetime/operations/verify_domain'
require_relative '../../../lib/onetime/jobs/scheduled/domain_refresh_job'

RefreshJob = Onetime::Jobs::Scheduled::DomainRefreshJob

@orig_conf = OT.instance_variable_get(:@conf)
OT.instance_variable_set(:@conf, @orig_conf.merge(
  'jobs' => { 'domain_refresh' => { 'enabled' => true, 'batch_size' => 2, 'rate_limit' => 0, 'check_interval' => '30m' } },
))

# Newest-first id list, as revrangeraw would return it.
IDS = %w[d5 d4 d3 d2 d1].freeze

class FakeInstances
  def element_count = IDS.size
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

@familia = Familia.singleton_class
@familia.send(:alias_method, :__orig_now, :now)

# Tick 0 of a 3-page cycle: 1800s intervals, 5 domains, 2 per page.
BASE = 1800 * 3 * 1000

def run_refresh(now)
  @familia.send(:define_method, :now) { now }
  RefreshJob.send(:refresh_domains)
  FakeVerify.seen.last
end

## interval_seconds parses the configured rufus duration
RefreshJob.send(:interval_seconds, RefreshJob.send(:interval))
#=> 1800

## page_offset steps one aligned page per interval and wraps over the page count
[0, 1, 2, 3].map { |tick| RefreshJob.send(:page_offset, 5, BASE + (tick * 1800)) }
#=> [0, 2, 4, 0]

## page_offset is constant within an interval
[RefreshJob.send(:page_offset, 5, BASE + 1800), RefreshJob.send(:page_offset, 5, BASE + 3599)]
#=> [2, 2]

## page_offset never lands past the end when the set shrinks
(0..5).map { |tick| RefreshJob.send(:page_offset, 1, BASE + (tick * 1800)) }.uniq
#=> [0]

## page_offset is 0 for an empty set
RefreshJob.send(:page_offset, 0, BASE)
#=> 0

## Three consecutive ticks refresh every domain exactly once
(0..2).each { |tick| run_refresh(BASE + (tick * 1800)) }
FakeVerify.seen
#=> [%w[d5 d4], %w[d3 d2], %w[d1]]

## The fourth tick starts over from the newest page
run_refresh(BASE + (3 * 1800))
#=> %w[d5 d4]

## A rerun inside the same interval (scheduler restart) repeats the page
run_refresh(BASE + (3 * 1800) + 120)
#=> %w[d5 d4]

# Teardown
@familia.send(:alias_method, :now, :__orig_now)
@familia.send(:remove_method, :__orig_now)
Onetime::Operations.send(:remove_const, :VerifyDomain)
Onetime::Operations.const_set(:VerifyDomain, @real_verify)
@cd.send(:alias_method, :instances, :__orig_instances)
@cd.send(:alias_method, :load_multi, :__orig_load_multi)
@cd.send(:remove_method, :__orig_instances)
@cd.send(:remove_method, :__orig_load_multi)
OT.instance_variable_set(:@conf, @orig_conf)
