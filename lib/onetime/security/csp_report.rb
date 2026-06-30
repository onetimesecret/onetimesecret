# lib/onetime/security/csp_report.rb
#
# frozen_string_literal: true

require 'json'
require 'uri'

module Onetime
  module Security
    # Parsing and REDACTION for inbound Content-Security-Policy violation
    # reports.
    #
    # This is a SECRET-SHARING application. A CSP violation report's URL fields
    # (document-uri, blocked-uri, referrer, source-file) routinely contain the
    # full page URL the browser was on — which for this app can be a secret link
    # such as https://host/secret/<SECRET_KEY>?... Logging those values verbatim
    # would LEAK secret tokens into logs and (if configured) Sentry. Every value
    # that reaches a log MUST therefore pass through #redact_url first, which
    # discards the query string and collapses the path so a secret key can never
    # survive into the log line.
    #
    # Layer-agnostic: no Rack/Otto dependency. The controller passes in the raw
    # request body + content-type and gets back a list of safe, structured
    # summaries ready to log.
    module CspReport
      extend self

      # Hard cap on the request body we are willing to parse. Browsers send tiny
      # JSON documents; anything larger is abuse and is skipped without parsing.
      MAX_BODY_BYTES = 64 * 1024 # 64 KiB

      # URL-ish report fields that may contain a secret token and must be
      # redacted before they are allowed anywhere near a log.
      URL_FIELDS = %w[document-uri blocked-uri referrer source-file].freeze

      # Parse a CSP report body into a list of REDACTED, log-safe summary hashes.
      #
      # Tolerates malformed/empty JSON and both wire formats. Never raises.
      #
      # @param body [String, nil] the raw request body.
      # @param content_type [String, nil] the request Content-Type header.
      # @return [Array<Hash>] zero or more redacted summaries. Empty when the
      #   body is missing, oversized, malformed, or contains no recognizable
      #   violation reports.
      def parse(body, content_type)
        return [] if body.nil?

        bytes = body.bytesize
        return [] if bytes.zero? || bytes > MAX_BODY_BYTES

        data =
          begin
            JSON.parse(body)
          rescue JSON::ParserError, EncodingError
            nil
          end
        return [] if data.nil?

        raw_reports = extract_reports(data, content_type)
        raw_reports.filter_map { |report| summarize(report) }
      end

      # Pull the per-violation hashes out of either wire format.
      #
      # Legacy 'application/csp-report': a single object {"csp-report": {...}}.
      # Reporting API 'application/reports+json': an ARRAY of
      #   {"type": "csp-violation", "body": {...}} (we tolerate other shapes too,
      #   keying off content rather than trusting the declared content-type).
      #
      # @return [Array<Hash>] raw (un-redacted) per-violation field hashes.
      def extract_reports(data, _content_type)
        case data
        when Array
          # Reporting API batch. Keep only csp-violation entries with a body.
          data.filter_map do |entry|
            next unless entry.is_a?(Hash)

            type = entry['type']
            body = entry['body']
            next unless body.is_a?(Hash)
            # Accept entries explicitly typed as csp-violation, or untyped
            # bodies that still look like a CSP report.
            next unless type.nil? || type == 'csp-violation'

            body
          end
        when Hash
          if data['csp-report'].is_a?(Hash)
            [data['csp-report']] # legacy single report
          elsif data['body'].is_a?(Hash)
            [data['body']]       # a single Reporting API object (not in an array)
          else
            []
          end
        else
          []
        end
      end

      # Reduce one raw report hash to a small, REDACTED, structured summary that
      # is safe to log. Only non-secret-bearing scalar fields survive verbatim
      # (directive names, disposition, line/column numbers, status code). Every
      # URL-ish field is collapsed via #redact_url.
      #
      # @param report [Hash] a raw per-violation field hash.
      # @return [Hash, nil] a redacted summary, or nil when the input is not a
      #   usable report hash.
      def summarize(report)
        return nil unless report.is_a?(Hash)

        {
          'violated-directive' => safe_token(report['violated-directive'] || report['violatedDirective']),
          'effective-directive' => safe_token(report['effective-directive'] || report['effectiveDirective']),
          'disposition' => safe_token(report['disposition']),
          'document-uri' => redact_url(report['document-uri'] || report['documentURL']),
          'blocked-uri' => redact_url(report['blocked-uri'] || report['blockedURL']),
          'referrer' => redact_url(report['referrer']),
          'source-file' => redact_url(report['source-file'] || report['sourceFile']),
          'line-number' => safe_int(report['line-number'] || report['lineNumber']),
          'column-number' => safe_int(report['column-number'] || report['columnNumber']),
          'status-code' => safe_int(report['status-code'] || report['statusCode']),
        }.compact
      end

      # Redact a URL-ish report value down to a form that CANNOT reveal a secret
      # token. Strategy: keep ONLY scheme + host (+ non-default port), drop the
      # query string, fragment, AND the entire path. We deliberately do NOT keep
      # even the first path segment: in this app a secret link can be as shallow
      # as https://host/<KEY> (or a custom-domain root), so any retained path
      # component risks being the secret itself. Non-URL CSP keyword sources
      # ('inline', 'eval', 'self', 'data', etc.) are passed through unchanged
      # since they carry no secret.
      #
      # Examples:
      #   https://host/secret/abc123?x=y -> "https://host/[redacted-path]"
      #   https://host/abc123            -> "https://host/[redacted-path]"
      #   https://host/                  -> "https://host/"
      #   inline                         -> "inline"
      #   data                           -> "data"
      #
      # @param value [Object] the raw field value.
      # @return [String, nil] a redacted string, or nil when value is blank.
      def redact_url(value)
        return nil if value.nil?

        str = value.to_s
        return nil if str.empty?

        # CSP keyword sources (not URLs) are safe verbatim and short.
        return str if CSP_KEYWORDS.include?(str)

        uri =
          begin
            URI.parse(str)
          rescue URI::InvalidURIError
            nil
          end

        # If it doesn't parse into something with a scheme+host we can't reason
        # about it safely — refuse to log the raw value.
        return '[redacted]' if uri.nil? || uri.scheme.nil? || uri.host.nil?

        origin = "#{uri.scheme}://#{uri.host}"
        origin = "#{origin}:#{uri.port}" if explicit_port?(uri)

        # Never emit any path segment — only signal whether a path was present.
        path = uri.path.to_s
        path.empty? || path == '/' ? "#{origin}/" : "#{origin}/[redacted-path]"
      end

      # CSP source keywords that may appear in blocked-uri / document-uri and are
      # not URLs (so cannot leak a secret). Browsers sometimes send these with
      # surrounding single quotes and sometimes without, so both forms are listed.
      CSP_KEYWORDS = [
        'inline', 'eval', 'self', 'data', 'blob', 'filesystem', 'about', 'wasm-eval',
        "'inline'", "'eval'", "'self'"
      ].freeze

      private

      # A short, non-URL scalar (directive name, disposition). Truncated
      # defensively so a hostile/oversized value can't bloat the log line.
      def safe_token(value)
        return nil if value.nil?

        str = value.to_s.strip
        return nil if str.empty?

        str.length > 128 ? "#{str[0, 128]}…" : str
      end

      def safe_int(value)
        return nil if value.nil?
        return value if value.is_a?(Integer)

        str = value.to_s
        str.match?(/\A\d{1,9}\z/) ? str.to_i : nil
      end

      # True when the URI carries a non-default port we should preserve.
      def explicit_port?(uri)
        return false if uri.port.nil?

        default = URI.scheme_list[uri.scheme.upcase]&.default_port
        uri.port != default
      end
    end
  end
end
