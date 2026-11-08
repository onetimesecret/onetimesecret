# lib/onetime/security/no_client_ip.rb
#
# frozen_string_literal: true

module Onetime
  module Security
    # The rate-limit subject for a request that reached the application with
    # no client IP.
    #
    # Since otto 2.13 (delano/otto#292) the filter-mode trusted-proxy walk
    # stops at the first X-Forwarded-For entry that is not an address
    # (`unknown`, an empty field) and leaves the request with NO client IP:
    # env['otto.client_ip'] is absent and the auth strategies' metadata[:ip]
    # is nil. The value that produced that state is the one the client wrote
    # into the header, so a limiter that SKIPS a blank subject is switched off
    # by the request it is meant to cap. Before 2.13 the same request resolved
    # to the proxy's own address and shared that proxy's bucket.
    #
    # The per-IP-only limiters (account creation, anonymous secret creation,
    # feedback, V1::ControllerBase#check_rate_limit!) therefore charge every
    # IP-less request to this one shared
    # bucket. It preserves a cap without naming the proxy as the client, and
    # it is the pre-2.13 ceiling for a proxy that writes `unknown` for every
    # visitor: those requests all shared one bucket then too, keyed on the
    # proxy. Limiters with a second tier (login by email, reset by email,
    # incoming by recipient) keep skipping the IP tier, since that tier is not
    # the only cap on them.
    #
    # Operators see the bucket in the key (`...:ip:no-client-ip`), in the cap
    # log line and in the audit event target, with the pointer below.
    module NoClientIp
      # Key segment and log label for the shared bucket. Not an address on
      # purpose: it can never collide with a masked client IP.
      BUCKET = 'no-client-ip'

      # The subject a per-IP limiter keys on: the IP when there is one, the
      # shared bucket otherwise.
      #
      # @param client_ip [String, nil]
      # @return [String]
      def self.subject_for(client_ip)
        value = client_ip.to_s
        value.empty? ? BUCKET : value
      end

      # @param subject [String, nil]
      # @return [Boolean] whether subject is the shared bucket
      def self.bucket?(subject)
        subject.to_s == BUCKET
      end

      # Operator diagnostic for a cap hit on the shared bucket, appended to the
      # lockout log line (server side only). Self-contained like the
      # collapsed-IP hints beside it: it states the condition and the remedy
      # so the log line alone carries the diagnosis.
      #
      # @return [String]
      def self.bucket_hint
        '. NOTE: these requests reached the application with NO client IP: the ' \
          'X-Forwarded-For chain relayed by the trusted proxies ended in a ' \
          'non-address entry (`unknown`, an empty field), so they share this one ' \
          'bucket. Configure the proxy that writes that entry to append the real ' \
          'peer address instead (docs/deployment/trusted-proxies.md, "Client IP resolution")'
      end
    end
  end
end
