# lib/onetime/middleware/cookie_tossing.rb
#
# frozen_string_literal: true

require 'rack/protection'

require_relative '../../middleware/detect_host'

module Onetime
  module Middleware
    # Rack::Protection::CookieTossing bound to the application's session cookie
    # and given per-request state (#4466, RISK-2026-08-14-COOKIE-TOSSING).
    #
    # What the gem does (rack-protection 4.2.1, cookie_tossing.rb): `accepts?`
    # parses the raw Cookie header with `Rack::Utils.parse_query(header, ';,')`
    # and refuses the request when the session cookie NAME appears more than
    # once, or appears percent-encoded (`Rack::Utils.unescape(k) ==
    # session_key`). The reaction is `deny`: a 403 with a text/plain
    # "Forbidden" body, and the response carries a Set-Cookie clearing the
    # offending name for every prefix of the request path, with the request
    # host as the cookie domain (`empty_cookie`: value '', domain, path,
    # expires Time.at(0)). The downstream app never runs. A request with one
    # session cookie passes through unchanged.
    #
    # That clear alone is host-scoped, and a tossed cookie is by nature set
    # with a parent `Domain=` attribute (the sibling host can set nothing
    # else that this host would receive), so the gem's clear would leave the
    # planted cookie in place and the browser blocked with 403 until it
    # expired. #remove_bad_cookies below therefore also emits the same empty
    # cookie for every parent domain of the request host that has at least
    # two labels (`eu.example.com` clears `example.com` too; `a.b.example.com`
    # clears `b.example.com` and `example.com`), for the same path prefixes.
    # One refused request clears both the planted cookie and the legitimate
    # host cookie; the next request carries no session cookie, gets a fresh
    # session, and the user signs in again. That is the recovery path. It is
    # not public-suffix aware on purpose: a browser ignores a Set-Cookie whose
    # Domain is a public suffix, so emitting one is harmless, and a suffix
    # list is not worth carrying for it. IP-literal and single-label hosts
    # get the host clear only. Nothing is widened: cookies are cleared only
    # on a response that already refuses the request.
    #
    # The request host here is the one Rack::DetectHost resolved, the host
    # the browser addressed, and Rack's own host only when nothing was
    # detected (localhost, an IP literal). Behind a proxy that rewrites
    # `Host` to its origin target, Rack's host is that target, and a clear
    # scoped to it never reaches the browser's cookies.
    #
    # Two things the stock class needs from us:
    #
    # 1. The cookie name. The gem's `session_key` option shares its name with
    #    Base's env-key option and defaults to 'rack.session', but here it
    #    means the COOKIE name. Ours is `site.session.key`, the value
    #    MiddlewareStack hands Onetime::Session, so it is read from the same
    #    accessor (Onetime.session_config) and the two cannot disagree.
    #
    # 2. Malformed cookie names. The gem compares every OTHER cookie's name
    #    percent-decoded (`Rack::Utils.unescape(k) == session_key`), and
    #    `Rack::Utils.unescape` raises ArgumentError on an invalid escape such
    #    as a bare `%`. A stray `%=x` cookie from some other application on
    #    the host would turn every request into a 500. Here a name that
    #    cannot be decoded is simply not the session key: the request is
    #    neither refused nor failed, the same as any other unrelated cookie.
    #
    # 3. Per-request state. The gem memoizes `bad_cookies` on the middleware
    #    instance (`@bad_cookies ||= []`) and never clears it, and `accepts?`
    #    answers `bad_cookies.empty?`. Rack builds one instance per app, so
    #    after the first refused request every later request through that
    #    process would be refused too, whatever its cookies: one request with
    #    two session cookies would take the process down until restart. The
    #    list is not thread-safe under Puma either. Each request therefore
    #    runs on a copy of the instance that starts with an empty list.
    #
    # Where it runs: in the universal stack directly above Onetime::Session
    # (lib/onetime/application/middleware_stack.rb), so a refused request
    # never loads or commits a session. Mounted below the session middleware
    # (inside Onetime::Middleware::Security, until the #4223 review), the
    # refusal ran after Rack had picked the first of the repeated values and
    # the session it named was loaded; the commit on the way back out then
    # set that session's cookie again, after the clears. A browser applies
    # Set-Cookie in order, so it kept the first cookie's session as its host
    # cookie: a planted cookie sent first (a longer Path sorts it ahead)
    # survived the refusal meant to remove it.
    class CookieTossing < Rack::Protection::CookieTossing
      # The cookie name when Onetime.session_config cannot be asked (a
      # standalone unit context). Same literal as Onetime::Session's default
      # and boot.rb's SESSION_DEFAULTS.
      DEFAULT_SESSION_KEY = 'onetime.session'

      # The gem's own #call, kept reachable under another name so the
      # per-request copy can run it.
      alias call_once call
      protected :call_once

      def initialize(app, options = {})
        options                 = options.dup
        options[:session_key] ||= configured_session_key
        super
      end

      def call(env)
        per_request = dup
        per_request.instance_variable_set(:@bad_cookies, [])
        per_request.call_once(env)
      end

      # The gem's check (rack-protection 4.2.1 cookie_tossing.rb#accepts?)
      # with the decode made safe; see point 2 above.
      def accepts?(env)
        cookies = Rack::Utils.parse_query(env['HTTP_COOKIE'], ';,') { |s| s }
        cookies.each do |k, v|
          if (k == session_key && Array(v).size > 1) ||
             (k != session_key && decoded_name(k) == session_key)
            bad_cookies << k
          end
        end
        bad_cookies.empty?
      end

      # The gem's clear (host-scoped, one per path prefix) plus the same clear
      # for each parent domain of the request host; see the class comment.
      def remove_bad_cookies(request, response)
        return if bad_cookies.empty?

        paths = cookie_paths(request.path)
        host  = clear_host(request)
        [host, *parent_domains(host)].each do |domain|
          bad_cookies.each do |name|
            paths.each { |path| response.set_cookie(name, empty_cookie(domain, path)) }
          end
        end
      end

      # The host Rack::DetectHost resolved, or Rack's host when it resolved
      # none; see the class comment.
      #
      # @param request [Rack::Request]
      # @return [String, nil]
      def clear_host(request)
        detected = request.get_header(Rack::DetectHost.result_field_name).to_s
        detected.empty? ? request.host : detected
      end

      # Every proper suffix of `host` with at least two labels, longest first.
      # Empty for an IP literal (v4 or v6) and for a single-label host.
      #
      # @param host [String, nil]
      # @return [Array<String>]
      def parent_domains(host)
        name = host.to_s.downcase.delete_suffix('.')
        return [] if name.empty? || name.include?(':') || name.match?(/\A[0-9.]+\z/)

        labels = name.split('.')
        return [] if labels.size < 3 || labels.any?(&:empty?)

        (1..(labels.size - 2)).map { |i| labels[i..].join('.') }
      end

      private

      # nil for a name that is not valid percent-encoding: never the session key.
      def decoded_name(name)
        Rack::Utils.unescape(name)
      rescue ArgumentError
        nil
      end

      def configured_session_key
        key = Onetime.session_config['key'] if Onetime.respond_to?(:session_config)
        key.to_s.empty? ? DEFAULT_SESSION_KEY : key
      rescue StandardError
        DEFAULT_SESSION_KEY
      end
    end
  end
end
