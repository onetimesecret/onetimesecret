# try/unit/config/jobs_config_defaults_try.rb
#
# frozen_string_literal: true

# Regression net for issue #3775: inlining the JOBS_* env-var defaults.
#
# The `jobs:` block in etc/defaults/config.defaults.yaml had 35 ENV['JOBS_*']
# ERB interpolations. 3 are KEEPERS (real toggles left as env wiring); the other
# 32 were inlined to their literal fallback value because nothing outside the
# YAML ever read those env vars.
#
# This tryout pins the resolved `jobs:` values so the inline literals stay
# byte-equivalent to the ERB fallbacks they replaced. If someone later edits a
# default or reintroduces an interpolation with a different fallback, this fails.
#
# NOTE: we load the defaults file DIRECTLY by explicit path rather than reading
# OT.conf['jobs']. In :test mode OT.conf is the defaults deep-merged with
# spec/config.test.yaml, and that test file overrides several jobs keys
# (dlq_consumer_enabled -> false, channel_pool_size -> 1,
# maintenance.housekeeping.cron -> nil). Passing an explicit path to
# Onetime::Config.load skips the defaults-layer merge (see Config.load docs),
# so we assert the pure defaults file under a clean environment.

require_relative '../../support/test_helpers'

# Guarantee a clean environment: strip any JOBS_* overrides so the assertions
# reflect the defaults file's ERB fallbacks, not a leaked CI/shell value.
ENV.keys.grep(/\AJOBS_/).each { |key| ENV.delete(key) }

@defaults_path = File.expand_path(File.join(Onetime::HOME, 'etc', 'defaults', 'config.defaults.yaml'))
@jobs = Onetime::Config.load(@defaults_path)['jobs']


## Loads the jobs block from the defaults file
@jobs.class
#=> Hash

## KEEPERS resolve to their unset-env defaults
[@jobs['enabled'], @jobs['fallback_to_sync'], @jobs['scheduler']['enabled']]
#=> [false, true, false]

## Top-level inlined scalars (dlq_consumer_enabled is TRUE, not false)
[@jobs['plan_cache_refresh_enabled'], @jobs['catalog_retry_enabled'], @jobs['dlq_consumer_enabled']]
#=> [false, false, true]

## domain_refresh block matches inlined defaults
@jobs['domain_refresh']
#=> {"enabled"=>false, "check_interval"=>"30m", "batch_size"=>200, "rate_limit"=>0.5}

## expiration_warnings block matches inlined defaults
@jobs['expiration_warnings']
#=> {"enabled"=>false, "check_interval"=>"1h", "warning_hours"=>24, "min_ttl_hours"=>48, "batch_size"=>100}

## maintenance master toggle is off by default
@jobs['maintenance']['enabled']
#=> false

## maintenance.phantom_cleanup matches inlined defaults
@jobs['maintenance']['phantom_cleanup']
#=> {"enabled"=>false, "interval"=>"1h", "batch_size"=>500, "auto_repair"=>false}

## maintenance.data_audit matches inlined defaults
@jobs['maintenance']['data_audit']
#=> {"enabled"=>false, "interval"=>"6h", "sample_size"=>100}

## maintenance.participation_gc matches inlined defaults
@jobs['maintenance']['participation_gc']
#=> {"enabled"=>false, "cron"=>"0 5 * * *", "batch_size"=>500, "auto_repair"=>false}

## maintenance.index_rebuild matches inlined defaults
@jobs['maintenance']['index_rebuild']
#=> {"enabled"=>false, "cron"=>"0 4 * * *", "auto_repair"=>false}

## maintenance.instances_rebuild matches inlined defaults
@jobs['maintenance']['instances_rebuild']
#=> {"enabled"=>false, "cron"=>"0 3 * * 0", "auto_repair"=>false}

## maintenance.housekeeping matches inlined defaults
@jobs['maintenance']['housekeeping']
#=> {"enabled"=>false, "cron"=>"0 2 * * *"}
