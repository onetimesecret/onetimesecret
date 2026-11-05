# lib/onetime/utils/client_ip.rb
#
# frozen_string_literal: true

module Onetime
  module Utils
    # Predicates over the client-IP state otto's IPPrivacyMiddleware leaves in
    # the Rack env. Shared by every fallback that would otherwise re-resolve
    # the client from REMOTE_ADDR (auth strategies, the admin network gate, the
    # full-mode signup hook), so they agree on one reading of the marker.
    module ClientIp
      # True when IPPrivacyMiddleware ran on this env and found no client IP.
      #
      # otto 2.13 (delano/otto#292): in filter mode the trusted-proxy walk
      # stops at the first X-Forwarded-For entry that is not an address
      # (`unknown`, an empty field, a CIDR) and the request has no client IP.
      # That pass leaves env['otto.client_ip'] absent, deletes the forwarded
      # address headers, and installs a fail-closed env['otto.ip_match']
      # together with env['otto.peer_relayed']. Every pass writes
      # otto.peer_relayed before resolving, so the pair is the marker of a
      # prior pass; otto.ip_match alone may be a stub. The same guard
      # Otto::Request#client_ipaddress applies.
      #
      # Re-resolving on this path sees only REMOTE_ADDR, which after the
      # middleware is the proxy, unmasked: a caller that treats a missing
      # otto.client_ip as "resolve it myself" must check this first.
      #
      # @param env [Hash] Rack environment
      # @return [Boolean]
      def self.no_client_ip_marker?(env)
        env.key?('otto.ip_match') && env.key?('otto.peer_relayed')
      end
    end
  end
end
