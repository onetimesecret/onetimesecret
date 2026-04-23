# try/unit/models/custom_domain_homepage_config_race_try.rb
#
# frozen_string_literal: true

# Race-condition tests for CustomDomain::HomepageConfig.find_or_create_for_domain
#
# Verifies that concurrent find_or_create_for_domain calls against the same
# domain_id produce exactly one :created outcome and one :existed outcome,
# and that the surviving record reflects the winning writer's value (not
# a silent last-write-wins overwrite of either value).
#
# Backed by Familia's save_if_not_exists! (WATCH + MULTI), which raises
# Familia::RecordExistsError when a racing writer completes first; the
# find_or_create_for_domain class method catches that and returns :existed.
#
# Pattern adapted from try/unit/models/organization_race_condition_try.rb.

require_relative '../../support/test_models'

OT.boot! :test

Familia.dbclient.flushdb
OT.info 'Cleaned Redis for HomepageConfig race-condition test run'

@ts      = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@owner   = Onetime::Customer.create!(email: "hp_race_owner_#{@ts}_#{@entropy}@test.com")
@org     = Onetime::Organization.create!("HpRace Test Org #{@ts}", @owner, "hp_race_#{@ts}@test.com")
@domain  = Onetime::CustomDomain.create!("hp-race-#{@ts}.example.com", @org.objid)

## Setup: target domain has no HomepageConfig
Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@domain.identifier)
#=> false

# --- Two concurrent writers, different proposed values ---
#
# Thread A proposes enabled=true, Thread B proposes enabled=false. Only one
# writer's value should be persisted; both threads should receive a coherent
# tuple ([config, :created] or [config, :existed]).

## Concurrent find_or_create_for_domain produces exactly one :created, one :existed
results = []
mutex   = Mutex.new
threads = []
2.times do |i|
  threads << Thread.new do
    proposed = (i == 0)
    begin
      cfg, outcome = Onetime::CustomDomain::HomepageConfig.find_or_create_for_domain(
        domain_id: @domain.identifier, enabled: proposed,
      )
      mutex.synchronize do
        results << { proposed: proposed, outcome: outcome, stored: cfg&.enabled? }
      end
    rescue StandardError => e
      mutex.synchronize { results << { proposed: proposed, error: e.class.name, msg: e.message } }
    end
  end
end
threads.each(&:join)
@results = results
created_count = @results.count { |r| r[:outcome] == :created }
existed_count = @results.count { |r| r[:outcome] == :existed }
error_count   = @results.count { |r| r.key?(:error) }
[created_count, existed_count, error_count]
#=> [1, 1, 0]

## Exactly one Redis record persisted
Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@domain.identifier)
#=> true

## Both threads' returned stored-enabled values agree (single source of truth)
@results.map { |r| r[:stored] }.uniq.size
#=> 1

## Persisted record matches the :created writer's proposed value
@winner            = @results.find { |r| r[:outcome] == :created }
@reloaded          = Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain.identifier)
@reloaded.enabled? == @winner[:proposed]
#=> true

## The :existed writer sees the winner's value, not their own proposal
@loser = @results.find { |r| r[:outcome] == :existed }
@loser[:stored] == @winner[:proposed]
#=> true

# --- Race against a pre-existing record: all writers should see :existed ---

## Setup: second domain with a pre-existing HomepageConfig(enabled=true)
@domain_pre = Onetime::CustomDomain.create!("hp-race-pre-#{@ts}.example.com", @org.objid)
Onetime::CustomDomain::HomepageConfig.upsert(domain_id: @domain_pre.identifier, enabled: true)
Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_pre.identifier).enabled?
#=> true

## Three concurrent find_or_create attempts all report :existed, none overwrite
pre_results = []
pre_mutex   = Mutex.new
pre_threads = []
3.times do
  pre_threads << Thread.new do
    _cfg, outcome = Onetime::CustomDomain::HomepageConfig.find_or_create_for_domain(
      domain_id: @domain_pre.identifier, enabled: false,
    )
    pre_mutex.synchronize { pre_results << outcome }
  end
end
pre_threads.each(&:join)
[pre_results.count(:existed), pre_results.count(:created), pre_results.size]
#=> [3, 0, 3]

## Pre-existing record's enabled=true survives unchanged
Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_pre.identifier).enabled?
#=> true

# --- Rescue-branch coverage: force the Familia::RecordExistsError path ---
#
# The tests above exercise the pre-check short-circuit at line 168-169 (both
# concurrent callers typically read nil and race, but whichever loses the
# exists?-inside-WATCH check returns via the rescue). To guarantee the rescue
# branch at lines 177-179 of homepage_config.rb executes, we stub
# find_by_domain_id to return nil on the FIRST call per thread, bypassing
# the pre-check, and pass through on subsequent calls so the re-read inside
# the rescue branch returns the persisted record.

## Setup: third domain, no HomepageConfig
@domain_rescue = Onetime::CustomDomain.create!("hp-race-rescue-#{@ts}.example.com", @org.objid)
Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@domain_rescue.identifier)
#=> false

## Rescue branch executes: stubbed pre-check forces both threads into save_if_not_exists!
hp_class         = Onetime::CustomDomain::HomepageConfig
original_find    = hp_class.method(:find_by_domain_id)
target_id        = @domain_rescue.identifier  # capture locally so the stub closure sees it
rescue_latch     = Mutex.new
rescue_ready     = ConditionVariable.new
rescue_threads_ready = 0
rescue_rescue_fired  = { count: 0 } # shared mutable tracker for rescue re-reads

