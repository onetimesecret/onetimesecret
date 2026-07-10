# lib/onetime/mail/mailer.rb
#
# frozen_string_literal: true

require_relative 'delivery/base'
require_relative 'delivery/disabled'
require_relative 'delivery/logger'
require_relative 'delivery/smtp'
require_relative 'delivery/ses'
require_relative 'delivery/sendgrid'
require_relative 'delivery/lettermint'
require_relative 'views/base'
require_relative 'views/secret_link'
require_relative 'views/welcome'
require_relative 'views/password_request'
require_relative 'views/incoming_secret'
require_relative 'views/feedback_email'
require_relative 'views/secret_revealed'
require_relative 'views/expiration_warning'
require_relative 'views/organization_invitation'
require_relative 'views/magic_link'
require_relative 'views/email_change_confirmation'
require_relative 'views/email_change_requested'
require_relative 'views/email_changed'
require_relative 'views/new_login_alert'
require_relative 'views/mfa_enabled'
require_relative 'views/mfa_disabled'
require_relative 'views/password_changed'
require_relative 'views/role_changed'
require_relative 'views/member_removed'
require_relative 'views/organization_deleted'
require_relative 'views/trial_expiring'
require_relative 'views/payment_failed'
require_relative 'views/payment_receipt'
require_relative 'views/subscription_changed'

