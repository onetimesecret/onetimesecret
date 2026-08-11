# lib/onetime/operations/email/config_summary.rb
#
# frozen_string_literal: true

# Central (cross-cutting) admin operation — see decision D3 in
# lib/onetime/operations/README.md. Sibling of send_test.rb / ingest_feedback.rb
# / sync_provider_feedback.rb. Loaded at the call site, so require the mailer
# dependency explicitly.
require 'onetime/mail'

module Onetime
  module Operations
    module Email
      # The SINGLE source of the standing email-delivery config summary — the
      # masked, wire-safe view of the mailer configuration shared by the
      # `bin/ots email config` CLI ({Onetime::CLI::Email::ConfigCommand}) and the
      # colonel `GET /api/colonel/email/config` endpoint
      # ({ColonelAPI::Logic::Colonel::GetEmailConfig}).
      #
      # ## Security invariant (items 1 + 11)
      #
      # NO secret (user / pass / api_key / token / secret / password) may cross
      # the wire in this summary. {.masked_provider_config} emits ONLY booleans
      # (has_credentials) plus non-secret config (host / port / domain / tls /
      # region), and {.build} adds only from_address / from_name and the two
      # provider names. The raw emailer_config (which carries credentials) is
      # NEVER placed in the summary.
      #
      # ## What is NET-NEW vs the CLI
      #
      # The extraction adds `sender_provider` (the sender-domain provisioning
      # provider, CUSTOM_MAIL_PROVIDER → Mailer.determine_sender_provider) and a
      # `sender_differs` boolean. The old CLI computed only the transport
      # (determine_provider); surfacing that the sender-provisioning provider can
      # differ from the transport is the whole point of the colonel panel.
      module ConfigSummary
        extend self

        # Build the masked config summary.
        #
        # Uses Mailer.send(:...) for the three internal resolvers: send() works
        # on public methods too, so it is safe regardless of the method's actual
        # visibility — a bare call to a private resolver would raise
        # NoMethodError and 500 the whole config endpoint (and cascade into the
        # item-4 banner).
        #
        # @return [Hash] symbol-keyed summary (otto serializes to string keys on
        #   the wire).
        def build
          provider = Onetime::Mail::Mailer.send(:determine_provider)
          raw      = Onetime::Mail::Mailer.send(:emailer_config)
          sender   = Onetime::Mail::Mailer.send(:determine_sender_provider)
          explicit = raw['mode']&.to_s&.downcase

          {
            provider: provider,
            auto_detected: explicit.nil? || explicit.empty?,
            from_address: Onetime::Mail::Mailer.from_address,
            # from_name is documented [String, nil] (nil when unset). Coerce to a
            # string so the wire contract's non-nullable `from_name` holds — a
            # nil would fail the frontend Zod envelope and take the config panel
            # AND the item-4 safety banner down with it.
            from_name: Onetime::Mail::Mailer.from_name.to_s,
            provider_config: masked_provider_config(provider, raw),
            sender_provider: sender,
            sender_differs: sender != provider,
          }
        end

        # A STABLE superset: ALWAYS returns the same six keys, with explicit nils
        # where a key does not apply to the active provider. `port` is coerced to
        # Integer-or-nil; `has_credentials` is always a boolean. NO raw
        # user/pass/api_key/token is ever emitted.
        #
        # Registry-driven (the lettermint-omission bug class is structurally
        # impossible): every Mail::ProviderRegistry descriptor declares its
        # config-builder method, its safe-to-emit masked_config_keys, and the
        # summary_credential_groups that define has_credentials. The raw
        # emailer config is run through the SAME per-provider builder the
        # delivery path uses (Mailer's *_provider_config, which applies the
        # conf/ENV fallback chain), so summary and delivery cannot disagree.
        #
        # @param provider [String] the resolved transport provider.
        # @param raw [Hash] the raw emailer_config (string keys). Never returned.
        # @return [Hash] { host:, port:, domain:, tls:, region:, has_credentials: }
        def masked_provider_config(provider, raw)
          base = {
            host: nil, port: nil, domain: nil, tls: nil, region: nil, has_credentials: false
          }

          descriptor = Onetime::Mail::ProviderRegistry.descriptor(provider)
          # logger / disabled / none: no host/region and no credentials.
          return base unless descriptor

          # send() because the builders are private on Mailer (see build's
          # visibility note above).
          creds         = Onetime::Mail::Mailer.send(descriptor.provider_config_method, raw || {})
          masked        = descriptor.masked_config_keys.to_h { |key| [key.to_sym, creds[key]] }
          masked[:port] = coerce_port(masked[:port]) if masked.key?(:port)

          base.merge(masked).merge(has_credentials: credentials_present?(descriptor, creds))
        end

        # @return [Integer, nil] the port as an Integer, or nil when blank/invalid.
        def coerce_port(value)
          return nil if value.nil? || value.to_s.strip.empty?

          Integer(value.to_s.strip, exception: false)
        end

        # OR across groups, AND within a group (e.g. lettermint: sending
        # api_token OR provisioning team_token each count; smtp needs
        # username AND password).
        def credentials_present?(descriptor, creds)
          descriptor.summary_credential_groups.any? do |group|
            group.all? { |key| !creds[key].to_s.empty? }
          end
        end
      end
    end
  end
end
