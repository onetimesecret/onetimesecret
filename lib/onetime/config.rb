module Onetime
  module Config
    extend self
    attr_writer :path

    SERVICE_PATHS = %w[/etc/onetime ./etc].freeze
    UTILITY_PATHS = %w[~/.onetime /etc/onetime ./etc].freeze
    attr_reader :env, :base, :bootstrap

    # Load a YAML configuration file, allowing for ERB templating within the file.
    # This reads the file at the given path, processes any embedded Ruby (ERB) code,
    # and then parses the result as YAML.
    #
    # @param path [String] (optional the path to the YAML configuration file
    # @return [Hash] the parsed YAML data
    #
    def load(path=nil)
      path ||= self.path

      raise ArgumentError, "Missing config file" if path.nil?
      raise ArgumentError, "Bad path (#{path})" unless File.readable?(path)

      parsed_template = ERB.new(File.read(path))

      YAML.load(parsed_template.result)
    rescue StandardError => e
      OT.le "Error loading config: #{path}"
      OT.le

      # Log the contents of the parsed template for debugging purposes.
      # This helps identify issues with template rendering and provides
      # context for the error, making it easier to diagnose config
      # problems, especially when the error involves environment vars.
      if parsed_template
        template_content = parsed_template.result
        template_lines = template_content.split("\n")

        template_lines.each_with_index do |line, index|
          OT.ld "Line #{index + 1}: #{line}"
        end
      end

      OT.le e.message
      OT.le e.backtrace.join("\n")
      Kernel.exit(1)
    end

    def after_load(conf = nil)
      conf ||= {}

      unless conf.key?(:development)
        raise OT::Problem, "No `development` config found in #{path}"
      end

      unless conf.key?(:mail)
        raise OT::Problem, "No `mail` config found in #{path}"
      end

      unless conf[:site]&.key?(:authentication)
        raise OT::Problem, "No `site.authentication` config found in #{path}"
      end

      unless conf[:site]&.key?(:domains)
        conf[:site][:domains] = { enabled: false }
      end

      unless conf[:site]&.key?(:plans)
        conf[:site][:plans] = { enabled: false }
      end

      unless conf[:site]&.key?(:regions)
        conf[:site][:regions] = { enabled: false }
      end

      unless conf[:site]&.key?(:secret_options)
        conf[:site][:secret_options] = {}
      end
      conf[:site][:secret_options][:default_ttl] ||= 7.days
      conf[:site][:secret_options][:ttl_options] ||= [
        5.minutes,      # 300 seconds
        30.minutes,     # 1800
        1.hour,         # 3600
        4.hours,        # 14400
        12.hours,       # 43200
        1.day,          # 86400
        3.days,         # 259200
        1.week,         # 604800
        2.weeks,        # 1209600
        30.days,        # 2592000
      ]

      # Disable all authentication sub-features when main feature is off for
      # consistency, security, and to prevent unexpected behavior. Ensures clean
      # config state.
      if OT.conf.dig(:site, :authentication, :enabled) != true
        OT.conf[:site][:authentication].each_key do |key|
          conf[:site][:authentication][key] = false
        end
      end

      if OT.conf.dig(:site, :domains, :enabled).to_s == "true"
        cluster = conf.dig(:site, :domains, :cluster)
        OT.ld "Setting OT::Cluster::Features #{cluster}"
        klass = OT::Cluster::Features
        klass.api_key = cluster[:api_key]
        klass.cluster_ip = cluster[:cluster_ip]
        klass.cluster_name = cluster[:cluster_name]
        klass.cluster_host = cluster[:cluster_host]
        klass.vhost_target = cluster[:vhost_target]
        OT.ld "Domains config: #{cluster}"
        unless klass.api_key
          raise OT::Problem.new "No `site.domains.cluster` api key (#{klass.api_key})"
        end
      end

      site_host = OT.conf.dig(:site, :host)
      ttl_options = OT.conf.dig(:site, :secret_options, :ttl_options)
      default_ttl = OT.conf.dig(:site, :secret_options, :default_ttl)

      # if the ttl_options setting is a string, we want to split it into an
      # array of integers.
      if ttl_options.is_a?(String)
        conf[:site][:secret_options][:ttl_options] = ttl_options.split(/\s+/)
      end
      ttl_options = OT.conf.dig(:site, :secret_options, :ttl_options)
      if ttl_options.is_a?(Array)
        conf[:site][:secret_options][:ttl_options] = ttl_options.map(&:to_i)
      end

      if default_ttl.is_a?(String)
        conf[:site][:secret_options][:default_ttl] = default_ttl.to_i
      end

      if OT.conf.dig(:site, :plans, :enabled).to_s == "true"
        stripe_key = conf.dig(:site, :plans, :stripe_key)
        unless stripe_key
          raise OT::Problem, "No `site.plans.stripe_key` found in #{path}"
        end

        require 'stripe'
        Stripe.api_key = stripe_key
      end

      mtc = conf[:mail][:truemail]
      OT.ld "Setting TrueMail config from #{path}"
      raise OT::Problem, "No TrueMail config found" unless mtc

      # Iterate over the keys in the mail/truemail config
      # and set the corresponding key in the Truemail config.
      Truemail.configure do |config|
        mtc.each do |key, value|
          actual_key = mapped_key(key)
          unless config.respond_to?("#{actual_key}=")
            OT.le "config.#{actual_key} does not exist"
          end
          OT.ld "Setting Truemail config key #{key} to #{value}"
          config.send("#{actual_key}=", value)
        end
      end

      # Apply the defaults to backend and frontend
      merged = merge_config_sections(conf.dig(:services, :sentry))
      OT.conf[:services] = {
        sentry: merged
      }

      OT.conf[:services][:sentry][:enabled] = false
      backend = OT.conf[:services][:sentry].fetch(:backend, {})
      dsn = backend.fetch(:dsn, nil)

      unless dsn.nil?
        OT.ld "Setting up Sentry #{backend}..."

        # Require only if we have a DSN
        require 'sentry-ruby'
        require 'stackprof'

        OT.li "[sentry-init] Initializing with DSN: #{dsn[0..10]}..."
        Sentry.init do |config|
          config.dsn = dsn
          config.environment = "#{site_host} (#{OT.env})"
          config.release = OT::VERSION.inspect

          # Configure breadcrumbs logger for detailed error tracking.
          # Uses sentry_logger to capture progression of events leading
          # to errors, providing context for debugging.
          config.breadcrumbs_logger = [:sentry_logger]

          # Set traces_sample_rate to capture 10% of
          # transactions for performance monitoring.
          config.traces_sample_rate = 0.1

          # Set profiles_sample_rate to profile 10%
          # of sampled transactions.
          config.profiles_sample_rate = 0.1
        end

        OT.li "[sentry-init] Status: #{Sentry.initialized? ? 'OK' : 'Failed'}"
        OT.conf[:services][:sentry][:enabled] = true
      end

      development = conf[:development]
      development[:enabled] ||= false
      development[:frontend_host] ||= ''  # make sure this is set

    end

    def exists?
      !path.nil?
    end

    def dirname
      @dirname ||= File.dirname(path)
    end

    def path
      @path ||= find_configs.first
    end

    def mapped_key(key)
      # `key` is a symbol. Returns a symbol.
      # If the key is not in the KEY_MAP, return the key itself.
      KEY_MAP[key] || key
    end

    # Merges section configurations with defaults
    #
    # @param config [Hash] Raw configuration with :defaults and named sections
    # @return [Hash] Processed sections with defaults applied
    #
    # @example Basic usage
    #   config = {
    #     defaults: { timeout: 5, enabled: true },
    #     api: { timeout: 10 },
    #     web: {}
    #   }
    #   merge_config_sections(config)
    #   # => {
    #   #   api: { timeout: 10, enabled: true },
    #   #   web: { timeout: 5, enabled: true }
    #   # }
    #
    # @example With nil config
    #   merge_config_sections(nil) #=> {}
    #
    # @example Real world config
    #   service_config = {
    #     defaults: { dsn: ENV['DSN'] },
    #     backend: { path: '/api' },
    #     frontend: { path: '/web' }
    #   }
    #   sections = merge_config_sections(service_config)
    #   sections[:backend][:dsn] #=> ENV['DSN']
    def merge_config_sections(config)
      return {} if config.nil? || config.empty?

      defaults = config[:defaults] || {}
      return {} unless defaults.is_a?(Hash)

      config.each_with_object({}) do |(section, values), result|
        next if section == :defaults
        next unless values.is_a?(Hash)

        # Deep merge defaults with section values, preserving nil values only for explicitly set keys
        result[section] = defaults.merge(values) do |_key, default_val, section_val|
          section_val.nil? ? default_val : section_val
        end
      end
    end

    def find_configs(filename = nil)
      filename ||= 'config.yaml'
      paths = Onetime.mode?(:cli) ? UTILITY_PATHS : SERVICE_PATHS
      paths.collect do |f|
        f = File.join File.expand_path(f), filename
        Onetime.ld "Looking for #{f}"
        f if File.exist?(f)
      end.compact
    end
  end

  # A simple map of our config options using our naming conventions
  # to the names that are used by other libraries. This makes it easier
  # for us to have our own consistent naming conventions.
  KEY_MAP = {
    allowed_domains_only: :whitelist_validation,
    allowed_emails: :whitelisted_emails,
    blocked_emails: :blacklisted_emails,
    allowed_domains: :whitelisted_domains,
    blocked_domains: :blacklisted_domains,
    blocked_mx_ip_addresses: :blacklisted_mx_ip_addresses,

    # An example mapping for testing.
    example_internal_key: :example_external_key
  }
end
