# try/unit/jobs/favicon_backfill_job_try.rb
#
# frozen_string_literal: true

# Onetime::Jobs::Scheduled::FaviconBackfillJob eligibility + gating (#3780 P3).
#
# Hermetic: eligible? takes a plain domain double + an explicit `now`; enabled?
# and max_attempts read OT.conf, stubbed here (attr_reader :conf, so set the
# ivar) and restored at the end. No Redis/network. Proves the full eligibility
# decision table (already-fetched / user-upload / attempt-cap / fresh-vs-stale
# vs stuck PROCESSING / backoff window) and that scheduling requires BOTH the
# backfill flag AND the favicon_fetch worker flag.

require_relative '../../support/test_helpers'
require_relative '../../../lib/onetime/jobs/scheduled/favicon_backfill_job'

BackfillJob = Onetime::Jobs::Scheduled::FaviconBackfillJob
Lifecycle   = Onetime::Jobs::Workers::JobLifecycle
NOW         = 1_000_000

# Stub OT.conf so eligible?'s max_attempts read resolves to 6 for the matrix.
@orig_conf = OT.instance_variable_get(:@conf)
OT.instance_variable_set(:@conf, {
  'jobs' => { 'favicon_backfill' => { 'max_attempts' => 6 } },
})

# Minimal CustomDomain double: eligible? reads these accessors + icon[]. The
# icon hash mirrors the real shape — a present 'filename' means an icon exists,
# and 'favicon_source' tags who wrote it — because the overwrite guard (and now
# eligible?) keys off filename presence, not favicon_source alone.
DomainStub = Struct.new(
  :favicon_fetched, :favicon_fetch_attempts, :favicon_fetch_status,
  :favicon_fetch_started_at, :favicon_fetch_next_at, :favicon_source,
  :favicon_filename,
  keyword_init: true
) do
  def icon
    h = { 'favicon_source' => favicon_source }
    h['filename'] = favicon_filename if favicon_filename
    h
  end
end

# eligible?, enabled?, and max_attempts are private class methods -> send.
def check_eligible(dom)
  BackfillJob.send(:eligible?, dom, NOW)
end

def check_enabled(backfill:, fetch:)
  saved = OT.instance_variable_get(:@conf)
  OT.instance_variable_set(:@conf, {
    'jobs' => {
      'favicon_backfill' => { 'enabled' => backfill },
      'favicon_fetch'    => { 'enabled' => fetch },
    },
  })
  BackfillJob.send(:enabled?)
ensure
  OT.instance_variable_set(:@conf, saved)
end

## eligibility decision table — one row per rule, evaluated in one shot
[
  check_eligible(DomainStub.new),                                               # baseline: no icon => eligible
  check_eligible(DomainStub.new(favicon_fetched: true)),                        # already stored
  check_eligible(DomainStub.new(favicon_source: 'user_upload',
                                favicon_filename: 'logo.png')),                 # user upload protected
  check_eligible(DomainStub.new(favicon_filename: 'old.ico')),                  # legacy untagged icon: no churn
  check_eligible(DomainStub.new(favicon_fetch_attempts: 6)),                    # at attempt cap
  check_eligible(DomainStub.new(favicon_fetch_attempts: 5)),                    # under cap
  check_eligible(DomainStub.new(favicon_fetch_status: Lifecycle::PROCESSING,
                                favicon_fetch_started_at: NOW)),                # fresh in-flight
  check_eligible(DomainStub.new(favicon_fetch_status: Lifecycle::PROCESSING,
                                favicon_fetch_started_at: NOW - 4000)),         # stale processing
  check_eligible(DomainStub.new(favicon_fetch_status: Lifecycle::PROCESSING)),  # stuck: no started_at
  check_eligible(DomainStub.new(favicon_fetch_next_at: NOW + 10_000)),          # backoff pending
  check_eligible(DomainStub.new(favicon_fetch_next_at: NOW - 10)),              # backoff elapsed
]
#=> [true, false, false, false, false, true, false, true, true, false, true]

## scheduling requires BOTH the backfill flag AND the worker flag
[
  check_enabled(backfill: true,  fetch: true),
  check_enabled(backfill: true,  fetch: false),
  check_enabled(backfill: false, fetch: true),
  check_enabled(backfill: false, fetch: false),
]
#=> [true, false, false, false]

## Restore the process-global OT.conf for sibling tryouts
OT.instance_variable_set(:@conf, @orig_conf)
OT.instance_variable_get(:@conf).equal?(@orig_conf)
#=> true
