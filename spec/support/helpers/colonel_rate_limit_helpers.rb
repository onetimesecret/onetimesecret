# spec/support/helpers/colonel_rate_limit_helpers.rb
#
# frozen_string_literal: true

# Drive the colonel API rate limiters from a unit spec (#4329).
#
# spec/config.test.yaml ships `site.admin.rate_limit.enabled: false` so the
# colonel suites — many endpoints, one process, ONE acting colonel — do not
# throttle themselves. Every spec that wants a bucket ON therefore turns it on
# in-process, which is what {#stub_colonel_rate_limit} does.
#
# Like {ColonelElevationHelpers#stub_colonel_elevation} it stubs `OT.conf` with a
# DEEP COPY rather than mutating the live hash (the global after(:each) restores
# `@conf` only when `OT.conf != @__original_ot_conf`, and an in-place mutation
# compares equal to itself). It deep-copies whatever `OT.conf` currently returns,
# so calling it AFTER `stub_colonel_elevation` composes rather than clobbers.
module ColonelRateLimitHelpers
  # Replace OT.conf for this example with one whose site.admin.rate_limit block
  # says what the caller asked for. Everything else in the config is preserved.
  #
  # @param buckets [Hash{String,Symbol=>Hash}] per-bucket overrides keyed by
  #   section name ('mutation', 'destructive', 'handle_resolve', 'elevation').
  #   Values are string-keyed setting hashes, e.g. `{ 'max_attempts' => 2 }`.
  # @param enabled [Boolean] the PARENT flag, which short-circuits every bucket.
  # @return [Hash] the stubbed config
  def stub_colonel_rate_limit(enabled: true, **buckets)
    conf = YAML.load(YAML.dump(OT.conf))
    conf['site'] ||= {}
    conf['site']['admin'] ||= {}
    conf['site']['admin']['rate_limit'] = buckets
      .to_h { |section, settings| [section.to_s, stringify(settings)] }
      .merge('enabled' => enabled)
    allow(OT).to receive(:conf).and_return(conf)
    conf
  end

  # Delete every key of one colonel bucket for one subject. Call it before AND
  # after an example that writes real counters: the buckets live on the Customer
  # shard, which the integration flush hook does not necessarily reach.
  #
  # @param prefix [String] e.g. 'colonel:destructive'
  # @param subject [String] the acting colonel's extid
  def clear_colonel_bucket(prefix, subject)
    Onetime::Customer.dbclient.del("#{prefix}:attempts:#{subject}", "#{prefix}:locked:#{subject}")
  end

  private

  def stringify(settings)
    settings.to_h { |key, value| [key.to_s, value] }
  end
end

RSpec.configure do |config|
  config.include ColonelRateLimitHelpers
end
