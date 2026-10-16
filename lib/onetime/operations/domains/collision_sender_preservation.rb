# frozen_string_literal: true

require 'onetime/mail/sender_strategies'

module Onetime
  module Operations
    module Domains
      # Preflight removals against the complete audit, including unselected and
      # ordinary records. Compare DeleteSenderDomain targets, not provisioning
      # metadata. Even another removal candidate protects a shared identity:
      # its removal may fail, so remote cleanup must be left to the operator.
      class CollisionSenderPreservation
        class UnsafeIdentity < StandardError; end

        # records must be the full, complete audit.rows. The caller stops writers
        # and shares a fresh cache across this apply only, retaining identities
        # even after an earlier group's local records have been destroyed.
        def initialize(group:, records:, identity_cache:)
          @group          = group
          @records        = records
          @identity_cache = identity_cache
        end

        def call
          removals   = @group.records - [@group.keep_record].compact
          candidates = removals.to_h { |record| [record.domain_id, cached_identity_for(record)] }
          return candidates.transform_values { false } if candidates.values.all?(&:nil?)

          # Resolve all references before comparing; short-circuiting on a match
          # must not hide an unreadable identity elsewhere in the audit.
          references = @records.to_h { |record| [record.domain_id, cached_identity_for(record)] }
          candidates.to_h do |domain_id, identity|
            shared = !identity.nil? && references.any? do |other_id, other_identity|
              other_id != domain_id && other_identity == identity
            end
            [domain_id, shared]
          end
        rescue StandardError
          # Preflight errors flow into persisted collision outcomes. Never expose
          # credentials, sender addresses, or exception messages from SDKs/Redis.
          raise UnsafeIdentity, 'Cannot safely establish collision sender identities; nothing removed', cause: nil
        end

        private

        def cached_identity_for(record)
          @identity_cache.fetch(record.domain_id) do
            @identity_cache[record.domain_id] = identity_for(record)
          end
        end

        def identity_for(record)
          domain = Onetime::CustomDomain.find_by_identifier(record.domain_id)
          raise UnsafeIdentity unless domain

          config = domain.mailer_config
          return nil unless config

          provider = config.effective_provider.to_s
          return nil if %w[smtp logger].include?(provider)
          raise UnsafeIdentity unless %w[ses sendgrid lettermint smtp2go].include?(provider)

          strategy      = Onetime::Mail::SenderStrategies.for_provider(provider)
          sender_domain = strategy.send(:extract_domain, config.from_address)
          raise UnsafeIdentity if sender_domain.to_s.empty?

          # All deletion strategies use installation-level credentials, not the
          # config's encrypted delivery API key. SES/SMTP2GO target domain names;
          # SendGrid/Lettermint resolve provider IDs using these exact lookups.
          target = case provider
                   when 'ses', 'smtp2go'
                     sender_domain.downcase
                   when 'sendgrid'
                     credentials = Onetime::Mail::Mailer.provider_credentials(provider)
                     require_credential!(credentials, 'api_key')
                     credentials['domain_id'] || strategy.send(:find_domain_id, sender_domain, api_key: credentials['api_key'])
                   when 'lettermint'
                     credentials = Onetime::Mail::Mailer.provider_credentials(provider)
                     require_credential!(credentials, 'team_token')
                     client      = strategy.send(:build_client, credentials)
                     strategy.send(:find_domain_by_name, client, sender_domain)&.fetch('id')
                   end
          raise UnsafeIdentity unless target.is_a?(String) || target.is_a?(Integer)
          raise UnsafeIdentity if target.to_s.strip.empty?

          [provider, target.to_s]
        end

        def require_credential!(credentials, key)
          raise UnsafeIdentity if credentials[key].to_s.empty?
        end
      end
    end
  end
end
