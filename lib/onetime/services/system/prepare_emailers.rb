# lib/onetime/services/system/prepare_emailers.rb

require 'onetime/refinements/indifferent_hash_access'
require_relative '../service_provider'

module Onetime
  module Services
    module System
      ##
      # Emailer Provider
      #
      # Configures the email service based on the configured mode (sendgrid, ses, smtp).
      # Sets up the appropriate mailer class and makes it available system-wide.
      #
      class PrepareEmailers < ServiceProvider

        attr_reader :emailer

        def initialize
          super(:emailer, type: TYPE_INSTANCE, priority: 30)
        end

        ##
        # Configure the emailer based on the configured mode
        #
        # @param config [Hash] Application configuration
        def start(config)
          debug('Configuring email service...')

          mail_mode = config.dig(:mail, :connection, :mode).to_s.to_sym

          mailer_class = case mail_mode
          when :sendgrid
            Onetime::Mail::Mailer::SendGridMailer
          when :ses
            Onetime::Mail::Mailer::SESMailer
          when :smtp
            Onetime::Mail::Mailer::SMTPMailer
          else
            OT.le "Unsupported mail mode: '#{mail_mode}', falling back to SMTP"
            Onetime::Mail::Mailer::SMTPMailer
          end

          mailer_class.setup(config)
          @emailer = mailer_class

          set_state(:mailer_class, mailer_class)
          set_state(:emailer, @emailer)

          register_provider(:emailer, self)
          debug("Email service configured with #{mail_mode} provider")
        end
      end

    end
  end
end
