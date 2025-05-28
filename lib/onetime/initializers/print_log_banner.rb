# lib/onetime/initializers/print_log_banner.rb

require 'tty-table'
require 'json'

module Onetime
  module Initializers

    def print_log_banner
      site_config = OT.conf.fetch(:site) # if :site is missing we got real problems
      email_config = OT.conf.fetch(:emailer, {})
      redis_info = Familia.redis.info
      colonels = site_config.dig(:authentication, :colonels) || []

      # Create a buffer to collect all output
      output = []

      # Header banner
      output << "---  ONETIME #{OT.mode} v#{OT::VERSION.inspect}  #{'---' * 3}"
      output << ""

      # SECTION 1: Core System Information
      system_rows = [
        ['System', "#{@sysinfo.platform} (#{RUBY_ENGINE} #{RUBY_VERSION} in #{OT.env})"],
        ['Config', OT::Config.path],
        ['Redis', "#{redis_info['redis_version']} (#{Familia.uri.serverid})"],
        ['Familia', "v#{Familia::VERSION}"],
        ['I18n', OT.i18n_enabled],
        ['Diagnostics', OT.d9s_enabled],
      ]

      # Add locales if i18n is enabled
      if OT.i18n_enabled
        system_rows << ['Locales', @locales.keys.join(', ')]
      end

      system_table = TTY::Table.new(
        header: ['Component', 'Value'],
        rows: system_rows,
      )

      output << system_table.render(:unicode,
        padding: [0, 1],
        multiline: true,
        column_widths: [15, 79]
      )
      output << ""

      # SECTION 2: Authentication Settings
      auth_rows = []

      if colonels.empty?
        auth_rows << ['Colonels', 'No colonels configured ⚠️']
      else
        auth_rows << ['Colonels', colonels.join(', ')]
      end

      if site_config.key?(:authentication)
        auth_settings = site_config[:authentication].map { |k,v| "#{k}=#{v}" }.join(', ')
        auth_rows << ['Auth Settings', auth_settings]
      end

      unless auth_rows.empty?
        auth_table = TTY::Table.new(
          header: ['Authentication', 'Details'],
          rows: auth_rows
        )

        output << auth_table.render(:unicode,
          padding: [0, 1],
          multiline: true,
          column_widths: [15, 79],
        )
        output << ""
      end

      # SECTION 3: Features Configuration
      feature_rows = []

      # Plans section
      if site_config.dig(:plans, :enabled)
        begin
          feature_rows << ['Plans', OT::Plan.plans.keys.join(', ')]
        rescue => e
          feature_rows << ['Plans', "Error: #{e.message}"]
        end
      end

      # Domains and regions
      [:domains, :regions].each do |key|
        if site_config.key?(key) && !site_config[key].empty?
          # Format as JSON for better readability with nested structures
          formatted_value = site_config[key].is_a?(Hash) ?
            site_config[key].map { |k,v| "#{k}=#{v.is_a?(Hash) || v.is_a?(Array) ? v.to_json : v}" }.join(', ') :
            site_config[key].to_s
          feature_rows << [key.to_s.capitalize, formatted_value]
        end
      end

      unless feature_rows.empty?
        feature_table = TTY::Table.new(
          header: ['Features', 'Configuration'],
          rows: feature_rows
        )

        output << feature_table.render(:unicode,
          padding: [0, 1],
          multiline: true,
          column_widths: [15, 79]
        )
        output << ""
      end

      # SECTION 4: Email Configuration
      if email_config && !email_config.empty?
        begin
          mail_rows = [
            ['Mailer', @emailer],
            ['Mode', email_config[:mode]],
            ['From', "'#{email_config[:fromname]} <#{email_config[:from]}>'"],
            ['Host', "#{email_config[:host]}:#{email_config[:port]}"],
            ['Region', email_config[:region]],
            ['TLS', email_config[:tls]],
            ['Auth', email_config[:auth]]
          ].reject { |row| row[1].nil? || row[1].to_s.empty? }

          if !mail_rows.empty?
            mail_table = TTY::Table.new(
              header: ['Mail Config', 'Value'],
              rows: mail_rows
            )

            output << mail_table.render(:unicode,
              padding: [0, 1],
              multiline: true,
              column_widths: [15, 79]
            )
            output << ""
          end
        rescue => e
          output << "Error rendering mail table: #{e.message}"
          output << ""
        end
      end

      # SECTION 5: Development and Experimental Settings
      dev_rows = []

      [:development, :experimental].each do |key|
        if config_value = OT.conf.fetch(key, false)
          # Format as JSON for better readability of nested structures
          formatted_value = config_value.map do |k, v|
            value_str = (v.is_a?(Hash) || v.is_a?(Array)) ? v.to_json : v.to_s
            "#{k}=#{value_str}"
          end.join(', ')
          dev_rows << [key.to_s.capitalize, formatted_value]
        end
      end

      unless dev_rows.empty?
        dev_table = TTY::Table.new(
          header: ['Development', 'Settings'],
          rows: dev_rows
        )

        output << dev_table.render(:unicode,
          padding: [0, 1],
          multiline: true,
          column_widths: [15, 79]
        )
        output << ""
      end

      # SECTION 6: Secret Options (separate due to its importance)
      secret_options = OT.conf.dig(:site, :secret_options)
      if secret_options
        secret_table = TTY::Table.new(
          header: ['Security', 'Configuration'],
          rows: [['Secret Options', secret_options.to_json]]
        )

        output << secret_table.render(:unicode,
          padding: [0, 1],
          multiline: true,
          column_widths: [15, 79]
        )
        output << ""
      end

      # Footer
      output << "#{'-' * 75}"

      # Output everything with a single OT.li call
      OT.li output.join("\n")
    end

  end
end
