#!/usr/bin/env ruby
# scripts/billing-docs-generate.rb
#
# Standalone billing docs generator — bypasses bin/ots and the full app
# boot so it runs in seconds instead of 30+ on shared-CPU instances.
#
# Only requires: yaml, erb, fileutils, config_resolver, billing/config.
# No Familia, Redis, Rack, Truemail, or any heavy gem.
#
# Usage:
#   bundle exec ruby scripts/billing-docs-generate.rb [--output PATH]
#
# frozen_string_literal: true

require 'bundler/setup'

base_path = File.expand_path('..', __dir__)

# Minimal Onetime module — just enough for ConfigResolver
module Onetime
  HOME = base_path unless defined?(HOME)

  module Utils; end
end

require_relative '../lib/onetime/utils/config_resolver'
require_relative '../apps/web/billing/docs_renderer'

output_path = nil
ARGV.each_with_index do |arg, idx|
  output_path = ARGV[idx + 1] if arg == '--output' && ARGV[idx + 1]
end

kwargs = {}
kwargs[:output_path] = output_path if output_path

begin
  result = Billing::DocsRenderer.generate_and_write(**kwargs)
  exit(result ? 0 : 0) # nil (skipped) is also success
rescue Psych::SyntaxError => ex
  warn "YAML syntax error in billing config: #{ex.message}"
  exit 1
rescue StandardError => ex
  warn "Error generating billing docs: #{ex.message}"
  exit 1
end
