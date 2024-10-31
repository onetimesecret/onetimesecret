
module Onetime


  class DomainType
    MAX_DOMAIN_LENGTH = 253
    MAX_LABEL_LENGTH = 63

    attr_reader :host_field_name, :domain_strategy, :canonical_domain, :config

    def initialize(app)
      @app = app
      @config = OT.conf.fetch(:site, {})
      @canonical_domain = determine_canonical_domain
      @host_field_name = Rack::DetectHost.result_field_name
    end

    def call(env)

      # Fail-fast and move on with lifem when domains are disabled.
      unless config.dig(:domains, :enabled)
        return @app.call(env)
      end

      # We rely on Rack::DetectHost running to populate this field
      request_host = env[host_field_name] # request host can be nil (e.g. IP address)


      env['onetime.domain_strategy'] = determine_domain_strategy(request_host)

      @app.call(env)
    end

    # Use the domains configruation if enabled and available otherwise default
    # the site host which isn't necessarily a domain (e.g. 127.0.0.1:3000).
    def determine_canonical_domain
      domain = config.fetch(:host, nil)
      domains_config = config.fetch(:domains, {})

      if domains_config[:enabled] && domains_config[:default]
        domain = domains_config[:default]
      end

      domain = Rack::DetectHost.normalize_host(domain)
      Rack::DetectHost.valid_host?(domain) ? domain : nil
    end

    def determine_domain_strategy(request_host)
      return :canonical if request_host.nil? || canonical_domain.nil?

      request_host = normalize_host(request_host)
      return :canonical unless request_host

      return :canonical if request_host == canonical_domain

      canonical_parts = canonical_domain.split('.')
      request_parts = request_host.split('.')

      # Add debug logging
      OT.ld("Request parts: #{request_parts}")
      OT.ld("Canonical parts: #{canonical_parts}")

      return :custom unless valid_domain_parts?(request_parts)

      if is_valid_subdomain?(request_host, request_parts, canonical_parts)
        return :subdomain
      end

      :custom
    end

    private

    def normalize_host(host)
      return nil if host.nil? || host.empty?

      # Remove whitespace, ports, and convert to lowercase
      host = host.strip.downcase
      host = host.split(':').first # Remove port
      host = begin
               SimpleIDN.to_ascii(host)
      rescue
               host
      end # Handle IDN

      # Basic format validation
      return nil if host.length > MAX_DOMAIN_LENGTH
      return nil if host.start_with?('.') || host.end_with?('.')
      return nil if host.include?('..')

      # Validate individual label lengths
      parts = host.split('.')
      return nil if parts.any? { |part| part.length > MAX_LABEL_LENGTH }

      host
    end

    def valid_domain_parts?(parts)
      return false if parts.empty?

      parts.all? do |part|
        part.length <= MAX_LABEL_LENGTH &&
        part.match?(/\A[a-z0-9]([a-z0-9-]*[a-z0-9])?\z/i)
      end
    end

    def is_valid_subdomain?(request_host, request_parts, canonical_parts)
      return false if request_parts.length <= canonical_parts.length

      # More explicit suffix check
      suffix = canonical_parts.join('.')
      return false unless request_host.end_with?(".#{suffix}")

      # Validate subdomain parts
      subdomain_parts = request_parts[0...-canonical_parts.length]
      valid_domain_parts?(subdomain_parts)
    end
  end
end