# Stub: per-thread first-call returns nil, subsequent calls pass through.
# Also synchronize so both threads enter save_if_not_exists! concurrently.
hp_class.define_singleton_method(:find_by_domain_id) do |domain_id|
  if domain_id == target_id
    Thread.current[:hp_rescue_calls] ||= 0
    Thread.current[:hp_rescue_calls]  += 1
    if Thread.current[:hp_rescue_calls] == 1
      # Barrier: wait until both threads have bypassed the pre-check together,
      # so neither has written yet when both reach save_if_not_exists!
      rescue_latch.synchronize do
        rescue_threads_ready += 1
        if rescue_threads_ready >= 2
          rescue_ready.broadcast
        else
          rescue_ready.wait(rescue_latch)
        end
      end
      nil
    else
      # Subsequent calls (the re-read inside the rescue branch) — pass through.
      rescue_latch.synchronize { rescue_rescue_fired[:count] += 1 }
      original_find.call(domain_id)
    end
  else
    original_find.call(domain_id)
  end
end

rescue_results = []
rescue_mutex   = Mutex.new
rescue_threads = []
2.times do |i|
  rescue_threads << Thread.new do
    proposed = (i == 0)
    begin
      cfg, outcome = hp_class.find_or_create_for_domain(
        domain_id: @domain_rescue.identifier, enabled: proposed,
      )
      rescue_mutex.synchronize do
        rescue_results << { proposed: proposed, outcome: outcome, stored: cfg&.enabled? }
      end
    rescue StandardError => e
      rescue_mutex.synchronize { rescue_results << { proposed: proposed, error: e.class.name, msg: e.message } }
    end
  end
end
rescue_threads.each(&:join)

# Restore original method
hp_class.define_singleton_method(:find_by_domain_id) do |domain_id|
  original_find.call(domain_id)
end

@rescue_results      = rescue_results
@rescue_rescue_fired = rescue_rescue_fired[:count]
[
  @rescue_results.count { |r| r[:outcome] == :created },
  @rescue_results.count { |r| r[:outcome] == :existed },
  @rescue_results.count { |r| r.key?(:error) },
]
#=> [1, 1, 0]

## Rescue branch re-read executed for the :existed thread (not pre-check)
@rescue_rescue_fired
#=> 1

## Surviving Redis record matches the :created writer's proposed value
@rescue_winner    = @rescue_results.find { |r| r[:outcome] == :created }
@rescue_persisted = Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@domain_rescue.identifier)
@rescue_persisted.enabled? == @rescue_winner[:proposed]
#=> true

## The :existed thread (rescue branch) sees the winner's value
@rescue_loser = @rescue_results.find { |r| r[:outcome] == :existed }
@rescue_loser[:stored] == @rescue_winner[:proposed]
#=> true

# --- Nil re-read after RecordExistsError raises Onetime::Problem ---
#
# Exercises the contract-preserving raise at homepage_config.rb:
#   rescue Familia::RecordExistsError
#     found = find_by_domain_id(domain_id)
#     raise Onetime::Problem, "...vanished after conflict" unless found
#
# Simulates the case where the record existed at WATCH time (so
# save_if_not_exists! raises RecordExistsError) but has vanished by the
# time the rescue branch re-reads (concurrent destroy / eviction / teardown).
# We stub both find_by_domain_id (to always return nil so the pre-check is
# bypassed AND the rescue re-read returns nil) AND save_if_not_exists! (to
# raise RecordExistsError directly, since without a real pre-existing record
# the WATCH path would actually persist successfully).

## Setup: fourth domain for the vanish scenario
@domain_vanish = Onetime::CustomDomain.create!("hp-race-vanish-#{@ts}.example.com", @org.objid)
Onetime::CustomDomain::HomepageConfig.exists_for_domain?(@domain_vanish.identifier)
#=> false

## Stub find_by_domain_id -> nil and save_if_not_exists! -> raise, then call method
vanish_class      = Onetime::CustomDomain::HomepageConfig
@vanish_target_id  = @domain_vanish.identifier
original_v_find   = vanish_class.method(:find_by_domain_id)
vanish_class.define_singleton_method(:find_by_domain_id) do |domain_id|
  if domain_id == @vanish_target_id
    nil
  else
    original_v_find.call(domain_id)
  end
end
# Stub save_if_not_exists! on any instance of HomepageConfig to raise,
# simulating "record existed at WATCH time" without needing a real racer.
vanish_class.class_eval do
  alias_method :__orig_save_if_not_exists!, :save_if_not_exists!
  define_method(:save_if_not_exists!) do |*|
    raise Familia::RecordExistsError, "stubbed: record existed at WATCH time"
  end
end

@vanish_outcome =
  begin
    vanish_class.find_or_create_for_domain(domain_id: @vanish_target_id, enabled: true)
    :no_raise
  rescue Onetime::Problem => e
    [:raised, e.message]
  end

# Restore stubs
vanish_class.define_singleton_method(:find_by_domain_id) do |domain_id|
  original_v_find.call(domain_id)
end
vanish_class.class_eval do
  alias_method :save_if_not_exists!, :__orig_save_if_not_exists!
  remove_method :__orig_save_if_not_exists!
end

@vanish_outcome.first
#=> :raised

## Raised message mentions the vanishing condition and identifies the record
@vanish_outcome.last.include?('vanished after conflict') && @vanish_outcome.last.include?(@vanish_target_id)
#=> true

# Teardown
Familia.dbclient.flushdb
