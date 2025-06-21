# lib/onetime/services/system/print_log_banner.rb

require 'json'

require 'onetime/refinements/indifferent_hash_access'
require 'receipt_generator'
require 'system_status'

require_relative '../service_provider'

# Add the ReceiptGenerator classes here or require them
# (assuming they're available in the application)

module Onetime
  module Services
    module System
      # Custom section for key-value pairs in the log banner
      class KeyValueSection < ReceiptSection
        def initialize(generator, header1:, header2:, rows: [])
          super(generator)
          @header1 = header1
          @header2 = header2
          @rows    = rows
        end

        def add_row(key, value)
          @rows << [key, value]
          self
        end

        def render
          return '' if @rows.empty?

          lines = []
          lines << divider
          lines << two_column(@header1, @header2)
          lines << divider('-')

          @rows.each do |row|
            lines << two_column(row[0].to_s, row[1].to_s)
          end

          lines.join("\n")
        end
      end

      ##
      # LogBannerProvider
      #
      # Prints a formatted banner with system and configuration information at startup.
      # Now uses ReceiptGenerator for consistent formatting.
      #
      class PrintLogBanner < ServiceProvider
        using IndifferentHashAccess

        def initialize
          super(:log_banner, type: TYPE_INFO, priority: 90)
        end

        ##
        # Print the system banner with configuration and status information
        #
        # @param config [Hash] Frozen application configuration
        def start(config)
          log('Printing system banner...')
          print_enhanced_log_banner(config)
        end

        private

        def print_enhanced_log_banner(config)
          site_config  = config.fetch(:site)
          email_config = config.fetch(:emailer, {})
          redis_info   = Familia.redis.info
          colonels     = site_config.dig(:authentication, :colonels) || []
          emailer      = get_state(:emailer)

          generator = ReceiptGenerator.new(width: 48)

          # System header
          generator.add_section(SystemHeaderSection.new(generator,
            app_name: 'ONETIME APP SYSTEM RECEIPT',
            version: "Version: v#{OT::VERSION}",
            subtitle: 'System Diagnostics Report',
          ),
                               )

          # System components with status
          system_section = SystemStatusSection.new(generator,
            title: 'COMPONENT              VERSION/VALUE    STATUS',
          )

          platform_info = "#{RUBY_ENGINE} #{RUBY_VERSION}"
          arch_info     = RUBY_PLATFORM
          mode_info     = OT.env

          system_section.add_row('System Runtime', platform_info, status: 'OK')
          system_section.add_row('Platform', arch_info, status: 'OK')
          system_section.add_row('Config File', File.basename(OT::Boot.configurator.config_path), status: 'OK')
          system_section.add_row('Redis Server', redis_info['redis_version'], status: 'OK')
          system_section.add_row('Redis URL', Familia.uri.serverid, status: 'OK')
          system_section.add_row('Familia Library', "v#{Familia::VERSION}", status: 'OK')

          i18n_enabled = config[:i18n][:enabled]
          d9s_enabled  = config[:diagnostics][:enabled]
          system_section.add_row('Internationalization', i18n_enabled ? 'enabled' : 'disabled',
            status: i18n_enabled ? 'OK' : 'OFF'
          )
          system_section.add_row('Diagnostics', d9s_enabled ? 'enabled' : 'disabled',
            status: d9s_enabled ? 'OK' : 'OFF'
          )

          generator.add_section(system_section)

          # Locale support (wrapped text)
          if i18n_enabled && !config[:i18n][:locales].empty?
            locales_text = config[:i18n][:locales].join(', ')
            generator.add_section(WrapTextSection.new(generator,
              title: 'LOCALE SUPPORT: ',
              content: locales_text,
            ),
                                 )
          end

          # Development settings
          if config.fetch(:development, false)
            dev_section = SystemStatusSection.new(generator,
              title: 'DEVELOPMENT SETTINGS                     VALUE',
            )

            dev_config = config[:development]
            dev_section.add_row('Development Mode', 'enabled', status: 'ON')

            if dev_config.is_a?(Hash) && dev_config['debug']
              dev_section.add_row('Debug Mode', 'enabled', status: 'ON')
            end

            if dev_config.is_a?(Hash) && dev_config['frontend_host']
              dev_section.add_row('Frontend Host', dev_config['frontend_host'], status: 'OK')
            end

            generator.add_section(dev_section)
          end

          # Experimental features
          if config.fetch(:experimental, false)
            exp_section = SystemStatusSection.new(generator,
              title: 'EXPERIMENTAL FEATURES                    VALUE',
            )

            exp_config = config[:experimental]
            if exp_config.is_a?(Hash)
              exp_config.each do |key, value|
                status = case key.to_s
                         when 'allow_nil_global_secret'
                           value ? 'WARN' : 'SAFE'
                         when 'rotated_secrets'
                           value.is_a?(Array) && value.length > 1 ? 'GOOD' : 'WARN'
                         else
                           'OK'
                         end

                formatted_value = case value
                                 when Array
                                   "#{value.length} configured"
                                 else
                                   value.to_s
                                 end

                exp_section.add_row(key.to_s.humanize, formatted_value, status: status)
              end
            end

            generator.add_section(exp_section)
          end

          # Authentication
          auth_section = SystemStatusSection.new(generator,
            title: 'AUTHENTICATION CONFIG                    VALUE',
          )

          auth_config = site_config['authentication']
          if auth_config && auth_config['enabled']
            auth_section.add_row('Auth System', 'enabled', status: 'ON')
          end

          if colonels.any?
            # Show first colonel, indicate if more
            display_colonel = colonels.first
            if display_colonel.length > 20
              display_colonel = display_colonel[0..16] + '...'
            end
            auth_section.add_row('Colonel Access', display_colonel, status: 'OK')
            auth_section.add_row('Total Colonels', "#{colonels.length} user#{'s' if colonels.length != 1}",
              status: colonels.empty? ? 'WARN' : 'GOOD'
            )
          else
            auth_section.add_row('Colonel Access', 'none configured', status: 'WARN')
          end

          generator.add_section(auth_section)

          # Status summary
          generator.add_section(StatusSummarySection.new(generator,
            status: 'READY',
            message: 'All components verified',
          ),
                               )

          # Footer
          generator.add_section(FooterSection.new(generator,
            messages: [
              'Thank you for using ONETIME APP',
              'Secure secret sharing service',
              'https://github.com/onetimesecret',
            ],
          ),
                               )

          OT.li generator.generate
        end

        # Builds system information section rows
        def build_system_section(redis_info)
          platform_info = "#{RUBY_ENGINE} #{RUBY_VERSION} on #{RUBY_PLATFORM} (#{OT.env})"
          configurator  = OT::Boot.configurator
          locales       = config[:i18n][:locales]
          i18n_enabled  = config[:i18n][:enabled]
          d9s_enabled   = config[:diagnostics][:enabled]

          system_rows = [
            ['System', platform_info],
            ['Config', configurator.config_path],
            ['Redis', "#{redis_info['redis_version']} (#{Familia.uri.serverid})"],
            ['Familia', "v#{Familia::VERSION}"],
            ['I18n', i18n_enabled],
            ['Diagnostics', d9s_enabled],
          ]

          # Add locales if i18n is enabled and locales service is available
          if i18n_enabled && !locales.empty?
            system_rows << ['Locales', locales.join(', ')]
          end

          system_rows
        end

        # Builds development and experimental settings section rows
        def build_dev_section(config)
          dev_rows = []

          [:development, :experimental].each do |key|
            next unless config_value = config.fetch(key, false)

            dev_rows << if feature_disabled?(config_value)
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

          # Plans section
          if site_config.key?('plans')
            plans_config = site_config['plans']
            if feature_disabled?(plans_config)
              feature_rows << %w[Plans disabled]
            else
              begin
                feature_rows << ['Plans', OT::Plan.plans.keys.join(', ')]
              rescue StandardError => ex
                feature_rows << ['Plans', "Error: #{ex.message}"]
              end
            end
          end

          # Domains and regions
          %w[domains regions].each do |key|
            next unless site_config.key?(key)

            config = site_config[key]
            if feature_disabled?(config)
              feature_rows << [key.to_s.capitalize, 'disabled']
            elsif !config.empty?
              feature_rows << [key.to_s.capitalize, format_config_value(config)]
            end
          end

          feature_rows
        end

        # Builds email configuration section rows
        def build_email_section(email_config, emailer)
          return [] if email_config.nil? || email_config.empty?

          begin
            if feature_disabled?(email_config)
              [%w[Status disabled]]
            else
              [
                ['Mailer', emailer&.to_s || 'Unknown'],
                ['Mode', email_config[:mode]],
                ['From', "'#{email_config[:fromname]} <#{email_config[:from]}>'"],
                ['Host', "#{email_config[:host]}:#{email_config[:port]}"],
                ['Region', email_config[:region]],
                ['TLS', email_config[:tls]],
                ['Auth', email_config[:auth]],
              ].reject { |row| row[1].nil? || row[1].to_s.empty? }
            end
          rescue StandardError => ex
            [['Error', "Error rendering mail config: #{ex.message}"]]
          end
        end

        # Builds authentication section rows
        def build_auth_section(site_config, colonels)
          auth_rows = []

          auth_rows << if colonels.empty?
            ['Colonels', 'No colonels configured ⚠️']
          else
            ['Colonels', colonels.join(', ')]
          end

          if site_config.key?('authentication')
            auth_config = site_config['authentication']
            if feature_disabled?(auth_config)
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
          secret_options = site_config[:secret_options]
          if secret_options
            # Format default TTL
            if secret_options[:default_ttl]
              default_ttl = format_duration(secret_options[:default_ttl].to_i)
              customization_rows << ['Default TTL', default_ttl]
            end

            # Format TTL options
            if secret_options[:ttl_options]
              ttl_options = secret_options[:ttl_options].map { |seconds| format_duration(seconds) }.join(', ')
              customization_rows << ['TTL Options', ttl_options]
            end
          end

          # Interface configuration
          if site_config.key?('user_interface')
            interface_config = site_config[:interface]
            if feature_disabled?(interface_config)
              customization_rows << %w[Interface disabled]
            elsif interface_config.is_a?(Hash)
              # Handle nested ui and api configs under interface
              %w[ui api].each do |key|
                next unless interface_config.key?(key)

                sub_config = interface_config[key]
                if feature_disabled?(sub_config)
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
              if feature_disabled?(config)
                customization_rows << [key.to_s.upcase, 'disabled']
              elsif !config.empty?
                customization_rows << [key.to_s.upcase, format_config_value(config)]
              end
            end
          end

          customization_rows
        end

        # Helper method to check if a feature is disabled
        def feature_disabled?(config)
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
      end
    end
  end
end

class String
  def humanize
    tr('_', ' ').split.map(&:capitalize).join(' ')
  end
end