module Onetime
  module Mail
    # Unified mailer for Onetime Secret.
    #
    # Provides a simple interface for sending emails with support for
    # multiple delivery backends (SMTP, SES, SendGrid) and ERB templates.
    #
    # Configuration is determined from:
    #   1. OT.conf['emailer'] settings
    #   2. Environment variables (fallback)
    #
    # Example usage:
    #   # Send a secret link email
    #   Onetime::Mail::Mailer.deliver(:secret_link,
    #     secret: secret_obj,
    #     recipient: "user@example.com",
    #     sender_email: "sender@example.com"
    #   )
    #
    #   # Using template class directly
    #   template = Onetime::Mail::Templates::SecretLink.new(
    #     secret: secret,
    #     recipient: "user@example.com",
    #     sender_email: "sender@example.com"
    #   )
    #   Onetime::Mail::Mailer.deliver_template(template)
    #
    class Mailer
      class << self
        # Deliver an email using a named template
        # @param template_name [Symbol] Template name (:secret_link, :welcome, etc.)
        # @param data [Hash] Template data
        # @param locale [String] Locale code (default: 'en')
        # @return [Object] Delivery response
        def deliver(template_name, data = {}, locale: 'en', sender_config: nil)
          template_class = template_class_for(template_name)
          template       = template_class.new(data, locale: locale)
          deliver_template(template, sender_config: sender_config)
        end

        # Deliver an email using a template instance
        # @param template [Templates::Base] Template instance
        # @return [Object] Delivery response
        def deliver_template(template, sender_config: nil)
          backend    = resolve_backend(sender_config)
          use_sender = sender_config&.enabled? && sender_config.verified?

          email = template.to_email(
            from: use_sender ? sender_config.from_address : from_address,
            reply_to: use_sender && sender_config.reply_to ? sender_config.reply_to : reply_to_address(template),
          )
          backend.deliver(email)
        end

        # Deliver a raw email hash (for Rodauth integration)
        # @param email [Hash] Email with :to, :from, :subject, :body keys
        # @return [Object] Delivery response
        def deliver_raw(email, sender_config: nil)
          backend    = resolve_backend(sender_config)
          use_sender = sender_config&.enabled? && sender_config.verified?

          normalized = {
            to: extract_email_address(email[:to]),
            from: use_sender ? sender_config.from_address : (extract_email_address(email[:from]) || from_address),
            reply_to: use_sender && sender_config.reply_to ? sender_config.reply_to : email[:reply_to]&.to_s,
            subject: email[:subject]&.to_s,
            text_body: email[:body]&.to_s,
            html_body: email[:html_body]&.to_s,
          }
          backend.deliver(normalized)
        end

        # Get the configured delivery backend
        # @return [Delivery::Base]
        def delivery_backend
          @delivery_backend ||= create_delivery_backend
        end

        # Reset the delivery backend (useful for testing)
        def reset!
          @delivery_backend = nil
        end

        # Get the configured from address
        # @return [String]
        def from_address
          conf = emailer_config
          conf['from'] || ENV['FROM_EMAIL'] || 'noreply@example.com'
        end

        # Get the configured from name
        # @return [String, nil]
        def from_name
          conf = emailer_config
          if conf['from_name']
            conf['from_name']
          elsif conf['fromname']
            log_info "[mail] DEPRECATION: 'fromname' config is deprecated since v0.23, use 'from_name' instead"
            conf['fromname']
          end
        end

        # Get provider-specific credentials for API access
        # @param provider [String] Provider name ('ses', 'sendgrid', 'lettermint', 'smtp')
        # @return [Hash] Provider credentials from OT.conf['emailer']
        # @example
        #   Onetime::Mail::Mailer.provider_credentials('ses')
        #   # => { 'region' => 'us-east-1', 'access_key_id' => '...', 'secret_access_key' => '...' }
        def provider_credentials(provider)
          config = build_provider_config(provider)

          # Sender-domain provisioning is decoupled from the install-level
          # transactional mailer (EMAILER_MODE / EMAILER_REGION / SMTP_*).
          # Provider-specific settings come from email_providers.<provider> so an
          # operator can run, e.g., SMTP for transactional delivery while
          # provisioning sender domains through SES — without EMAILER_REGION or
          # the SMTP credentials (SMTP_USERNAME/SMTP_PASSWORD, which
          # build_provider_config resolves as emailer.user/pass) leaking into the
          # SES provisioning client. email_providers.ses.{region,access_key_id,
          # secret_access_key} default to the dedicated CUSTOM_MAIL_SES_* vars
          # (falling back to AWS_REGION / AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY),
          # so these override the emailer-derived values whenever set. When none
          # are set (e.g. EMAILER_MODE=ses, where emailer.user is the AWS key),
          # the override is skipped and the emailer-derived value is kept. The
          # delivery path (create_delivery_backend) uses emailer config directly.
          if provider.to_s.downcase == 'ses'
            ses_conf = provider_config('ses')
            %w[region access_key_id secret_access_key].each do |key|
              value = ses_conf[key] || ses_conf[key.to_sym]
              config[key] = value.to_s unless value.to_s.empty?
            end
          end

          config
        end

        # Returns the provider for custom mail sender domain provisioning.
        #
        # Resolves, in order: the explicit `sender_provider` emailer config,
        # then the sending transport (determine_provider, e.g. EMAILER_MODE).
        # Public because per-domain sender configs fall back to it when they
        # carry no explicit provider (see MailerConfig#effective_provider).
        #
        # @return [String] Lowercased provider name (e.g. 'ses', 'lettermint')
        def determine_sender_provider
          conf = emailer_config
          sp   = conf['sender_provider']
          return sp.to_s.downcase.strip if sp.is_a?(String) && !sp.strip.empty?

          determine_provider
        end

        private

        def template_class_for(name)
          case name.to_sym
          when :secret_link
            Templates::SecretLink
          when :welcome
            Templates::Welcome
          when :password_request
            Templates::PasswordRequest
          when :incoming_secret
            Templates::IncomingSecret
          when :feedback_email
            Templates::FeedbackEmail
          when :secret_revealed
            Templates::SecretRevealed
          when :expiration_warning
            Templates::ExpirationWarning
          when :organization_invitation
            Templates::OrganizationInvitation
          when :email_change_confirmation
            Templates::EmailChangeConfirmation
          when :email_change_requested
            Templates::EmailChangeRequested
          when :email_changed
            Templates::EmailChanged
          when :new_login_alert
            Templates::NewLoginAlert
          when :mfa_enabled
            Templates::MfaEnabled
          when :mfa_disabled
            Templates::MfaDisabled
          when :password_changed
            Templates::PasswordChanged
          when :role_changed
            Templates::RoleChanged
          when :member_removed
            Templates::MemberRemoved
          when :organization_deleted
            Templates::OrganizationDeleted
          when :trial_expiring
            Templates::TrialExpiring
          when :payment_failed
            Templates::PaymentFailed
          when :payment_receipt
            Templates::PaymentReceipt
          when :subscription_changed
            Templates::SubscriptionChanged
          else
            raise ArgumentError, "Unknown template: #{name}"
          end
        end

        def create_delivery_backend
          provider = determine_provider
          config   = build_provider_config(provider)

          log_info "[mail] Using #{provider} delivery backend"

          case provider
          when 'disabled', 'none'
            Delivery::Disabled.new(config)
          when 'smtp'
            Delivery::SMTP.new(config)
          when 'ses'
            Delivery::SES.new(config)
          when 'sendgrid'
            Delivery::SendGrid.new(config)
          when 'lettermint'
            Delivery::Lettermint.new(config)
          when 'logger'
            Delivery::Logger.new(config)
          else
            log_error "[mail] Unknown provider '#{provider}', falling back to logger"
            Delivery::Logger.new(config)
          end
        end

        # Returns the delivery backend for the given sender config.
        # Currently always uses the global backend — per-domain sender
        # identity is applied at the email level (from/reply_to override),
        # not at the backend level.
        def resolve_backend(_sender_config)
          delivery_backend
        end

        # Logging helpers that work with or without OT defined
        def log_info(message)
          if defined?(OT) && OT.respond_to?(:info)
            OT.info message
          else
            puts message
          end
        end

        def log_error(message)
          if defined?(OT) && OT.respond_to?(:le)
            OT.le message
          else
            warn message
          end
        end

        def determine_provider
          conf = emailer_config
          mode = conf['mode']&.to_s&.downcase

          return mode if mode && !mode.empty?

          # Test environment always uses logger
          return 'logger' if ENV['RACK_ENV'] == 'test'

          # Auto-detect provider from config keys (first match wins):
          #   region + user        -> ses (AWS SES credentials)
          #   sendgrid_api_key     -> sendgrid
          #   lettermint_api_token -> lettermint
          #   host                 -> smtp (generic SMTP)
          #   (none)               -> logger (safe fallback)
          if conf['region'] && conf['user']
            'ses' # AWS SES uses region + AWS credentials
          elsif conf['sendgrid_api_key']
            'sendgrid'
          elsif conf['lettermint_api_token']
            'lettermint'
          elsif conf['host']
            'smtp'
          else
            'logger' # fallback
          end
        end

        def build_provider_config(provider)
          conf = emailer_config

          case provider
          when 'smtp'
            {
              'host' => conf['host'] || ENV.fetch('SMTP_HOST', nil),
              'port' => conf['port'] || ENV.fetch('SMTP_PORT', nil),
              'username' => conf['user'] || ENV.fetch('SMTP_USERNAME', nil),
              'password' => conf['pass'] || ENV.fetch('SMTP_PASSWORD', nil),
              'domain' => conf['domain'] || ENV.fetch('SMTP_DOMAIN', nil),
              'tls' => conf['tls'],
              'allow_unauthenticated_fallback' => conf['allow_unauthenticated_fallback'],
            }
          when 'ses'
            {
              'region' => conf['region'] || ENV.fetch('AWS_REGION', nil),
              'access_key_id' => conf['user'] || ENV.fetch('AWS_ACCESS_KEY_ID', nil),
              'secret_access_key' => conf['pass'] || ENV.fetch('AWS_SECRET_ACCESS_KEY', nil),
            }
          when 'sendgrid'
            {
              'api_key' => conf['sendgrid_api_key'] || conf['pass'] || ENV.fetch('SENDGRID_API_KEY', nil),
            }
          when 'lettermint'
            lm_conf = provider_config('lettermint')
            {
              # Sending API token (x-lettermint-token header) - for email delivery
              'api_token' => conf['lettermint_api_token'] || lm_conf['api_token'] || conf['pass'] || ENV.fetch('LETTERMINT_API_TOKEN', nil),
              # Team API token (Authorization: Bearer header) - for domain provisioning
              'team_token' => conf['lettermint_team_token'] || lm_conf['team_token'] || ENV.fetch('LETTERMINT_TEAM_TOKEN', nil),
              'base_url' => conf['lettermint_base_url'] || lm_conf['api_base_url'] || ENV.fetch('LETTERMINT_BASE_URL', nil),
              'timeout' => conf['lettermint_timeout'],
            }.compact
          else
            {}
          end
        end

        def emailer_config
          return {} unless defined?(OT) && OT.respond_to?(:conf) && OT.conf

          OT.conf['emailer'] || OT.conf[:emailer] || {}
        end

        def provider_config(provider)
          return {} unless defined?(OT) && OT.respond_to?(:conf) && OT.conf

          providers = OT.conf['email_providers'] || OT.conf[:email_providers] || {}
          providers[provider] || providers[provider.to_sym] || {}
        end

        def reply_to_address(template)
          # Some templates may have a specific reply-to
          template.data[:reply_to] || template.data[:sender_email]
        end

        def extract_email_address(value)
          return nil if value.nil?

          # Check for Array specifically, not respond_to?(:first)
          # because String#first returns the first character in Ruby 3.x
          if value.is_a?(Array)
            value.first&.to_s
          else
            value.to_s
          end
        end
      end
    end
  end
end
