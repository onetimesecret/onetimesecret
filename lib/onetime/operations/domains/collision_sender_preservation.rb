# frozen_string_literal: true

require 'onetime/mail/sender_strategies'

module Onetime
  module Operations
    module Domains
      # Preflight removals against the complete audit, including unselected and
      # ordinary records. Compare DeleteSenderDomain targets, not provisioning
      # metadata. Even another removal candidate protects a shared identity:
      # its removal may fail, so remote cleanup must be left to the operator.
      #
      # Every refusal is an UnsafeIdentity whose message names the record it
      # stopped on and whether its local mailer config or the provider lookup
      # failed, and never carries a credential, a sender address or an
      # exception message from an SDK or the datastore: the message is
      # persisted in the collision outcome's audit detail.
      class CollisionSenderPreservation
        class UnsafeIdentity < StandardError; end

        REMOTE_PROVIDERS = %w[ses sendgrid lettermint smtp2go].freeze
        LOCAL_PROVIDERS  = %w[smtp logger].freeze

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
        rescue UnsafeIdentity
          raise
        rescue StandardError
          raise UnsafeIdentity, 'Cannot safely establish collision sender identities', cause: nil
        end

        private

        def cached_identity_for(record)
          @identity_cache.fetch(record.domain_id) do
            @identity_cache[record.domain_id] = identity_for(record)
          end
        end

        # @return [Array(String, String), nil] the provider and the target
        #   its delete_sender_identity would delete; nil when the record has
        #   no remote sender identity
        def identity_for(record)
          domain = Onetime::CustomDomain.find_by_identifier(record.domain_id)
          raise UnsafeIdentity, unsafe(record, 'record not found') unless domain

          provider, strategy, sender_domain = local_identity(record, domain)
          return nil if provider.nil?

          target = deletion_target(record, provider, strategy, sender_domain)
          raise UnsafeIdentity, unsafe(record, "#{provider} lookup returned no identity for the sender domain") unless target.is_a?(String) || target.is_a?(Integer)
          raise UnsafeIdentity, unsafe(record, "#{provider} lookup returned no identity for the sender domain") if target.to_s.strip.empty?

          [provider, target.to_s]
        end

        # The local facts: which provider (and strategy) the record sends
        # through and the domain of its sender address. Nil: nothing remote to
        # delete. Anything the local config cannot answer refuses the record.
        def local_identity(record, domain)
          config = domain.mailer_config
          return nil unless config

          provider = config.effective_provider.to_s
          return nil if LOCAL_PROVIDERS.include?(provider)
          raise UnsafeIdentity, unsafe(record, 'mailer config names an unsupported provider') unless REMOTE_PROVIDERS.include?(provider)

          strategy      = Onetime::Mail::SenderStrategies.for_provider(provider)
          sender_domain = strategy.send(:extract_domain, config.from_address)
          raise UnsafeIdentity, unsafe(record, 'mailer config has no sender domain') if sender_domain.to_s.empty?

          [provider, strategy, sender_domain]
        rescue UnsafeIdentity
          raise
        rescue StandardError
          raise UnsafeIdentity, unsafe(record, 'mailer config unreadable'), cause: nil
        end

        # All deletion strategies use installation-level credentials, not the
        # config's encrypted delivery API key. SES/SMTP2GO target domain names;
        # SendGrid/Lettermint resolve provider IDs using these exact lookups,
        # which contact the provider: a failure there is the provider's, and a
        # retry may succeed. Reading the credentials is local and says so.
        def deletion_target(record, provider, strategy, sender_domain)
          case provider
          when 'ses', 'smtp2go'
            sender_domain.downcase
          when 'sendgrid'
            credentials = installation_credentials(record, provider, 'api_key')
            credentials['domain_id'] || remote_lookup(record, provider) do
              strategy.send(:find_domain_id, sender_domain, api_key: credentials['api_key'])
            end
          when 'lettermint'
            credentials = installation_credentials(record, provider, 'team_token')
            client      = local_step(record, "#{provider} client could not be built from the installation credentials") do
              strategy.send(:build_client, credentials)
            end
            remote_lookup(record, provider) { strategy.send(:find_domain_by_name, client, sender_domain)&.dig('id') }
          end
        end

        def installation_credentials(record, provider, key)
          credentials = local_step(record, "#{provider} installation credentials unreadable") do
            Onetime::Mail::Mailer.provider_credentials(provider)
          end
          return credentials unless credentials[key].to_s.empty?

          raise UnsafeIdentity, unsafe(record, "#{provider} credentials have no #{key}; the identity cannot be resolved")
        end

        def local_step(record, reason)
          yield
        rescue StandardError
          raise UnsafeIdentity, unsafe(record, reason), cause: nil
        end

        def remote_lookup(record, provider)
          yield
        rescue StandardError
          raise UnsafeIdentity, unsafe(record, "#{provider} lookup failed; the provider did not answer or refused the request, retry may succeed"), cause: nil
        end

        # The refusal text: the record's reference (its extid when it has
        # one, else its identifier) and a fixed reason. Neither is a
        # credential or a sender address.
        def unsafe(record, reason)
          "sender identity for #{ref_of(record)}: #{reason}"
        end

        def ref_of(record)
          extid = record.respond_to?(:extid) ? record.extid.to_s : ''
          extid.empty? ? record.domain_id.to_s : extid
        end
      end
    end
  end
end
