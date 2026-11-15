# lib/onetime/initializers/print_log_banner.rb
#
# frozen_string_literal: true

# No longer need tty-table

module Onetime
  module Initializers
    # PrintLogBanner initializer
    #
    # Prints a formatted banner with system and configuration information at startup.
    # This initializer performs side-effect operations (logging) and doesn't set
    # runtime state that needs to be tracked.
    #
    # rubocop:disable Metrics/ClassLength
    class PrintLogBanner < Onetime::Boot::Initializer
      @depends_on = [:logging, :familia_config, :domains]

      using Familia::Refinements::TimeLiterals

      def execute(_context)
        print_log_banner
      end

      private

      # Prints a formatted banner with system and configuration information at startup.
      # The banner is organized into logical sections, each rendered as a table.
      #
      # Structure:
      # - All output is collected in an array and printed with a single OT.li call
      # - Each section is rendered as a TTY::Table with consistent formatting
      # - Sections are separated by newlines
      #
      # To add a new section to the banner:
      # 1. Add a section comment: ====== New Section Name ======
      # 2. Create an array to collect rows: `new_section_rows = []`
      # 3. Add key/value pairs to the array: `new_section_rows << ['Key', 'Value']`
      # 4. Check if the section has content: `unless new_section_rows.empty?`
      # 5. Add rendered section to output: `output << render_section('Header1', 'Header2', new_section_rows)`
      #
      # Helper methods available:
      # - render_section(header1, header2, rows): Creates a formatted table
      # - disabled?(path): Checks if the config section at path is disabled
      # - format_config_value(config): Formats complex config values for display
      # - format_duration(seconds): Converts seconds to human-readable format (e.g., "5m", "2h", "7d")
      def print_log_banner
      redis_info = Familia.dbclient.info

      # Header banner
      auth_mode      = defined?(OT.auth_config) ? OT.auth_config.mode : 'n/a'
      billing_status = defined?(OT.billing_config) ? OT.billing_config.enabled? : 'n/a'
      OT.boot_logger.info "---  ONETIME #{OT.mode} v#{OT::VERSION.details}  auth:#{auth_mode} billing:#{billing_status}  #{'---' * 3}"

      # Create a buffer to collect all output
      output = []
      output << ''

      # Add each section to output
      system_rows = build_system_section(redis_info)
      output << render_section('Component', 'Value', system_rows)

      dev_rows = build_dev_section
      unless dev_rows.empty?
        output << render_section('Development', 'Settings', dev_rows)
      end

      feature_rows = build_features_section
      unless feature_rows.empty?
        output << render_section('Features', 'Configuration', feature_rows)
      end

      mail_rows = build_email_section
      unless mail_rows.empty?
        output << render_section('Mail Config', 'Value', mail_rows)
      end

      auth_rows = build_auth_section
      unless auth_rows.empty?
        output << render_section('Authentication', 'Details', auth_rows)
      end

      auth_config_rows = build_auth_config_section
      unless auth_config_rows.empty?
        output << render_section('Auth Config', 'Value', auth_config_rows)
      end

      billing_config_rows = build_billing_config_section
      unless billing_config_rows.empty?
        output << render_section('Billing Config', 'Value', billing_config_rows)
      end

      domains_config_rows = build_domains_config_section
      unless domains_config_rows.empty?
        output << render_section('Domains Config', 'Value', domains_config_rows)
      end

      customization_rows = build_customization_section
      unless customization_rows.empty?
        output << render_section('Customization', 'Configuration', customization_rows)
      end

      # Footer

      # Output everything with a single OT.li call
      OT.boot_logger.debug output.join("\n")
      end

      # Builds system information section rows
      def build_system_section(redis_info)
        redis_dbs   = OT.conf.get('redis.dbs', {})
        system_rows = [
          ['System', "#{RUBY_ENGINE} #{RUBY_VERSION} in #{OT.env}"],
          ['Config', OT::Config.path],
          ['Valkey', "#{redis_info['redis_version']} (#{Familia.uri.serverid})"],
          ['Familia', "v#{Familia::VERSION}"],
          ['Otto', "v#{Otto::VERSION}"],
          ['I18n', OT.i18n_enabled],
          ['Diagnostics', OT.d9s_enabled],
          ['Models', redis_dbs.inspect],
        ]

        # Add locales if i18n is enabled
        if OT.i18n_enabled
          locales = Onetime::Runtime.internationalization.locales
          system_rows << ['Locales', locales.keys.join(', ')] if locales
        end

        system_rows
      end

      # Builds development settings section rows
      def build_dev_section
        development = OT.conf.get('development', nil)
        return [] unless development

        [['Development', disabled?('development') ? 'disabled' : format_config_value(development)]]
      end

      # Builds features section rows from features config
      def build_features_section
        feature_rows = []

        # Domains feature
        domains = OT.conf.get('features.domains', nil)
        if disabled?('features.domains')
          feature_rows << %w[Domains disabled]
        elsif domains.is_a?(Hash) && !domains.empty?
          feature_rows << ['Domains', format_config_value(domains)]
        end

        # Regions feature with jurisdictions
        if disabled?('features.regions')
          feature_rows << %w[Regions disabled]
        elsif OT.conf.get('features.regions', nil).is_a?(Hash)
          jurisdictions = OT.conf.get('features.regions.jurisdictions', [])
          if jurisdictions.any?
            ids = jurisdictions.map { |j| j['identifier'] }.join(', ')
            feature_rows << ['Regions', "enabled (#{ids})"]
            current = OT.conf.get('features.regions.current_jurisdiction', nil)
            feature_rows << ['Current', current] if current
          else
            feature_rows << ['Regions', 'enabled (no jurisdictions)']
          end
        end

        feature_rows
      end

      # Builds email configuration section rows
      def build_email_section
        emailer = OT.conf.get('emailer', nil)
        return [] if emailer.nil? || emailer.empty?
        return [%w[Status disabled]] if disabled?('emailer')

        # from_name, then fromname (deprecated as of v0.23), as Mailer.from_name reads them.
        from_name = OT.conf.get('emailer.from_name', nil) || OT.conf.get('emailer.fromname', nil)

        [
          ['Mode', OT.conf.get('emailer.mode', nil)],
          ['From', "'#{from_name} <#{OT.conf.get('emailer.from', nil)}>'"],
          ['Host', "#{OT.conf.get('emailer.host', nil)}:#{OT.conf.get('emailer.port', nil)}"],
          ['Region', OT.conf.get('emailer.region', nil)],
          ['TLS', OT.conf.get('emailer.tls', nil)],
          ['Auth', OT.conf.get('emailer.auth', nil)],
        ].reject { |row| row[1].nil? || row[1].to_s.empty? }
      rescue StandardError => ex
        [['Error', "Error rendering mail config: #{ex.message}"]]
      end

      # Builds authentication section rows
      # Note: Colonels are now managed via CLI (bin/ots customers role) rather than config
      def build_auth_section
        authentication = OT.conf.get('site.authentication', nil)
        return [] unless authentication.is_a?(Hash)

        settings = if disabled?('site.authentication')
          'disabled'
        else
          authentication.map { |k, v| "#{k}=#{v}" }.join(', ')
        end
        [['Auth UI Settings', settings]]
      end

      # Builds Onetime.auth_config section rows
      def build_auth_config_section
        auth_config_rows = []

        begin
          return auth_config_rows unless defined?(OT.auth_config)

          config = OT.auth_config

          # Basic info
          auth_config_rows << ['Mode', config.mode]

          # Database URL (masked)
          if config.database_url
            masked_url = mask_sensitive_value(config.database_url, type: :url)
            auth_config_rows << ['Database URL', masked_url]
          end

          # Migrations Database URL (masked)
          if config.database_url_migrations
            masked_url = mask_sensitive_value(config.database_url_migrations, type: :url)
            auth_config_rows << ['Migrations URL', masked_url]
          end

          # Feature flags
          auth_config_rows << ['Full Mode', config.full_enabled?]
          auth_config_rows << ['Simple Mode', config.simple_enabled?]
        rescue StandardError => ex
          auth_config_rows << ['Error', "Error rendering auth config: #{ex.message}"]
        end

        auth_config_rows
      end

      # Builds Onetime.billing_config section rows
      def build_billing_config_section
        billing_config_rows = []

        begin
          return billing_config_rows unless defined?(OT.billing_config)

          config = OT.billing_config

          # Enabled status
          billing_config_rows << ['Enabled', config.enabled?]

          return billing_config_rows unless config.enabled?

          # Stripe API key (masked)
          if config.stripe_key
            masked_key = mask_sensitive_value(config.stripe_key, type: :stripe_key)
            mode       = config.stripe_key.start_with?('sk_test_', 'rk_test_') ? 'Test' : 'Live'
            billing_config_rows << ['Stripe Key', "#{masked_key} (#{mode})"]
          end

          # Webhook signing secret (masked)
          if config.webhook_signing_secret
            masked_secret = mask_sensitive_value(config.webhook_signing_secret, type: :webhook_secret)
            billing_config_rows << ['Webhook Secret', masked_secret]
          end

          # API version
          billing_config_rows << ['API Version', config.stripe_api_version] if config.stripe_api_version

          # Region isolation status
          billing_config_rows << if config.region
            ['Region Isolation', "enabled (jurisdiction=#{config.region})"]
          else
            ['Region Isolation', 'disabled (all jurisdictions synced)']
                                 end
        rescue StandardError => ex
          billing_config_rows << ['Error', "Error rendering billing config: #{ex.message}"]
        end

        billing_config_rows
      end

      # Builds Onetime::DomainValidation::Features section rows
      def build_domains_config_section
        domains_config_rows = []

        begin
          # Check if DomainValidation::Features is loaded and configured
          return domains_config_rows unless defined?(Onetime::DomainValidation::Features)

          features = Onetime::DomainValidation::Features

          # Strategy name
          strategy = features.strategy_name
          return domains_config_rows if strategy.nil? || strategy.empty?

          domains_config_rows << ['Validation Strategy', strategy]

          # API configured (for approximated)
          if strategy == 'approximated'
            domains_config_rows << ['API Configured', features.api_configured?]
          end

          # Proxy settings (only show if present)
          domains_config_rows << ['Proxy Host', features.proxy_host] if features.proxy_host
          domains_config_rows << ['Proxy IP', features.proxy_ip] if features.proxy_ip
          domains_config_rows << ['Proxy Name', features.proxy_name] if features.proxy_name
          domains_config_rows << ['Vhost Target', features.vhost_target] if features.vhost_target
        rescue StandardError => ex
          domains_config_rows << ['Error', "Error rendering domains config: #{ex.message}"]
        end

        domains_config_rows
      end

      # Masks sensitive values for display
      # @param value [String] The sensitive value to mask
      # @param type [Symbol] The type of value (:url, :stripe_key, :webhook_secret)
      # @return [String] The masked value
      def mask_sensitive_value(value, type:)
        return '[not set]' if value.nil? || value.empty?

        case type
        when :url
          mask_url(value)
        when :stripe_key
          # For Stripe keys, show the prefix and last 4 characters
          # Format: sk_test_xxx or sk_live_xxx
          if value =~ /^(sk_(?:test|live)_)(.+)$/
            prefix = ::Regexp.last_match(1)
            rest   = ::Regexp.last_match(2)
            "#{prefix}#{'*' * 8}#{rest[-4..]}"
          else
            show_chars(value, prefix: 8, suffix: 4)
          end
        when :webhook_secret
          # For webhook secrets, show just the prefix
          # Format: whsec_xxx
          if value =~ /^(whsec_)(.+)$/
            "#{::Regexp.last_match(1)}#{'*' * 12}"
          else
            show_chars(value, prefix: 6, suffix: 0)
          end
        else
          # Generic masking
          show_chars(value, prefix: 4, suffix: 4)
        end
      end

      # Masks a database URL for display. Keeps the scheme, username, host
      # and path, which tell the app and migrations URLs apart, and masks the
      # password and the whole query string, where libpq also takes one
      # (`?password=`). The password runs to the LAST "@", so an unescaped
      # "@" in it masks too much rather than printing the rest of it.
      #
      # Two shapes are masked past the scheme: a "?" before that "@", which
      # is either in the password or starts a query with an "@" in it, and a
      # value with no "scheme://", which has no reliable shape to keep. A
      # SQLite URL (`sqlite::memory:` included) has no userinfo: its path is
      # kept whole and only its query is masked.
      #
      #   mask_url('postgresql://app:s3cret@db/auth?sslmode=require')
      #   #=> "postgresql://app:****@db/auth?****"
      #
      # @param value [String]
      # @return [String]
      def mask_url(value)
        Onetime::Utils.redact_uri_userinfo(value, keep_username: true, require_scheme: true, mask: '****')
      end

      # Helper to show only prefix and suffix characters
      def show_chars(value, prefix:, suffix:)
        return '[empty]' if value.nil? || value.empty?
        return value if value.length <= (prefix + suffix)

        masked_length = [value.length - prefix - suffix, 4].max
        "#{value[0...prefix]}#{'*' * masked_length}#{value[-suffix..] if suffix > 0}"
      end

      # Builds customization section rows
      def build_customization_section
        customization_rows = []

        # Secret options
        default_ttl = OT.conf.get('site.secret_options.default_ttl', nil)
        customization_rows << ['Default TTL', format_duration(default_ttl.to_i)] if default_ttl

        ttl_options = OT.conf.get('site.secret_options.ttl_options', nil)
        if ttl_options
          customization_rows << ['TTL Options', ttl_options.map { |seconds| format_duration(seconds) }.join(', ')]
        end

        { 'passphrase' => 'Passphrase', 'password_generation' => 'Password Generation' }.each do |key, label|
          path    = "site.secret_options.#{key}"
          section = OT.conf.get(path, nil)
          if disabled?(path)
            customization_rows << [label, 'disabled']
          elsif section.is_a?(Hash) && !section.empty?
            customization_rows << [label, format_config_value(section)]
          end
        end

        # Interface configuration, with its ui and api sections
        if disabled?('site.interface')
          customization_rows << %w[Interface disabled]
        elsif OT.conf.get('site.interface', nil).is_a?(Hash)
          %w[ui api].each do |key|
            path    = "site.interface.#{key}"
            section = OT.conf.get(path, nil)
            if disabled?(path)
              customization_rows << ["Interface > #{key.upcase}", 'disabled']
            elsif !section.nil? && (section.is_a?(Hash) ? !section.empty? : !section.to_s.empty?)
              customization_rows << ["Interface > #{key.upcase}", format_config_value(section)]
            end
          end
        end

        customization_rows
      end

      # Whether the config section at +path+ sets enabled to false.
      def disabled?(path)
        OT.conf.get(path, nil).is_a?(Hash) && OT.conf.get("#{path}.enabled", true) == false
      end

      # Helper method to format config values with special handling for hashes and arrays
      def format_config_value(config)
          if config.is_a?(Hash)
            config.map do |k, v|
              value_str = v.is_a?(Hash) || v.is_a?(Array) ? v.to_json : v.to_s
              "#{k}=#{value_str}"
            end.join(', ')
          else
            config.to_s
          end
      end

      # Helper method to convert seconds to human-readable duration format
      def format_duration(seconds)
        seconds = seconds.to_i

        case seconds
        when 0...60
          "#{seconds}s"
        when 60...3600
          minutes = seconds / 60
          minutes == 1 ? '1m' : "#{minutes}m"
        when 3600...86_400
          hours = seconds / 3600
          hours == 1 ? '1h' : "#{hours}h"
        when 86_400...604_800
          days = seconds / 86_400
          days == 1 ? '1d' : "#{days}d"
        when 604_800...2_592_000
          weeks = seconds / 604_800
          weeks == 1 ? '1w' : "#{weeks}w"
        else
          # For very large values, use days
          days = seconds / 86_400
          "#{days}d"
        end
      end

      # Helper method to render a section as a simple formatted table
      def render_section(header1, header2, rows)
        col1_width  = 17  # Width for first column
        col2_width  = 80  # Width for second column
        total_width = col1_width + col2_width + 7  # Include borders and padding
        separator   = '-' * total_width

        output = []
        output << separator
        output << format_row(header1, header2, col1_width, col2_width)
        output << separator

        rows.each do |row|
          output << format_row(row[0], row[1], col1_width, col2_width)
        end

        output << separator
        output.join("\n") + "\n"
      end

      # Helper method to format a table row with word wrapping
      def format_row(col1, col2, width1, width2)
        col1_str = (col1 || '').to_s
        col2_str = (col2 || '').to_s

        # Handle word wrapping for both columns
        col1_lines = word_wrap(col1_str, width1)
        col2_lines = word_wrap(col2_str, width2)

        # Ensure we have at least one line for each column
        col1_lines = [''] if col1_lines.empty?
        col2_lines = [''] if col2_lines.empty?

        # Determine how many lines we need (max of both columns)
        max_lines = [col1_lines.length, col2_lines.length].max

        lines = []
        (0...max_lines).each do |i|
          left_text  = (col1_lines[i] || '').ljust(width1)
          right_text = (col2_lines[i] || '').ljust(width2)
          lines << "| #{left_text} | #{right_text} |"
        end

        lines.join("\n")
      end

      # Simple word wrap helper
      def word_wrap(text, width)
        return [''] if text.nil? || text.empty?

        # Handle text that's already within width
        return [text] if text.length <= width

        # Simple wrapping at width boundary
        lines     = []
        remaining = text.dup

        until remaining.empty?
          if remaining.length <= width
            lines << remaining
            break
          else
            # Try to break at a space
            break_point = remaining.rindex(' ', width)
            break_point = width if break_point.nil? || break_point == 0

            lines << remaining[0...break_point].rstrip
            remaining = remaining[break_point..].lstrip
          end
        end

        lines.empty? ? [''] : lines
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
