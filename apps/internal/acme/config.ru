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

onetime_home = ENV.fetch('ONETIME_HOME')
lib_path     = File.join(onetime_home, 'lib')
$LOAD_PATH.unshift(lib_path) unless $LOAD_PATH.include?(lib_path)

require 'onetime'

Onetime.boot! :app

# Load the ACME application directly (bypasses the registry which may
# skip it when features.domains.acme.enabled is false).
require File.join(onetime_home, 'apps', 'internal', 'acme', 'application')

# Set HOST and PORT from config so rackup binds accordingly.
# CLI flags (-o, -p) and env vars still override these.
host = ENV['HOST'] ||= OT.conf.dig('features', 'domains', 'acme', 'listen_address') || '127.0.0.1'
port = ENV['PORT'] ||= (OT.conf.dig('features', 'domains', 'acme', 'port') || '12020').to_s

Onetime.app_logger.info "Starting standalone ACME endpoint on #{host}:#{port}"

run Internal::ACME::Application.new
