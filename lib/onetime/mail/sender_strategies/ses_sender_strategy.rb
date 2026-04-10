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
      # DKIM tokens for DNS configuration.
      #
      # SES provides DKIM authentication via 3 CNAME records with
      # tokens that must be added to the domain's DNS.
      #
      # Example DNS records returned (name is relative, without the domain suffix):
      #   { type: 'CNAME', name: 'token1._domainkey', value: 'token1.dkim.amazonses.com' }
      #   { type: 'CNAME', name: 'token2._domainkey', value: 'token2.dkim.amazonses.com' }
      #   { type: 'CNAME', name: 'token3._domainkey', value: 'token3.dkim.amazonses.com' }
      #
      # Configuration:
      #   region:            AWS region (default: us-east-1)
      #   access_key_id:     AWS access key
      #   secret_access_key: AWS secret key
      #
      class SESSenderStrategy < BaseSenderStrategy
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

          log_info "[ses-sender] Provisioning sender identity for #{domain}"

          client   = build_ses_client(credentials)
          response = create_or_get_email_identity(client, domain)

          dkim_tokens = response.dkim_attributes&.tokens || []

          {
            success: true,
            message: "Provisioned sender identity for #{domain}",
            dns_records: build_dkim_records(dkim_tokens),
            provider_data: {
              dkim_tokens: dkim_tokens,
              region: credentials['region'] || 'us-east-1',
              identity: domain,
              dkim_status: response.dkim_attributes&.status,
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

          {
            verified: verified,
            status: dkim_status.downcase,
            message: verification_message(dkim_status),
            details: {
              dkim_signing_enabled: dkim_attrs&.signing_enabled,
              dkim_tokens: dkim_attrs&.tokens,
              identity_type: response.identity_type,
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
            region: credentials['region'] || 'us-east-1',
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

        # Builds DNS record hashes from DKIM tokens.
        #
        # @param tokens [Array<String>] DKIM tokens from SES
        # @return [Array<Hash>] DNS records in standard format
        #
        def build_dkim_records(tokens)
          tokens.map do |token|
            {
              type: 'CNAME',
              name: "#{token}._domainkey",
              value: "#{token}.dkim.amazonses.com",
            }
          end
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
