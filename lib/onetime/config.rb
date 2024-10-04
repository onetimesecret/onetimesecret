
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
        klass.vhost_target = cluster[:vhost_target]
        OT.ld "Domains config: #{cluster}"
        unless klass.api_key
          raise OT::Problem, "No `site.domains.cluster` api key (#{klass.api_key})"
        end
      end

      if OT.conf.dig(:site, :plans, :enabled).to_s == "true"
        stripe_key = conf.dig(:site, :plans, :stripe_key)
        unless stripe_key
          raise OT::Problem, "No `site.plans.stripe_key` found in #{path}"
        end

        require 'stripe'
        Stripe.api_key = stripe_key
        #require_relative 'refinements/stripe_refinements'
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
          OT.ld "Setting Truemail config key #{actual_key} to #{value}"
          config.send("#{actual_key}=", value)
        end
      end

      development = conf[:development]
      development[:enabled] ||= false
      development[:frontend_host] ||= ''  # make sure this is set

      sentry = conf[:services][:sentry]

      if sentry&.dig(:enabled)
        OT.info "Setting up Sentry #{sentry}..."
        dsn = sentry&.dig(:dsn)

        unless dsn
          OT.le "No DSN"
        end

        require 'sentry-ruby'
        require 'stackprof'

        OT.info "[sentry-init] Initializing with DSN: #{dsn[0..10]}..."
        Sentry.init do |config|
          config.dsn = sentry[:dsn]
          # Set traces_sample_rate to capture 10% of
          # transactions for performance monitoring.
          config.traces_sample_rate = 0.1

          # Set profiles_sample_rate to profile 10%
          # of sampled transactions.
          config.profiles_sample_rate = 0.1
        end
      end

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
