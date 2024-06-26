
module Onetime
  module Config
    extend self
    attr_writer :path

    SERVICE_PATHS = %w[/etc/onetime ./etc].freeze
    UTILITY_PATHS = %w[~/.onetime /etc/onetime ./etc].freeze
    attr_reader :env, :base, :bootstrap

    def load(path = self.path)
      raise ArgumentError, "Bad path (#{path})" unless File.readable?(path)

      YAML.load(ERB.new(File.read(path)).result)
    rescue StandardError => e
      SYSLOG.err e.message
      msg = if path =~ /locale/
              "Error loading locale: #{path} (#{e.message})"
            else
              "Error loading config: #{path}"
            end
      Onetime.info msg
      Kernel.exit(1)
    end

    def after_load(conf = nil)
      conf ||= {}

      unless conf.has_key?(:mail)
        raise OT::Problem, "No :mail config found in #{path}"
      end

      mtc = conf[:mail][:truemail]
      OT.info "Setting TrueMail config from #{path}"
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

      if Otto.env?(:dev) && conf[:sentry] && conf[:sentry][:enabled]
        dsn = conf[:sentry][:dsn]
        OT.info "[sentry-init] Initializing with DSN: #{dsn[0..10]}..."
        Sentry.init do |config|
          config.dsn = conf[:sentry][:dsn]

          # Set traces_sample_rate to 1.0 to capture 100%
          # of transactions for performance monitoring.
          # We recommend adjusting this value in production.
          config.traces_sample_rate = 1.0
          # or
          config.traces_sampler = lambda do |context|
            true
          end
          # Set profiles_sample_rate to profile 100%
          # of sampled transactions.
          # We recommend adjusting this value in production.
          config.profiles_sample_rate = 1.0
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
      filename ||= 'config'
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
