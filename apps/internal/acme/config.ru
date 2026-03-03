# apps/internal/acme/config.ru
#
# frozen_string_literal: true

#
# Standalone rackup for the Internal ACME application.
#
# Use this when the ACME endpoint is NOT auto-mounted inside the main
# application process (i.e. features.domains.acme.enabled is false in
# the main config). Caddy's on-demand TLS `ask` directive should point
# at whatever address and port this process binds to.
#
# Usage:
#
#   $ rackup apps/internal/acme/config.ru
#
#   # Or with explicit host/port overrides:
#   $ rackup apps/internal/acme/config.ru -o 127.0.0.1 -p 12020
#

ENV['RACK_ENV']     ||= 'production'
ENV['ONETIME_HOME'] ||= File.expand_path('../../..', __dir__).freeze

$LOAD_PATH.unshift(File.join(ENV.fetch('ONETIME_HOME', nil), 'lib')) unless
  $LOAD_PATH.include?(File.join(ENV.fetch('ONETIME_HOME', nil), 'lib'))

require 'onetime'

Onetime.boot! :app

# Load the ACME application directly (bypasses the registry which may
# skip it when features.domains.acme.enabled is false).
require File.join(ENV.fetch('ONETIME_HOME', nil), 'apps', 'internal', 'acme', 'application')

# Set HOST and PORT from config so rackup binds accordingly.
# CLI flags (-o, -p) and env vars still override these.
ENV['HOST'] ||= OT.conf.dig('features', 'domains', 'acme', 'listen_address') || '127.0.0.1'
ENV['PORT'] ||= (OT.conf.dig('features', 'domains', 'acme', 'port') || '12020').to_s

Onetime.app_logger.info "Starting standalone ACME endpoint on #{ENV.fetch('HOST', nil)}:#{ENV.fetch('PORT', nil)}"

run Internal::ACME::Application.new
