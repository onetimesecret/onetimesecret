# try/unit/utils/client_ip_try.rb
#
# frozen_string_literal: true

# Onetime::Utils::ClientIp.from_request and NoClientIp.request_subject: the
# client IP Rodauth call sites read from a Rack request.
#
# otto 2.13 (delano/otto#292): when the trusted X-Forwarded-For walk reaches
# a non-address entry, IPPrivacyMiddleware leaves env['otto.client_ip'] absent,
# sets the otto.ip_match + otto.peer_relayed marker pair, and leaves
# REMOTE_ADDR raw (the proxy). from_request must return nil there, never the
# proxy's address.
#
# We test:
# 1. The canonical otto.client_ip wins over REMOTE_ADDR
# 2. Marker pair present: nil, not REMOTE_ADDR
# 3. otto.ip_match alone (a stub) is not the marker: falls back to request.ip
# 4. No middleware ran: request.ip
# 5. request_subject maps the marker path to the shared bucket

require 'rack'
require 'onetime/utils/client_ip'
require 'onetime/security/no_client_ip'

def ci_request(env)
  Rack::Request.new(Rack::MockRequest.env_for('/', env))
end

MARKER = { 'otto.ip_match' => ->(*) { false }, 'otto.peer_relayed' => true }.freeze

## The canonical client IP wins over REMOTE_ADDR
Onetime::Utils::ClientIp.from_request(ci_request('otto.client_ip' => '203.0.113.0', 'REMOTE_ADDR' => '10.0.0.5'))
#=> '203.0.113.0'

## Marker pair present: nil, not the proxy's raw address
Onetime::Utils::ClientIp.from_request(ci_request(MARKER.merge('REMOTE_ADDR' => '10.0.0.5')))
#=> nil

## otto.ip_match alone is not the marker: falls back to request.ip
Onetime::Utils::ClientIp.from_request(ci_request('otto.ip_match' => ->(*) { false }, 'REMOTE_ADDR' => '198.51.100.9'))
#=> '198.51.100.9'

## No middleware ran: request.ip
Onetime::Utils::ClientIp.from_request(ci_request('REMOTE_ADDR' => '198.51.100.9'))
#=> '198.51.100.9'

## request_subject keys the marker path on the shared bucket
Onetime::Security::NoClientIp.request_subject(ci_request(MARKER.merge('REMOTE_ADDR' => '10.0.0.5')))
#=> 'no-client-ip'

## request_subject passes a resolved IP through
Onetime::Security::NoClientIp.request_subject(ci_request('otto.client_ip' => '203.0.113.0'))
#=> '203.0.113.0'
