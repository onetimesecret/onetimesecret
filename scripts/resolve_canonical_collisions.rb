#!/usr/bin/env ruby
# frozen_string_literal: true

# Plan and apply which custom domain record to keep for each name collision
# that `bin/ots domains backfill-canonical-index` reports. The same operation
# as `bin/ots domains resolve-collisions`, for a release that has the backfill
# command but not that one (v0.26.17).
#
# On such a release, copy these into the application directory, then run from
# there:
#
#   scripts/resolve_canonical_collisions.rb                        (this file)
#   lib/onetime/operations/domains/collision_resolution.rb
#   lib/onetime/operations/domains/collision_resolution/*.rb
#   lib/onetime/operations/domains/remove.rb                       (keep_vhost)
#   lib/onetime/operations/domains/teardown.rb                     (keep_vhost)
#
# remove.rb and teardown.rb differ from v0.26.17 only by the keep_vhost
# option, which leaves the provider vhost up for the kept record.
#
# Usage (from the application directory, with its configuration and
# VALKEY_URL/REDIS_URL in the environment, as for bin/ots):
#
#   bundle exec ruby scripts/resolve_canonical_collisions.rb plan [--write FILE] [--json]
#   bundle exec ruby scripts/resolve_canonical_collisions.rb apply --plan FILE [--dry-run] [--yes] [--group NAME] [--json]
#
# STOP THE APPLICATION BEFORE apply, snapshot the datastore, and run
# `bin/ots domains backfill-canonical-index --apply` afterwards. Runbook:
# docs/runbooks/custom-domain-canonical-index-backfill.md, step 6. The
# rule, the plan file and the exit status are the command's; see
# `bin/ots domains resolve-collisions --help` on a release that has it, or
# the header of lib/onetime/operations/domains/collision_resolution.rb.

require 'optparse'
require 'json'

base_path = File.expand_path('..', __dir__)

ENV['ONETIME_HOME'] ||= base_path
$LOAD_PATH.unshift File.join(base_path, 'lib')
$LOAD_PATH.unshift(File.join(base_path, 'apps', 'api'))
$LOAD_PATH.unshift(File.join(base_path, 'apps', 'web'))

USAGE = 'Usage: resolve_canonical_collisions.rb plan [--write FILE] [--json] ' \
        '| apply --plan FILE [--dry-run] [--yes] [--group NAME] [--json]'

options = { write: nil, plan: nil, dry_run: false, yes: false, group: nil, json: false }
parser  = OptionParser.new do |opts|
  opts.banner = USAGE
  opts.on('--write FILE', 'plan: save the plan as JSON') { |v| options.store(:write, v) }
  opts.on('--plan FILE', 'apply: the plan file') { |v| options.store(:plan, v) }
  opts.on('--dry-run', 'apply: check and preview, write nothing') { options.store(:dry_run, true) }
  opts.on('-y', '--yes', 'apply: skip the confirmation prompt') { options.store(:yes, true) }
  opts.on('--group NAME', 'apply: one group, by canonical name') { |v| options.store(:group, v) }
  opts.on('--json', 'JSON output') { options.store(:json, true) }
  opts.on('-h', '--help') do
    puts opts
    exit
  end
end
parser.parse!

mode = ARGV.shift
unless %w[plan apply].include?(mode)
  warn USAGE
  exit 2
end

require 'onetime'
OT.boot! :cli
require 'onetime/operations/domains/collision_resolution'

op   = Onetime::Operations::Domains::CollisionResolution.new
text = Onetime::Operations::Domains::CollisionResolution::Text

def fail_with(message, json)
  puts(json ? JSON.generate({ error: message }) : "Error: #{message}")
  exit 1
end

case mode
when 'plan'
  plan = op.plan
  File.write(options[:write], "#{plan.to_json}\n") if options[:write]
  if options[:json]
    puts plan.to_json
  else
    puts text.plan(plan)
    puts "Plan written to #{options[:write]}" if options[:write]
  end
  exit(plan.attention? ? 1 : 0)
when 'apply'
  fail_with('apply requires --plan FILE', options[:json]) if options[:plan].to_s.empty?
  fail_with('refusing to apply in --json mode without --yes or --dry-run', true) if options[:json] && !options[:yes] && !options[:dry_run]

  plan = begin
    Onetime::Operations::Domains::CollisionResolution::Plan.parse(File.read(options[:plan]))
  rescue Errno::ENOENT, Errno::EACCES => ex
    fail_with("cannot read plan: #{ex.message}", options[:json])
  rescue Onetime::Operations::Domains::CollisionResolution::InvalidPlan => ex
    fail_with("invalid plan: #{ex.message}", options[:json])
  end

  unless options[:yes] || options[:dry_run]
    puts 'This permanently removes custom domain records with their configs and brand settings.'
    puts 'The provider vhost for a name stays while a record for the name is kept. The web,'
    puts 'worker and scheduler processes must be stopped, and the datastore snapshotted.'
    print 'Is the application stopped, and the plan reviewed? [y/N] '
    unless $stdin.gets&.strip&.downcase == 'y'
      puts 'Aborted. Nothing was written.'
      exit 1
    end
  end

  result = op.apply(plan, actor: 'cli', dry_run: options[:dry_run], only: options[:group])
  puts(options[:json] ? JSON.pretty_generate(result.to_h) : text.apply(result))
  exit(result.attention? ? 1 : 0)
end
