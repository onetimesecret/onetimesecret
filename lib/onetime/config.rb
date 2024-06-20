
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

    def after_load(email_address = nil)
      email_address ||= OT.conf[:emailer][:from]
      OT.info "Setting TrueMail verifier email to #{email_address}"

      Truemail.configure do |config|
        config.verifier_email = email_address
        # config.connection_timeout = 2 # Set the timeout to 2 seconds
        config.smtp_fail_fast = true
        config.not_rfc_mx_lookup_flow = true
        config.dns = %w[208.67.222.222 8.8.8.8 8.8.4.4 208.67.220.220]
      end
    end

    def exists?
      !config_path.nil?
    end

    def dirname
      @dirname ||= File.dirname(path)
    end

    def path
      @path ||= find_configs.first
    end

    def find_configs
      paths = Onetime.mode?(:cli) ? UTILITY_PATHS : SERVICE_PATHS
      paths.collect do |f|
        f = File.join File.expand_path(f), 'config'
        Onetime.ld "Looking for #{f}"
        f if File.exist?(f)
      end.compact
    end
  end
end
