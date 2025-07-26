# lib/onetime/services/system/print_boot_receipt.rb

require 'json'

require_relative 'print_boot_receipt/boot_receipt_generator'
require_relative 'print_boot_receipt/boot_receipt_sections'
require_relative '../service_provider'

module Onetime
  module Services
    module System
      ##
      # PrintBootReceipt
      #
      # Prints a formatted banner with system and configuration information at startup.
      # Now uses ReceiptGenerator for consistent formatting.
      #
      class PrintBootReceipt < ServiceProvider
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
          site_config  = config.fetch('site')
          redis_info   = Familia.dbclient.info
          colonels     = site_config.dig(:authentication, :colonels) || []
          # email_config = config.fetch('emailer', {})
          # emailer      = get_state(:emailer)

          generator = BootReceiptGenerator.new(width: 60)

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

          i18n_enabled = config['i18n']['enabled']
          d9s_enabled  = config['diagnostics']['enabled']
          system_section.add_row('Internationalization', i18n_enabled ? 'enabled' : 'disabled',
            status: i18n_enabled ? 'OK' : 'OFF'
          )
          system_section.add_row('Diagnostics', d9s_enabled ? 'enabled' : 'disabled',
            status: d9s_enabled ? 'OK' : 'OFF'
          )

          generator.add_section(system_section)

          # Locale support (wrapped text)
          if i18n_enabled && !config['i18n']['locales'].empty?
            locales_text = config['i18n']['locales'].join(', ')
            generator.add_section(WrapTextSection.new(generator,
              title: 'LOCALE SUPPORT: ',
              content: locales_text,
            ),
                                 )
          end

          # Development settings
          if config.fetch('development', false)
            dev_section = SystemStatusSection.new(generator,
              title: ['DEVELOPMENT SETTINGS', 'VALUE', 'STATUS'],
            )

            dev_config = config['development']
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
          if config.fetch('experimental', false)
            exp_section = SystemStatusSection.new(generator,
              title: ['EXPERIMENTAL FEATURES', 'VALUE', 'STATUS'],
            )

            exp_config = config['experimental']
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
            title: ['AUTHENTICATION CONFIG', 'VALUE', 'STATUS'],
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

          # Features: Domains and Regions
          features_section = SystemStatusSection.new(generator,
            title: ['FEATURES', 'STATUS/CONFIG', 'STATUS'],
          )

          # Domains configuration - look under features.domains
          domains_config = config.dig('features', 'domains') || {}
          domains_enabled = domains_config['enabled'] || false
          if domains_enabled
            features_section.add_row('Custom Domains', 'enabled', status: 'ON')
          else
            features_section.add_row('Custom Domains', 'disabled', status: 'OFF')
          end

          # Regions configuration - look under features.regions
          regions_config = config.dig('features', 'regions') || {}
          regions_enabled = regions_config['enabled'] || false
          if regions_enabled
            features_section.add_row('Regions', 'enabled', status: 'ON')
            # Show jurisdiction count
            jurisdictions = regions_config.dig('jurisdictions') || []
            if jurisdictions.is_a?(Array) && jurisdictions.any?
              features_section.add_row('Jurisdictions', "#{jurisdictions.length} configured", status: 'OK')
            end
          else
            features_section.add_row('Regions', 'disabled', status: 'OFF')
          end

          generator.add_section(features_section)

          # Show detailed configuration for enabled features
          if domains_enabled && domains_config.is_a?(Hash) && domains_config.size > 1
            domain_details = domains_config.reject { |k,v| k == 'enabled' }
                                           .map { |k,v| "#{k}=#{v}" }
                                           .join(', ')
            unless domain_details.empty?
              generator.add_section(WrapTextSection.new(generator,
                title: 'DOMAIN CONFIG: ',
                content: domain_details,
              ))
            end
          end

          # Show jurisdiction details if regions are enabled
          if regions_enabled && jurisdictions.is_a?(Array) && jurisdictions.any?
            jurisdiction_details = jurisdictions.map do |j|
              if j.is_a?(Hash)
                id = j[:identifier] || j['identifier']
                name = j['display_name'] || j[:display_name]
                domain = j['domain'] || j[:domain]
                "#{id}: #{name} (#{domain})"
              else
                j.to_s
              end
            end.join(', ')

            generator.add_section(WrapTextSection.new(generator,
              title: 'JURISDICTIONS: ',
              content: jurisdiction_details,
            ))
          end

          # Billing configuration
          billing_config = config.dig('billing') || {}
          billing_enabled = billing_config['enabled'] || false
          if billing_enabled
            billing_section = SystemStatusSection.new(generator,
              title: ['BILLING CONFIG', 'VALUE', 'STATUS'],
            )

            billing_section.add_row('Plans/Billing', 'enabled', status: 'ON')

            if billing_config['stripe_key']
              stripe_key_preview = billing_config['stripe_key'].to_s
              if stripe_key_preview.length > 20
                stripe_key_preview = stripe_key_preview[0..16] + '...'
              end
              billing_section.add_row('Stripe Key', stripe_key_preview, status: 'OK')
            end

            payment_links = billing_config.dig('payment_links') || {}
            if payment_links.any?
              billing_section.add_row('Payment Links', "#{payment_links.keys.length} tiers", status: 'OK')
            end

            generator.add_section(billing_section)
          end

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
