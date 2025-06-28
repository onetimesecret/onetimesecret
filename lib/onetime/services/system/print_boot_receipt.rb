# lib/onetime/services/system/print_boot_receipt.rb

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
      # PrintBootReceipt
      #
      # Prints a formatted banner with system and configuration information at startup.
      # Now uses ReceiptGenerator for consistent formatting.
      #
      class PrintBootReceipt < ServiceProvider
        using Onetime::IndifferentHashAccess

        def initialize
          super(:boot_receipt, type: TYPE_INFO, priority: 90)
        end

        ##
        # Print the system banner with configuration and status information
        #
        # @param config [Hash] Frozen application configuration
        def start(config)
          debug('Printing boot receipt...')
          print_enhanced_boot_receipt(config)
        end

        private

        def print_enhanced_boot_receipt(config)
          site_config  = config.fetch(:site)
          redis_info   = Familia.redis.info
          colonels     = site_config.dig(:authentication, :colonels) || []
          # email_config = config.fetch(:emailer, {})
          # emailer      = get_state(:emailer)

          generator = ReceiptGenerator.new(width: 60)

          # System header
          generator.add_section(SystemHeaderSection.new(generator,
            app_name: 'ONETIME SECRET',
            version: "Version: v#{OT::VERSION}",
            subtitle: 'System Initialization Report',
            environment: OT.env,
          ),
                               )

          # System components with status
          system_section = SystemStatusSection.new(generator,
            title: %w[COMPONENT VERSION/VALUE STATUS],
          )

          config_path = Onetime::Utils.pretty_path(OT::Boot.configurator.config_path)
          system_section.add_row('Config File', config_path, status: 'OK')
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
              title: ['DEVELOPMENT SETTINGS', 'VALUE'],
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
              title: ['EXPERIMENTAL FEATURES', 'VALUE'],
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
            title: ['AUTHENTICATION CONFIG', 'VALUE'],
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

          status  = 'In progress'
          message = 'System is initializing'

          # Status summary
          generator.add_section(StatusSummarySection.new(generator,
            status: status,
            message: message,
          ),
                               )

          # Footer
          generator.add_section(FooterSection.new(generator,
            messages: [
              'Thank you for using ONETIME APP',
              # 'Secure secret sharing service',
              'Your own private secret service',
              'https://github.com/onetimesecret',
            ],
          ),
                               )

          OT.li generator.generate
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
