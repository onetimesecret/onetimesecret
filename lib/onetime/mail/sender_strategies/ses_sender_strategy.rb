# lib/onetime/mail/sender_strategies/ses_sender_strategy.rb
#
# frozen_string_literal: true

require_relative 'base_sender_strategy'

module Onetime
  module Mail
    module SenderStrategies
      # SESSenderStrategy - AWS SES sender domain provisioning.
      #
      # Provisions email identities through SES v2 API and retrieves
      # DKIM tokens for DNS configuration. Also configures a custom MAIL
      # FROM domain so SPF aligns to the sender domain and bounces are
      # handled on the customer's domain rather than the shared
      # amazonses.com default.
      #
      # SES provides DKIM authentication via 3 CNAME records with
      # tokens that must be added to the domain's DNS. The custom MAIL
      # FROM adds an MX record (to the regional feedback endpoint) and an
      # SPF TXT record on the MAIL FROM subdomain.
      #
      # Example DNS records returned (names are fully-qualified):
      #   { type: 'CNAME', name: 'token1._domainkey.example.com', value: 'token1.dkim.amazonses.com' }
      #   { type: 'CNAME', name: 'token2._domainkey.example.com', value: 'token2.dkim.amazonses.com' }
      #   { type: 'CNAME', name: 'token3._domainkey.example.com', value: 'token3.dkim.amazonses.com' }
      #   { type: 'MX',    name: 'mail.example.com',              value: 'feedback-smtp.us-east-1.amazonses.com' }
      #   { type: 'TXT',   name: 'mail.example.com',              value: 'v=spf1 include:amazonses.com ~all' }
      #
      # Configuration:
      #   region:            AWS region (default: us-east-1)
      #   access_key_id:     AWS access key
      #   secret_access_key: AWS secret key
      #
      class SESSenderStrategy < BaseSenderStrategy
        # Default region when none is supplied via credentials.
        DEFAULT_REGION = 'us-east-1'

        # Subdomain label used for the custom MAIL FROM domain. AWS convention
        # is a subdomain of the sender domain (e.g. "mail.example.com").
        MAIL_FROM_SUBDOMAIN = 'mail'

        def provision_dns_records(mailer_config, credentials:)
          domain = extract_domain(mailer_config.from_address)

          unless domain
            return {
              success: false,
              message: 'Invalid from_address: cannot extract domain',
              dns_records: [],
              error: 'invalid_from_address',
            }
          end

          missing = missing_credential_keys(credentials)
          unless missing.empty?
            return {
              success: false,
              message: "AWS credentials required for SES provisioning (missing: #{missing.join(', ')})",
              dns_records: [],
              error: 'missing_credentials',
            }
          end

          region = credentials['region'] || DEFAULT_REGION
          log_info "[ses-sender] Provisioning sender identity for #{domain} (region: #{region})"

          client   = build_ses_client(credentials)
          response = create_or_get_email_identity(client, domain)

          dkim_tokens = response.dkim_attributes&.tokens || []
          records     = build_dkim_records(dkim_tokens, domain)

          # Configure a custom MAIL FROM domain so SPF aligns to the sender
          # domain and bounces land on the customer's own domain. SES requires
          # an MX record (to the regional feedback endpoint) plus an SPF TXT
          # record on the MAIL FROM subdomain; both are deterministic given the
          # region. Non-fatal: if SES rejects it we keep the DKIM records and
          # drop the MAIL FROM records (see #configure_mail_from).
          mail_from_domain = "#{MAIL_FROM_SUBDOMAIN}.#{domain}"
          if configure_mail_from(client, domain, mail_from_domain)
            records += build_mail_from_records(mail_from_domain, region)
          else
            mail_from_domain = nil
          end

          {
            success: true,
            message: "Provisioned sender identity for #{domain}",
            dns_records: records,
            provider_data: {
              dkim_tokens: dkim_tokens,
              region: region,
              identity: domain,
              dkim_status: response.dkim_attributes&.status,
              mail_from_domain: mail_from_domain,
            },
          }
        rescue Aws::SESV2::Errors::ServiceError => ex
          log_error "[ses-sender] SES API error: #{ex.message}"
          {
            success: false,
            message: "SES provisioning failed: #{ex.message}",
            dns_records: [],
            error: ex.code,
          }
        rescue StandardError => ex
          log_error "[ses-sender] Provisioning failed: #{ex.message}"
          {
            success: false,
            message: "Provisioning failed: #{ex.message}",
            dns_records: [],
            error: ex.message,
          }
        end

        # Checks provider-level verification via SES get_email_identity API.
        # DKIM status is returned directly by SES (SUCCESS, PENDING, FAILED, etc.).
        # DNS propagation is checked independently by check_dns_records (inherited
        # from BaseSenderStrategy), which works with provisioned records.
        def check_provider_verification_status(mailer_config, credentials:)
          domain = extract_domain(mailer_config.from_address)

          unless domain
            return {
              verified: false,
              status: 'invalid',
              message: 'Invalid from_address: cannot extract domain',
            }
          end

          log_info "[ses-sender] Checking verification status for #{domain}"

          client   = build_ses_client(credentials)
          response = client.get_email_identity(email_identity: domain)

          dkim_attrs  = response.dkim_attributes
          dkim_status = dkim_attrs&.status || 'NOT_STARTED'
          verified    = dkim_status == 'SUCCESS'
          mail_from   = response.mail_from_attributes

          {
            verified: verified,
            status: dkim_status.downcase,
            message: verification_message(dkim_status),
            details: {
              dkim_signing_enabled: dkim_attrs&.signing_enabled,
              dkim_tokens: dkim_attrs&.tokens,
              identity_type: response.identity_type,
              mail_from_domain: mail_from&.mail_from_domain,
              mail_from_status: mail_from&.mail_from_domain_status,
            },
          }
        rescue Aws::SESV2::Errors::NotFoundException
          {
            verified: false,
            status: 'not_found',
            message: "Identity #{domain} not found in SES",
          }
        rescue Aws::SESV2::Errors::ServiceError => ex
          log_error "[ses-sender] SES API error: #{ex.message}"
          {
            verified: false,
            status: 'error',
            message: "SES verification check failed: #{ex.message}",
          }
        rescue StandardError => ex
          log_error "[ses-sender] Verification check failed: #{ex.message}"
          {
            verified: false,
            status: 'error',
            message: "SES verification check failed: #{ex.message}",
          }
        end

        def delete_sender_identity(mailer_config, credentials:)
          domain = extract_domain(mailer_config.from_address)

          unless domain
            return {
              deleted: false,
              message: 'Invalid from_address: cannot extract domain',
            }
          end

          log_info "[ses-sender] Deleting sender identity for #{domain}"

          client = build_ses_client(credentials)
          client.delete_email_identity(email_identity: domain)

          {
            deleted: true,
            message: "Deleted sender identity #{domain}",
          }
        rescue Aws::SESV2::Errors::NotFoundException
          {
            deleted: true,
            message: "Identity #{domain} was already deleted or never existed",
          }
        rescue Aws::SESV2::Errors::ServiceError => ex
          log_error "[ses-sender] SES API error: #{ex.message}"
          {
            deleted: false,
            message: "SES deletion failed: #{ex.message}",
          }
        rescue StandardError => ex
          log_error "[ses-sender] Deletion failed: #{ex.message}"
          {
            deleted: false,
            message: "SES deletion failed: #{ex.message}",
          }
        end

        protected

        def validate_config!
          # Validation happens at call time with provided credentials
        end

        private

        # Builds an SES v2 client with the provided credentials.
        #
        # @param credentials [Hash] Must include 'access_key_id' and 'secret_access_key'
        # @option credentials [String] 'region' AWS region (default: 'us-east-1')
        # @return [Aws::SESV2::Client]
        #
        def build_ses_client(credentials)
          require 'aws-sdk-sesv2'

          Aws::SESV2::Client.new(
            region: credentials['region'] || DEFAULT_REGION,
            credentials: Aws::Credentials.new(
              credentials['access_key_id'],
              credentials['secret_access_key'],
            ),
          )
        end

        # Creates a new email identity or retrieves existing one.
        #
        # @param client [Aws::SESV2::Client]
        # @param domain [String]
        # @return [Aws::SESV2::Types::CreateEmailIdentityResponse, Aws::SESV2::Types::GetEmailIdentityResponse]
        #
        def create_or_get_email_identity(client, domain)
          client.create_email_identity(email_identity: domain)
        rescue Aws::SESV2::Errors::AlreadyExistsException
          log_info "[ses-sender] Identity #{domain} already exists, retrieving..."
          client.get_email_identity(email_identity: domain)
        end

        # Builds DKIM CNAME record hashes from SES tokens.
        #
        # Names are emitted as fully-qualified hostnames (including the sender
        # domain) so the verification layer can resolve them directly and the
        # UI can display them verbatim — consistent with the SendGrid and
        # Lettermint strategies.
        #
        # @param tokens [Array<String>] DKIM tokens from SES
        # @param domain [String] Sender domain (e.g. "example.com")
        # @return [Array<Hash>] DNS records in standard format
        #
        def build_dkim_records(tokens, domain)
          tokens.map do |token|
            {
              type: 'CNAME',
              name: "#{token}._domainkey.#{domain}",
              value: "#{token}.dkim.amazonses.com",
            }
          end
        end

        # Builds the custom MAIL FROM DNS records (MX + SPF TXT).
        #
        # The MX points at the regional SES feedback endpoint; the SPF TXT
        # authorizes amazonses.com for the MAIL FROM subdomain. Both are
        # required by SES once a custom MAIL FROM domain is configured.
        #
        # @param mail_from_domain [String] e.g. "mail.example.com"
        # @param region [String] AWS region (drives the feedback endpoint)
        # @return [Array<Hash>] MX and TXT records in standard format
        #
        def build_mail_from_records(mail_from_domain, region)
          [
            {
              type: 'MX',
              name: mail_from_domain,
              value: "feedback-smtp.#{region}.amazonses.com",
            },
            {
              type: 'TXT',
              name: mail_from_domain,
              value: 'v=spf1 include:amazonses.com ~all',
            },
          ]
        end

        # Configures a custom MAIL FROM domain on the SES identity.
        #
        # Non-fatal: the identity and DKIM are already provisioned, and a
        # custom MAIL FROM is an enhancement (SPF alignment + custom
        # Return-Path). If SES rejects the request we log and skip its records
        # rather than asking the customer to add records SES will not honor.
        # USE_DEFAULT_VALUE keeps mail flowing via the amazonses.com MAIL FROM
        # until the customer's MX propagates.
        #
        # @param client [Aws::SESV2::Client]
        # @param domain [String] Sender domain (the SES identity)
        # @param mail_from_domain [String] Custom MAIL FROM subdomain
        # @return [Boolean] true if SES accepted the MAIL FROM configuration
        #
        def configure_mail_from(client, domain, mail_from_domain)
          client.put_email_identity_mail_from_attributes(
            email_identity: domain,
            mail_from_domain: mail_from_domain,
            behavior_on_mx_failure: 'USE_DEFAULT_VALUE',
          )
          true
        rescue Aws::SESV2::Errors::ServiceError => ex
          log_warn "[ses-sender] MAIL FROM setup failed for #{domain}: #{ex.message}"
          false
        end

        # Returns the required credential keys that are missing or blank.
        #
        # Mirrors Lettermint/SendGrid which reject missing credentials up
        # front with a clear error rather than failing at API-call time with
        # an opaque AWS exception (e.g. MissingCredentialsError).
        #
        # @param credentials [Hash] Provider credentials (string keys per contract)
        # @return [Array<String>] Missing key names (empty if all present)
        #
        def missing_credential_keys(credentials)
          %w[access_key_id secret_access_key].select { |key| credentials[key].to_s.empty? }
        end

        # Maps SES DKIM status to human-readable message.
        #
        # @param status [String] SES DKIM status
        # @return [String]
        #
        def verification_message(status)
          case status
          when 'SUCCESS'
            'DKIM verification successful - domain is ready for sending'
          when 'PENDING'
            'DKIM verification pending - DNS records found, awaiting propagation'
          when 'FAILED'
            'DKIM verification failed - check DNS records are correctly configured'
          when 'TEMPORARY_FAILURE'
            'DKIM verification temporarily failed - will retry automatically'
          when 'NOT_STARTED'
            'DKIM verification not started - add DNS records to begin verification'
          else
            "DKIM status: #{status}"
          end
        end
      end
    end
  end
end
