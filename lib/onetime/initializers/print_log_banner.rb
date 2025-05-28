# lib/onetime/initializers/print_log_banner.rb

require 'tty-table'

module Onetime
  module Initializers

    def print_log_banner
      site_config = OT.conf.fetch(:site) # if :site is missing we got real problems
      email_config = OT.conf.fetch(:emailer, {})
      redis_info = Familia.redis.info
      colonels = site_config.dig(:authentication, :colonels) || []

      # Header banner
      OT.li "---  ONETIME #{OT.mode} v#{OT::VERSION.inspect}  #{'---' * 3}"

      # Prepare system information table
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

      # Create system information table
      system_table = TTY::Table.new(
        header: ['Component', 'Value'],
        rows: system_rows,
      )

      OT.li "", system_table.render(:unicode,
        padding: [0, 1],
        multiline: true,
        column_widths: [15, 79]
      )

      # Authentication and permissions table
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

        OT.li "", auth_table.render(:unicode,
          padding: [0, 1],
          multiline: true,
          column_widths: [15, 79]
        )
      end

      # Plans table (if enabled)
      if site_config.dig(:plans, :enabled)
        begin
          plans_table = TTY::Table.new(
            header: ['Plans', 'Available'],
            rows: [['Active Plans', OT::Plan.plans.keys.join(', ')]]
          )

          OT.li "", plans_table.render(:unicode,
            padding: [0, 1],
            multiline: true,
            column_widths: [15, 79]
          )
        rescue => e
          OT.le "Error rendering plans table: #{e.message}"
        end
      end

      # Email configuration table
      if email_config && !email_config.empty?
        begin
          mail_rows = [
            ['Mode', email_config[:mode]],
            ['From', "'#{email_config[:fromname]} <#{email_config[:from]}>'"],
            ['Host', "#{email_config[:host]}:#{email_config[:port]}"],
            ['Region', email_config[:region]],
            ['User', email_config[:user]],
            ['TLS', email_config[:tls]],
            ['Auth', email_config[:auth]] # this is an smtp feature and not credentials
          ].reject { |row| row[1].nil? || row[1].to_s.empty? }

          if !mail_rows.empty?
            mail_table = TTY::Table.new(
              header: ['Mail Config', 'Value'],
              rows: [['Mailer', @emailer]] + mail_rows
            )

            OT.li "", mail_table.render(:unicode,
              padding: [0, 1],
              multiline: true,
              column_widths: [15, 79]
            )
          end
        rescue => e
          OT.le "Error rendering mail table: #{e.message}"
        end
      end

      # Configuration sections table (domains, regions)
      config_rows = []
      [:domains, :regions].each do |key|
        if site_config.key?(key)
          config_value = site_config[key].map { |k,v| "#{k}=#{v}" }.join(', ')
          config_rows << [key.to_s.capitalize, config_value]
        end
      end

      # Optional top-level configuration sections
      [:development, :experimental].each do |key|
        if config_value = OT.conf.fetch(key, false)
          formatted_value = config_value.map { |k,v| "#{k}=#{v}" }.join(', ')
          config_rows << [key.to_s.capitalize, formatted_value]
        end
      end

      # Secret options
      secret_options = OT.conf.dig(:site, :secret_options)
      if secret_options
        config_rows << ['Secret Options', secret_options.to_s]
      end

      unless config_rows.empty?
        config_table = TTY::Table.new(
          header: ['Configuration', 'Settings'],
          rows: config_rows
        )

        OT.li "", config_table.render(:unicode,
          padding: [0, 1],
          multiline: true,
          column_widths: [15, 79]
        )
      end

      # Footer
      OT.li "#{'-' * 75}"
    end

  end
end
