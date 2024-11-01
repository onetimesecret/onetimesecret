module Onetime
  class DomainType
    # Constants for domain validation. Use defined? to avoid warnings when reloading
    unless defined?(MAX_DOMAIN_LENGTH)
      MAX_DOMAIN_LENGTH = 253 # Max length of domain name as per RFC 1035
      MAX_LABEL_LENGTH = 63  # Max length of individual labels (parts between dots)
    end

    attr_reader :host_field_name, :domain_strategy, :canonical_domain, :config

    def initialize(app)
      @app = app
      @config = OT.conf.fetch(:site, {})
      @canonical_domain = determine_canonical_domain
      @host_field_name = Rack::DetectHost.result_field_name
    end

    def call(env)
      # Fail-fast and move on with life when domains are disabled
      return @app.call(env) unless domains_enabled?

      # We rely on Rack::DetectHost running to populate this field
      request_host = env[host_field_name] # request host can be nil (e.g. IP address)
      env['onetime.domain_strategy'] = determine_domain_strategy(request_host)

      @app.call(env)
    end

    def determine_domain_strategy(request_host)
      # Early returns for simple cases where we default to canonical
      return :canonical if canonical_or_invalid?(request_host)

      normalized_host = normalize_host(request_host)
      return :canonical unless normalized_host
      return :canonical if normalized_host == canonical_domain

      classify_domain_strategy(normalized_host)
    end

    private

    def domains_enabled?
      config.dig(:domains, :enabled)
    end

    def determine_canonical_domain
      # Use the domains configuration if enabled and available otherwise default
      # to the site host which isn't necessarily a domain (e.g. 127.0.0.1:3000)
      domain = if domains_enabled? && config.dig(:domains, :default)
                config.dig(:domains, :default)
              else
                config.fetch(:host, nil)
              end

      normalized_domain = Rack::DetectHost.normalize_host(domain)
      Rack::DetectHost.valid_host?(normalized_domain) ? normalized_domain : nil
    end

    def canonical_or_invalid?(request_host)
      request_host.nil? || canonical_domain.nil?
    end

    def classify_domain_strategy(normalized_host)
      canonical_parts = canonical_domain.split('.')
      request_parts = normalized_host.split('.')

      # Add debug logging for domain parts comparison
      log_domain_parts(request_parts, canonical_parts)

      return :custom unless valid_domain_parts?(request_parts)

      if subdomain?(normalized_host, request_parts, canonical_parts)
        :subdomain
      else
        :custom
      end
    end

    def normalize_host(host)
      return nil if invalid_host?(host)

      normalized = normalize_and_validate_host(host)
      return nil unless normalized

      normalized
    end

    def invalid_host?(host)
      host.nil? || host.empty?
    end

    def normalize_and_validate_host(host)
      # Remove whitespace, ports, and convert to lowercase and
      # then handle IDN (International Domain Names) conversion.
      normalized = host.strip.downcase.split(':').first # Remove port

      # rubocop:disable Style/RescueModifier
      normalized = SimpleIDN.to_ascii(normalized) rescue ''
      # rubocop:enable Style/RescueModifier

      # Basic format validation
      return nil if invalid_format?(normalized) || invalid_labels?(normalized)

      normalized
    end

    def invalid_format?(host)
      host.length > MAX_DOMAIN_LENGTH ||
        host.start_with?('.') ||
        host.end_with?('.') ||
        host.include?('..') # Reject double dots
    end

    def invalid_labels?(host)
      parts = host.split('.')
      parts.any? { |part| part.length > MAX_LABEL_LENGTH }
    end

    def valid_domain_parts?(parts)
      return false if parts.empty?

      # Ensure all parts follow DNS label rules
      parts.all? do |part|
        valid_label_format?(part)
      end
    end

    def valid_label_format?(part)
      # DNS labels must start/end with alphanumeric and contain only alphanumeric + hyphen
      part.length <= MAX_LABEL_LENGTH &&
        part.match?(/\A[a-z0-9]([a-z0-9-]*[a-z0-9])?\z/i)
    end

    def subdomain?(request_host, request_parts, canonical_parts)
      # Must have more parts than canonical domain
      return false if request_parts.length <= canonical_parts.length

      # More explicit suffix check
      suffix = canonical_parts.join('.')
      return false unless request_host.end_with?(".#{suffix}")

      # Validate subdomain parts separately
      subdomain_parts = request_parts[0...-canonical_parts.length]
      valid_domain_parts?(subdomain_parts)
    end

    def log_domain_parts(request_parts, canonical_parts)
      OT.ld("Request parts: #{request_parts}")
      OT.ld("Canonical parts: #{canonical_parts}")
    end
  end
end
