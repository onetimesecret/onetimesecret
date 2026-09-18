# try/unit/jobs/domain_refresh_job_try.rb
#
# frozen_string_literal: true

# Onetime::Jobs::Scheduled::DomainRefreshJob page walk + DNS propagation warm-up.
#
# The job used to take the newest batch_size domains on every run, so any
# domain past the first batch never refreshed. It now derives one page per run
# from the clock (whole intervals since the epoch, modulo the page count), so
# the walk covers the full set with no persisted position. On top of that, any
# domain created inside `dns_propagation_window` that is still not fully
# verified gets re-checked every cycle so early DNS propagation is caught
# without waiting for the walk.
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
  'jobs' => { 'domain_refresh' => {
    'enabled' => true, 'batch_size' => 2, 'rate_limit' => 0,
    'check_interval' => '30m', 'dns_propagation_window' => '24h'
  } },
))

# Newest-first id list, as revrangeraw would return it.
IDS = %w[d5 d4 d3 d2 d1].freeze

FakeDomain = Struct.new(:identifier, :verified, :resolving)

# All fake domains are unverified/unresolving by default so the warm-up cohort
# picks up whichever ids fall inside the score window.
FAKE_DOMAINS = IDS.each_with_object({}) { |id, h| h[id] = FakeDomain.new(id, false, false) }

class FakeInstances
  # Scores are epoch-second creation times. Newest (d5) at BASE; each older
  # domain 6h earlier so the 24h warm-up window catches exactly d5..d2.
  SCORES = {
    'd5' => 0, 'd4' => -21_600, 'd3' => -43_200, 'd2' => -64_800, 'd1' => -86_401
  }.freeze

  def initialize(base) = @base = base
  def element_count    = IDS.size
  def revrangeraw(start, stop) = IDS[start..stop] || []
  def rangebyscoreraw(min, max)
    IDS.select { |id| s = @base + SCORES[id]; s >= min && s <= max }.reverse
  end
end

class FakeVerify
  class << self
    attr_accessor :seen
  end
  self.seen = []

  def initialize(domains:, **) = @domains = domains

  def call
    self.class.seen << @domains.map(&:identifier)
    Onetime::Operations::VerifyDomain::BulkResult.new(
      total: @domains.size, verified_count: 0, failed_count: 0,
      skipped_count: 0, results: [], duration_seconds: 0.0
    )
  end
end

# Tick 0 of a 3-page cycle: 1800s intervals, 5 domains, 2 per page.
BASE = 1800 * 3 * 1000

@cd = Onetime::CustomDomain.singleton_class
@cd.send(:alias_method, :__orig_instances, :instances)
@cd.send(:alias_method, :__orig_load_multi, :load_multi)
@cd.send(:define_method, :instances) { FakeInstances.new(BASE) }
@cd.send(:define_method, :load_multi) { |ids| ids.map { |id| FAKE_DOMAINS[id] } }

@real_verify = Onetime::Operations::VerifyDomain
Onetime::Operations.send(:remove_const, :VerifyDomain)
Onetime::Operations.const_set(:VerifyDomain, FakeVerify)
FakeVerify.const_set(:BulkResult, @real_verify::BulkResult)

@familia = Familia.singleton_class
@familia.send(:alias_method, :__orig_now, :now)

def run_refresh(now)
  @familia.send(:define_method, :now) { now }
  RefreshJob.send(:refresh_domains)
  FakeVerify.seen.last
end

def with_config(overrides)
  restore = Marshal.load(Marshal.dump(OT.instance_variable_get(:@conf)))
  merged  = Marshal.load(Marshal.dump(restore))
  merged['jobs']['domain_refresh'].merge!(overrides)
  OT.instance_variable_set(:@conf, merged)
  yield
ensure
  OT.instance_variable_set(:@conf, restore)
end

## schedule registers the job with overlap protection on a real scheduler
@scheduler = Rufus::Scheduler.new
RefreshJob.schedule(@scheduler)
@scheduled = @scheduler.jobs.first
[@scheduler.jobs.size, @scheduled.opts[:overlap], @scheduled.original]
#=> [1, false, '30m']

## A tick that fires while the previous run is still working is skipped
@runs    = 0
@release = Queue.new
@started = Queue.new
@overlap_job = @scheduler.schedule_every('1h', overlap: false, first_in: '1h') do
  @runs += 1
  @started << true
  @release.pop
end
@overlap_job.trigger(Time.now)
@started.pop
@overlap_job.trigger(Time.now) # previous run still holds the job
@release << true
sleep 0.05 until @overlap_job.running? == false
@runs
#=> 1

## schedule registers nothing when the job is disabled
@scheduler.shutdown(:kill)
@scheduler = Rufus::Scheduler.new
with_config('enabled' => false) { RefreshJob.schedule(@scheduler) }
count = @scheduler.jobs.size
@scheduler.shutdown(:kill)
count
#=> 0

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

## dns_propagation_window parses the configured rufus duration
RefreshJob.send(:dns_propagation_window_seconds)
#=> 86_400

## Warm-up adds unverified domains inside the window that the page missed
FakeVerify.seen.clear
run_refresh(BASE)
#=> %w[d5 d4 d2 d3]

## Warm-up excludes fully-verified domains even if they are inside the window
FAKE_DOMAINS['d3'] = FakeDomain.new('d3', true, true)
FakeVerify.seen.clear
run_refresh(BASE)
FAKE_DOMAINS['d3'] = FakeDomain.new('d3', false, false)
FakeVerify.seen.last
#=> %w[d5 d4 d2]

## Warm-up de-dupes against the page so a domain is never checked twice per run
FakeVerify.seen.clear
run_refresh(BASE + 1800)
FakeVerify.seen.last
#=> %w[d3 d2 d4 d5]

## dns_propagation_window: '0' disables the warm-up entirely
FakeVerify.seen.clear
with_config('dns_propagation_window' => '0') { run_refresh(BASE) }
FakeVerify.seen.last
#=> %w[d5 d4]

## Three consecutive ticks refresh every domain (page + warm-up combined)
FakeVerify.seen.clear
(0..2).each { |tick| run_refresh(BASE + (tick * 1800)) }
FakeVerify.seen
#=> [%w[d5 d4 d2 d3], %w[d3 d2 d4 d5], %w[d1 d2 d3 d4 d5]]

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
