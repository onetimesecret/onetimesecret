# apps/api/domains/logic/domains/update_domain_recipients.rb
#
# frozen_string_literal: true

require_relative '../base'

module DomainsAPI::Logic
  module Domains
    # Updates the incoming secret recipients for a custom domain.
    #
    # Accepts a list of {email, name} pairs and persists them as a
    # JSON blob in the incoming_secrets jsonkey. Emails are validated
    # and stored; only hashed versions are returned in the response.
    #
    # Requires the incoming_secrets entitlement. This is the entitlement
    # gate: on plan downgrade, existing recipients continue working for
    # submissions but this endpoint blocks configuration changes.
    #
    # @example Request
    #   PUT /api/domains/:extid/recipients
    #   {
    #     recipients: [
    #       { email: "support@example.com", name: "Support Team" },
    #       { email: "admin@example.com", name: "Admin" }
    #     ]
    #   }
    #
    class UpdateDomainRecipients < DomainsAPI::Logic::Base
      attr_reader :custom_domain, :recipients_input

      def process_params
        @extid = sanitize_identifier(params['extid'])
        @recipients_input = params['recipients']
      end

      def raise_concerns
        require_entitlement!('incoming_secrets')

        raise_form_error 'Please provide a domain ID' if @extid.empty?

        unless valid_extid?(@extid)
          raise_form_error 'Invalid domain identifier format'
        end

        require_organization!

        @custom_domain = Onetime::CustomDomain.find_by_extid(@extid)

        raise_form_error 'Domain not found' unless @custom_domain&.exists?

        unless @custom_domain.owner?(@cust)
          raise_form_error 'Domain not found'
        end

        validate_recipients_input
      end

      def process
        # Build new config with updated recipients
        config = @custom_domain.incoming_secrets_config
        config.set_incoming_recipients(@recipients_input)

        # Persist to Redis
        @custom_domain.update_incoming_secrets_config(config)

        OT.info "[UpdateDomainRecipients] Updated #{config.recipients.size} recipients for domain #{@extid} by #{@cust.objid} (org: #{organization&.extid})"

        success_data
      end

      def success_data
        # Clear memoized config to get fresh data
        @custom_domain.instance_variable_set(:@incoming_secrets_config, nil)
        config = @custom_domain.incoming_secrets_config
        site_secret = OT.conf.dig('site', 'secret')
        {
          user_id: @cust.objid,
          record: {
            recipients: config.public_incoming_recipients(site_secret),
            memo_max_length: config.memo_max_length,
            default_ttl: config.default_ttl,
          },
        }
      end

      private

      def valid_extid?(extid)
        extid.match?(/\A[a-z0-9]+\z/)
      end

      def validate_recipients_input
        unless @recipients_input.is_a?(Array)
          raise_form_error 'Recipients must be an array'
        end

        max = Onetime::CustomDomain::IncomingSecretsConfig::MAX_RECIPIENTS
        if @recipients_input.size > max
          raise_form_error "Maximum #{max} recipients allowed"
        end

        @recipients_input.each_with_index do |r, i|
          unless r.is_a?(Hash)
            raise_form_error "Recipient at index #{i} must be an object"
          end

          email = (r['email'] || r[:email]).to_s.strip
          if email.empty?
            raise_form_error "Recipient at index #{i} requires an email"
          end

          unless email.match?(/\A[\w+\-.]+@[a-z\d-]+(\.[a-z\d-]+)*\.[a-z]+\z/i)
            raise_form_error "Invalid email format for recipient at index #{i}"
          end
        end
      end
    end
  end
end
