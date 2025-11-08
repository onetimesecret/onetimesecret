# lib/onetime/initializers/print_log_banner.rb
#
# frozen_string_literal: true

# No longer need tty-table

module Onetime
  module Initializers
    using Familia::Refinements::TimeLiterals

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
    # - is_feature_disabled?(config): Checks if a feature is disabled
    # - format_config_value(config): Formats complex config values for display
    # - format_duration(seconds): Converts seconds to human-readable format (e.g., "5m", "2h", "7d")
    def print_log_banner
      site_config  = OT.conf.fetch('site') # if site is missing we got real problems
      email_config = OT.conf.fetch('emailer', {})
      redis_info   = Familia.dbclient.info
      colonels     = site_config.dig('authentication', 'colonels') || []

      # Header banner
      OT.boot_logger.info "---  ONETIME #{OT.mode} v#{OT::VERSION.inspect}  #{'---' * 3}"

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

      feature_rows = build_features_section(site_config)
      unless feature_rows.empty?
        output << render_section('Features', 'Configuration', feature_rows)
      end

      mail_rows = build_email_section(email_config)
      unless mail_rows.empty?
        output << render_section('Mail Config', 'Value', mail_rows)
      end

      auth_rows = build_auth_section(site_config, colonels)
      unless auth_rows.empty?
        output << render_section('Authentication', 'Details', auth_rows)
      end

      customization_rows = build_customization_section(site_config)
      unless customization_rows.empty?
        output << render_section('Customization', 'Configuration', customization_rows)
      end

      # Footer

      # Output everything with a single OT.li call
      OT.boot_logger.info output.join("\n")
    end

    private

    # Builds system information section rows
    def build_system_section(redis_info)

      redis_dbs = OT.conf.dig('redis', 'dbs') || {}
      system_rows = [
        ['System', "#{RUBY_ENGINE} #{RUBY_VERSION} in #{OT.env}"],
        ['Config', OT::Config.path],
        ['Valkey', "#{redis_info['redis_version']} (#{Familia.uri.serverid})"],
        ['Familia', "v#{Familia::VERSION}"],
        ['Otto', "v#{Otto::VERSION}"],
        ['I18n', OT.i18n_enabled],
        ['Diagnostics', OT.d9s_enabled],
        ['Models', redis_dbs.inspect]
      ]

      # Add locales if i18n is enabled
      if OT.i18n_enabled
        system_rows << ['Locales', @locales.keys.join(', ')]
      end

      system_rows
    end

    # Builds development and experimental settings section rows
    def build_dev_section
      dev_rows = []

      %w[development experimental].each do |key|
        next unless config_value = OT.conf.fetch(key, false)

        dev_rows << if is_feature_disabled?(config_value)
          [key.to_s.capitalize, 'disabled']
        else
          [key.to_s.capitalize, format_config_value(config_value)]
                    end
      end

      dev_rows
    end

    # Builds features section rows
    def build_features_section(site_config)
      feature_rows = []

      # Domains and regions
      %w[domains regions].each do |key|
        next unless site_config.key?(key)

        config = site_config[key]
        if is_feature_disabled?(config)
          feature_rows << [key.to_s.capitalize, 'disabled']
        elsif !config.empty?
          feature_rows << [key.to_s.capitalize, format_config_value(config)]
        end
      end

      feature_rows
    end

    # Builds email configuration section rows
    def build_email_section(email_config)
      return [] if email_config.nil? || email_config.empty?

      begin
        if is_feature_disabled?(email_config)
          [%w[Status disabled]]
        else
          [
            ['Mailer', @emailer],
            ['Mode', email_config['mode']],
            ['From', "'#{email_config['fromname']} <#{email_config['from']}>'"],
            ['Host', "#{email_config['host']}:#{email_config['port']}"],
            ['Region', email_config['region']],
            ['TLS', email_config['tls']],
            ['Auth', email_config['auth']],
          ].reject { |row| row[1].nil? || row[1].to_s.empty? }
        end
      rescue StandardError => ex
        [['Error', "Error rendering mail config: #{ex.message}"]]
      end
    end

    # Builds authentication section rows
    def build_auth_section(site_config, colonels)
      auth_rows = [
        ['Auth Mode', OT.auth_config.mode]
      ]

      auth_rows << if colonels.empty?
        ['Colonels', 'No colonels configured ⚠️']
      else
        ['Colonels', colonels.join(', ')]
      end

      if site_config.key?('authentication')
        auth_config = site_config['authentication']
        if is_feature_disabled?(auth_config)
          auth_rows << ['Auth Settings', 'disabled']
        else
          auth_settings = auth_config.map { |k, v| "#{k}=#{v}" }.join(', ')
          auth_rows << ['Auth Settings', auth_settings]
        end
      end

      auth_rows
    end

    # Builds customization section rows
    def build_customization_section(site_config)
      customization_rows = []

      # Secret options
      secret_options = OT.conf.dig('site', 'secret_options')
      if secret_options
        # Format default TTL
        if secret_options['default_ttl']
          default_ttl = format_duration(secret_options['default_ttl'].to_i)
          customization_rows << ['Default TTL', default_ttl]
        end

        # Format TTL options
        if secret_options['ttl_options']
          ttl_options = secret_options['ttl_options'].map { |seconds| format_duration(seconds) }.join(', ')
          customization_rows << ['TTL Options', ttl_options]
        end

        # Format passphrase options
        if secret_options['passphrase']
          passphrase_config = secret_options['passphrase']
          if is_feature_disabled?(passphrase_config)
            customization_rows << ['Passphrase', 'disabled']
          elsif passphrase_config.is_a?(Hash) && !passphrase_config.empty?
            customization_rows << ['Passphrase', format_config_value(passphrase_config)]
          end
        end

        # Format password_generation options
        if secret_options['password_generation']
          password_generation_config = secret_options['password_generation']
          if is_feature_disabled?(password_generation_config)
            customization_rows << ['Password Generation', 'disabled']
          elsif password_generation_config.is_a?(Hash) && !password_generation_config.empty?
            customization_rows << ['Password Generation', format_config_value(password_generation_config)]
          end
        end
      end

      # Interface configuration
      if site_config.key?('interface')
        interface_config = site_config['interface']
        if is_feature_disabled?(interface_config)
          customization_rows << %w[Interface disabled]
        elsif interface_config.is_a?(Hash)
          # Handle nested ui and api configs under interface
          %w[ui api].each do |key|
            next unless interface_config.key?(key)

            sub_config = interface_config[key]
            if is_feature_disabled?(sub_config)
              customization_rows << ["Interface > #{key.to_s.upcase}", 'disabled']
            elsif !sub_config.nil? && (sub_config.is_a?(Hash) ? !sub_config.empty? : !sub_config.to_s.empty?)
              customization_rows << ["Interface > #{key.to_s.upcase}", format_config_value(sub_config)]
            end
          end
        end
      else
      # Fallback: check for standalone ui and api configs
      %w[ui api].each do |key|
        next unless site_config.key?(key)

        config = site_config[key]
        if is_feature_disabled?(config)
          customization_rows << [key.to_s.upcase, 'disabled']
        elsif !config.empty?
          customization_rows << [key.to_s.upcase, format_config_value(config)]
        end
      end
    end

      customization_rows
    end

    # Helper method to check if a feature is disabled
    def is_feature_disabled?(config)
      config.is_a?(Hash) && config.key?('enabled') && !config['enabled']
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
      col1_width = 17  # Width for first column
      col2_width = 80  # Width for second column
      total_width = col1_width + col2_width + 7  # Include borders and padding
      separator = '-' * total_width

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
        left_text = (col1_lines[i] || '').ljust(width1)
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
      lines = []
      remaining = text.dup

      while remaining.length > 0
        if remaining.length <= width
          lines << remaining
          break
        else
          # Try to break at a space
          break_point = remaining.rindex(' ', width)
          break_point = width if break_point.nil? || break_point == 0

          lines << remaining[0...break_point].rstrip
          remaining = remaining[break_point..-1].lstrip
        end
      end

      lines.empty? ? [''] : lines
    end
  end
end
