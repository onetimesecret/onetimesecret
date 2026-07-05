# apps/api/domains/logic/incoming_config/put_incoming_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/homepage_config'
require_relative 'base'
require_relative 'serializers'

module DomainsAPI
  module Logic
    module IncomingConfig
      # Create/Replace Domain Incoming Configuration
      #
      # @api Creates or replaces the incoming secrets configuration for a custom domain.
      #   Sets the full list of recipients, replacing any existing configuration.
      #   Requires the requesting user to be an organization owner with incoming_secrets.
      #
      # Request body:
      # - enabled: Boolean (optional, default false)
      # - recipients: Array of {email, name} objects
      #
      # Response includes:
      # - domain_id: The domain identifier
      # - enabled: Whether incoming secrets is active
      # - recipients: Array of {email, name}
      # - max_recipients: Maximum allowed recipients (20)
      # - created_at: Unix timestamp
      # - updated_at: Unix timestamp
      #
      class PutIncomingConfig < Base
        include Serializers

        attr_reader :incoming_config

        def process_params
          @domain_id           = sanitize_identifier(params['extid'])
          @enabled             = parse_boolean(params['enabled'])
          @recipients_provided = params.key?('recipients')
          @recipients          = parse_recipients(params['recipients'])
        end

        def raise_concerns
          # Require authenticated user
          if cust.anonymous?
            raise_form_error(
              'Authentication required',
              error_key: 'api.errors.authentication_required',
              field: :user_id,
              error_type: :authentication_required,
            )
          end

          # Validate domain_id parameter
          if @domain_id.to_s.empty?
            raise_form_error(
              'Domain ID required',
              error_key: 'api.domains.errors.domain_id_required',
              field: :domain_id,
              error_type: :missing,
            )
          end

          # Load domain and organization, verify ownership and entitlement
          authorize_domain_incoming!(@domain_id)

          # Validate recipients
          max = Onetime::CustomDomain::IncomingConfig::MAX_RECIPIENTS
          if @recipients.size > max
            raise_form_error(
              "Maximum #{max} recipients allowed",
              error_key: 'api.domains.errors.recipients_max_exceeded',
              args: { max: max },
              field: :recipients,
              error_type: :invalid,
            )
          end

          # Validate recipient emails with Truemail (write path — admin config)
          @recipients.each do |r|
            next if valid_email?(r[:email])

            raise_form_error(
              "Invalid email: #{r[:email]}",
              error_key: 'api.domains.errors.recipients_invalid_email',
              args: { email: r[:email] },
              field: :recipients,
              error_type: :invalid,
            )
          end

          # Check for duplicate emails
          emails = @recipients.map { |r| r[:email] }
          return unless emails.uniq.size != emails.size

          raise_form_error(
            'Duplicate recipient emails not allowed',
            error_key: 'api.domains.errors.recipients_duplicate',
            field: :recipients,
            error_type: :invalid,
          )
        end

        def process
          OT.ld "[PutIncomingConfig] Setting incoming config for domain #{@domain_id} by user #{cust.extid}"

          # Find or create config
          @incoming_config = Onetime::CustomDomain::IncomingConfig.find_by_domain_id(@custom_domain.identifier)

          if @incoming_config
            # Update existing
            @incoming_config.enabled = @enabled.to_s
            # Only update recipients if explicitly provided in the request.
            # This allows toggling enabled state without wiping recipients.
            # The admin frontend always sends the full recipients list, so the
            # provided branch is the standard path; the omitted branch supports
            # toggle-only callers (e.g. future PATCH).
            if @recipients_provided
              @incoming_config.recipients = @recipients
            end
            @incoming_config.updated = Familia.now.to_i
            @incoming_config.save
          else
            # Create new
            @incoming_config = Onetime::CustomDomain::IncomingConfig.create!(
              domain_id: @custom_domain.identifier,
              enabled: @enabled,
              recipients: @recipients,
            )
          end

          log_homepage_drift unless @incoming_config.ready?

          success_data
        end

        def success_data
          {
            user_id: cust.extid,
            record: serialize_incoming_config_admin(@incoming_config),
          }
        end

        private

        # This write left the config unready (disabled or zero recipients)
        # while the domain's homepage points at the incoming form.
        # Deliberately permissive — blocking would invert the dependency and
        # trap legitimate edits; the bootstrap serializer fails the homepage
        # closed to the trust card — but leave an audit trail so a silently
        # trust-carded homepage is traceable to this write.
        def log_homepage_drift
          homepage = Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@custom_domain.identifier)
          return unless homepage&.enabled? && homepage.incoming_mode?

          OT.li "[PutIncomingConfig] domain=#{@custom_domain.identifier} homepage secrets_mode=incoming " \
                "now unready (enabled=#{@incoming_config.enabled?} recipients=#{@incoming_config.recipients.size}) " \
                "after update by user=#{cust.extid}; public homepage degrades to trust card"
        end
      end
    end
  end
end
