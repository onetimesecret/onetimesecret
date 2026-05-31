#!/usr/bin/env ruby
# scripts/generate_billing_docs.rb
#
# frozen_string_literal: true

# Boot-free billing docs generator.
#
# Regenerates apps/web/billing/docs/plan-definitions.md from billing.yaml
# WITHOUT booting the app. It deliberately does NOT `require 'onetime'` or
# `require 'onetime/cli'` — those pull in bundler/setup, Familia, Redis, the
# model layer, and auth config, none of which a pure YAML → markdown
# transform needs. This is why a contributor / CI job / dev container with
# only Ruby + stdlib (no etc/auth.yaml, no Redis, no full boot) can run it:
#
#   ruby scripts/generate_billing_docs.rb [--output PATH]
#
# It mirrors `bin/ots billing catalog generate-docs` (which delegates to the
# same Billing::Operations::Catalog::DocsGenerator module) so the output is
# identical. When billing.yaml is absent it prints an informational line and
# exits 0 — fresh checkouts and the `predev` hook depend on this no-op.

require 'optparse'

repo_root = File.expand_path('..', __dir__)
require File.join(repo_root, 'apps', 'web', 'billing', 'operations', 'catalog', 'docs_generator')

DocsGenerator = Billing::Operations::Catalog::DocsGenerator

options = { output: nil }
OptionParser.new do |opts|
  opts.banner = 'Usage: ruby scripts/generate_billing_docs.rb [--output PATH]'
  opts.on('--output PATH', 'Output file path (default: apps/web/billing/docs/plan-definitions.md)') do |path|
    options[:output] = path
  end
end.parse!(ARGV)

# Resolve billing.yaml without Onetime::Utils::ConfigResolver so we stay
# boot-free. Same resolution order: explicit env override, project-local
# etc/billing.yaml, then the shipped defaults. (defaults/billing.defaults.yaml
# is not shipped today, but resolving it keeps parity with the CLI path.)
candidates = [
  ENV['ONETIME_BILLING_CONFIG'],
  File.join(repo_root, 'etc', 'billing.yaml'),
  File.join(repo_root, 'etc', 'defaults', 'billing.defaults.yaml'),
].compact
catalog_path = candidates.find { |path| File.exist?(path) }

output_path = options[:output] ||
  File.join(repo_root, DocsGenerator::DEFAULT_OUTPUT_PATH)

if catalog_path.nil?
  # Informational, not an error: fresh checkouts and standalone deployments
  # without billing configured skip cleanly. The `predev` hook depends on
  # this graceful no-op.
  puts '[billing catalog generate-docs] skipped: billing.yaml not configured'
  exit 0
end

begin
  puts "Loading catalog: #{catalog_path}"

  catalog      = DocsGenerator.load_catalog(catalog_path)
  entitlements = DocsGenerator.entitlements_from(catalog)
  puts "Loaded #{entitlements.size} entitlements from billing config"

  markdown = DocsGenerator.write(catalog, output_path, entitlements: entitlements)

  puts "✅ Documentation generated: #{output_path}"
  puts "   #{markdown.lines.count} lines, #{markdown.bytesize} bytes"
rescue Psych::SyntaxError => ex
  warn "❌ YAML syntax error: #{ex.message}"
  exit 1
rescue StandardError => ex
  warn "❌ Error generating docs: #{ex.message}"
  warn ex.backtrace.first(5).join("\n") if ENV['ONETIME_DEBUG'] == 'true'
  exit 1
end
