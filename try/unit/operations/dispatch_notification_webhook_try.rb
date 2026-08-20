# try/unit/operations/dispatch_notification_webhook_try.rb
#
# frozen_string_literal: true

# Unit coverage for the SSRF-pinned webhook path of
# Onetime::Operations::DispatchNotification (via_webhook channel).
#
# Hermetic: the shared egress guard's DNS seam (Onetime::Http::Guard
# .resolve_addresses) and Net::HTTP.new are both redefined on their
# singletons and restored in the teardown at the bottom, so NO real DNS or
# network is touched and no OT.boot! / Redis is required.
#
# Proves: a blocked resolution (loopback-only or split RRset) is classified
# as a permanent :error by dispatch_to_channel's StandardError rescue —
# Guard::Blocked propagates out of send_webhook_request untranslated — and
# NO Net::HTTP connection object is ever built; an allowed resolution
# constructs Net::HTTP with the explicit nil p_addr (environment-proxy
# pickup disabled so http_proxy cannot bypass pinning) and pins the dial to
# the validated IP via #ipaddr= while keeping the hostname for Host/SNI;
# scheme validation happens BEFORE resolution (ftp:// raises ArgumentError
# without a DNS lookup).
#
# Run:
#   bundle exec try --agent try/unit/operations/dispatch_notification_webhook_try.rb

require_relative '../../support/test_helpers'
require_relative '../../../lib/onetime/operations/dispatch_notification'

DNW_OP    = Onetime::Operations::DispatchNotification
DNW_GUARD = Onetime::Http::Guard

# Stubbed DNS: host => resolved addresses. Unknown hosts resolve to [].
DNW_DNS = {
  'hook.test'  => ['203.0.113.10'],
  'inner.test' => ['127.0.0.1'],
  'split.test' => ['203.0.113.10', '10.0.0.5'], # one public + one private
}.freeze

# Records how often resolution is attempted (proves scheme-first ordering).
DNW_STATE = { resolves: 0, instances: [] }

class << DNW_GUARD
  alias_method :__dnw_orig_resolve_addresses, :resolve_addresses
  def resolve_addresses(host)
    DNW_STATE[:resolves] += 1
    DNW_DNS.fetch(host) { [] }
  end
end

# Recorder stand-in for a Net::HTTP connection; implements only what
# send_webhook_request touches and never dials anything.
class DnwFakeHttp
  attr_reader :new_args, :calls

  def initialize(*args)
    @new_args = args
    @calls    = {}
  end

  %i[ipaddr use_ssl verify_mode verify_hostname open_timeout read_timeout].each do |name|
    define_method(:"#{name}=") { |value| @calls[name] = value }
  end

  def use_ssl?
    @calls[:use_ssl]
  end

  def request(req)
    @calls[:request] = req
    Net::HTTPOK.new('1.1', '200', 'OK')
  end
end

class << Net::HTTP
  alias_method :__dnw_orig_new, :new
  def new(*args)
    fake = DnwFakeHttp.new(*args)
    DNW_STATE[:instances] << fake
    fake
  end
end

def dnw_dispatch(webhook_url)
  DNW_STATE[:instances].clear
  op = DNW_OP.new(data: {
    type: 'secret.viewed',
    addressee: { webhook_url: webhook_url },
    template: 'secret_viewed',
    channels: ['via_webhook'],
    data: {},
  },)
  op.call
end

## Allowed resolution delivers successfully
dnw_dispatch('https://hook.test/notify')
#=> { via_webhook: :success }

## Allowed resolution dials through exactly one connection, constructed with
## the hostname (Host/SNI/cert checks), the URI port, and the explicit nil
## p_addr that disables environment-proxy pickup
DNW_STATE[:instances].map(&:new_args)
#=> [['hook.test', 443, nil]]

## Allowed resolution pins the dial to the validated IP and enables TLS
http = DNW_STATE[:instances].first
[http.calls[:ipaddr], http.calls[:use_ssl], http.calls[:verify_mode] == OpenSSL::SSL::VERIFY_PEER, http.calls[:verify_hostname]]
#=> ['203.0.113.10', true, true, true]

## The request itself is a JSON POST
req = DNW_STATE[:instances].first.calls[:request]
[req.class, req['Content-Type']]
#=> [Net::HTTP::Post, 'application/json']

## Guard::Blocked propagates untranslated out of send_webhook_request; the
## channel rescue classifies it as a permanent :error (never retried — the
## worker's with_retry only sees exceptions, and per-channel failures are
## swallowed into the results hash)
dnw_dispatch('https://inner.test/notify')
#=> { via_webhook: :error }

## Blocked resolution never builds a connection object
DNW_STATE[:instances]
#=> []

## Split RRset (one public + one private answer) is blocked wholesale
dnw_dispatch('https://split.test/notify')
#=> { via_webhook: :error }

## ...and likewise attempts no connection
DNW_STATE[:instances]
#=> []

## Unresolvable host fails closed as :error, no connection attempt
[dnw_dispatch('https://unknown.test/notify'), DNW_STATE[:instances]]
#=> [{ via_webhook: :error }, []]

## Scheme validation runs BEFORE resolution: ftp:// raises ArgumentError
## without a single DNS lookup
before = DNW_STATE[:resolves]
result = begin
  DNW_OP.new(data: {}).send(:send_webhook_request, 'ftp://hook.test/x', {})
rescue ArgumentError
  :argument_error
end
[result, DNW_STATE[:resolves] - before]
#=> [:argument_error, 0]

# Teardown: restore the singletons so sibling tryouts in a directory run see
# the real implementations (this dir shares one process across files).
class << Net::HTTP
  remove_method :new
  alias_method :new, :__dnw_orig_new
  remove_method :__dnw_orig_new
end

class << DNW_GUARD
  remove_method :resolve_addresses
  alias_method :resolve_addresses, :__dnw_orig_resolve_addresses
  remove_method :__dnw_orig_resolve_addresses
end
