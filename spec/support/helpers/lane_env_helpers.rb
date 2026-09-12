# spec/support/helpers/lane_env_helpers.rb
#
# frozen_string_literal: true

# Lane environment contract
# =========================
#
# Integration specs run inside a LANE: one rake task, one process, one fixed
# environment (lib/tasks/spec.rake). A spec may rely on everything its lane
# sets and on nothing else. The full-mode lane (spec:integration:full) sets:
#
#   RACK_ENV=test  AUTHENTICATION_MODE=full  AUTH_DATABASE_URL=sqlite::memory:
#   ORGS_SSO_ENABLED=true  --tag ~postgres_database
#
# A bare `bundle exec rspec spec/integration/full/...` is NOT a lane. Whatever
# the shell happens to export is what the spec gets, and a spec that needs a
# lane-provided setting then fails in a way that looks like a product bug
# (an SSO route answers 404, which a gate test reads as "not 401, passed" or
# "401, failed"). This helper turns that into a loud, named failure.
#
# Usage: tag the narrowest example or group that needs the setting with
# `lane_env:`; the hook below fails the example before it runs when the
# process was not started with that environment.
#
#   it 'reaches the SSO callback', lane_env: { 'ORGS_SSO_ENABLED' => 'true' } do
#   describe 'SSO routes', lane_env: { 'ORGS_SSO_ENABLED' => 'true' } do
#
# It asserts against ENV, not against the app's config objects, because the
# lane is the thing being checked: the contract is "the process was started
# the way the lane starts it", not "some spec stubbed the config to match".
module LaneEnv
  # The rake task that provides each setting, for the error message.
  LANES = {
    'ORGS_SSO_ENABLED' => 'spec:integration:full',
    'AUTH_MFA_ENABLED' => 'spec:integration:full:mfa',
  }.freeze

  class MissingLaneEnv < StandardError; end

  extend self

  # Raise unless every expected ENV pair is present with the expected value.
  #
  # @param expected [Hash{String => String}] ENV name => required value
  # @raise [MissingLaneEnv] naming the missing settings and the lane to run
  def require!(expected)
    missing = expected.reject { |name, value| ENV[name] == value }
    return if missing.empty?

    lanes   = missing.keys.map { |name| LANES.fetch(name, 'the lane in lib/tasks/spec.rake') }.uniq
    details = missing.map { |name, value| "#{name}=#{value} (got #{ENV[name].inspect})" }.join(', ')
    raise MissingLaneEnv,
      "This spec relies on lane-provided environment: #{details}. " \
      "Run it through its lane (bundle exec rake #{lanes.join(' / ')}) " \
      'rather than bare rspec; see spec/support/helpers/lane_env_helpers.rb.'
  end
end

RSpec.configure do |config|
  # Group metadata is inherited by its examples, so a `lane_env:` tag on a
  # describe block covers every example under it.
  #
  # An `around` hook, not `before`: the check must raise OUTSIDE the
  # before/after pair. spec_helper's before(:each) snapshots OT global state
  # and its after(:each) restores it; a raise from a config-level before hook
  # registered ahead of that snapshot skips the save but not the restore,
  # which writes nil over OT.conf and fails every later example in the
  # process. Around hooks wrap both, so raising here runs neither.
  config.around do |example|
    expected = example.metadata[:lane_env]
    LaneEnv.require!(expected) if expected
    example.run
  end
end
