# lib/onetime/mail/provider_registry.rb
#
# frozen_string_literal: true

module Onetime
  module Mail
    # ProviderRegistry - THE single authoritative description of every custom
    # mail sender provider.
    #
    # Every Ruby provider list or case-arm derives from this registry. Adding a
    # provider still requires updating independent configuration/frontend
    # mirrors that cannot consume Ruby; frontend_provider_parity_spec.rb names
    # those surfaces and fails until they agree with the new descriptor.
    # Before this registry existed, ~10 independent hashes and
    # case statements had to be updated in lockstep and drifted silently
    # (e.g. ConfigSummary shipped without a lettermint arm and nobody
    # noticed).
    #
    # Derived (rewired) call sites:
    #   - Mail::SenderStrategies::PROVIDER_STRATEGIES / PROVISIONING_PROVIDERS
    #   - DomainValidation::SenderStrategies::SenderStrategy::PROVIDER_MAP
    #   - DomainValidation::SenderStrategies::ProviderConfig::DEFAULTS
    #   - CustomDomain::MailerConfig::PROVIDER_TYPES
    #   - Mail::Mailer (build_provider_config dispatch, delivery backend
    #     selection, determine_provider auto-detection)
    #   - Operations::ProvisionSenderDomain#missing_credential_keys
    #   - Operations::Email::ConfigSummary.masked_provider_config
    #   - Operations::Email::{RecipientLookup,ProviderStatus,
    #     SyncProviderFeedback}::PROVIDERS (feedback-capable providers)
    #   - Jobs::Workers::DomainValidationWorker credential guards
    #   - ConfigGenerator email_provider choices + env placeholders
    #
    # Configuration/frontend mirrors (cannot consume Ruby; guarded by
    # spec/unit/onetime/mail/frontend_provider_parity_spec.rb):
    #   - src/schemas/contracts/email-config.ts emailProviderTypeSchema
    #     (= provisioning_providers + 'inherit')
    #   - src/apps/workspace/components/domains/DomainEmailConfigForm.vue
    #     providerDisplayName map (same set, labels from descriptors)
    #   - src/schemas/api/internal/responses/colonel-deliverability.ts
    #     colonelEmailProviderStatusDetailsSchema blocks (= feedback_providers)
    #   - etc/defaults/config.defaults.yaml email_providers blocks
    #     (= provisioning_providers; DNS defaults must match each descriptor)
    #   - generated/schemas/config/static.schema.json emailer enums and
    #     email_providers blocks/defaults (generated from TS config shapes)
    #
    # Class references are stored as NAMES and resolved lazily via const_get:
    # this file requires nothing, so it can be required from anywhere
    # (models, workers, operations) without load-order or circular-require
    # concerns. The strategy/delivery files themselves are still required by
    # their existing owners (sender_strategies.rb, strategy.rb, mailer.rb).
    module ProviderRegistry
      # Immutable description of one mail provider.
      #
      # @!attribute name  [String] canonical lowercase provider name
      # @!attribute label [String] human label (config generator, UIs)
      # @!attribute required_credential_keys [Array<String>] credential keys
      #   (as returned by Mailer.provider_credentials) that MUST be non-empty
      #   for provisioning / provider API checks to run
      # @!attribute optional_credential_keys [Array<String>] recognized but
      #   not required credential keys
      # @!attribute summary_credential_groups [Array<Array<String>>]
      #   OR-of-ANDs over credential keys used by ConfigSummary's
      #   has_credentials boolean (e.g. lettermint: sending token OR team
      #   token each count)
      # @!attribute masked_config_keys [Array<String>] non-secret credential
      #   keys safe to emit in the masked config summary
      # @!attribute provisioning [Boolean] supports automated sender-domain
      #   DNS provisioning via provider API
      # @!attribute feedback [Boolean] has a pollable suppression-feedback /
      #   status API (a fetcher under Onetime::Mail::Feedback)
      # @!attribute sender_strategy_class_name [String] provisioning strategy
      #   (Onetime::Mail::SenderStrategies::*)
      # @!attribute validation_strategy_class_name [String, nil] DNS
      #   validation strategy (Onetime::DomainValidation::SenderStrategies::*),
      #   nil for providers validated manually (smtp)
      # @!attribute delivery_class_name [String] transactional delivery
      #   backend (Onetime::Mail::Delivery::*)
      # @!attribute provider_config_method [Symbol] Mailer private method that
      #   builds the credential hash from emailer config + ENV
      # @!attribute detect_keys [Array<String>] emailer-config keys whose
      #   joint presence auto-detects this provider (Mailer.determine_provider;
      #   registry order is the detection precedence order)
      # @!attribute env_placeholders [Array<String>] ENV var names the config
      #   generator emits as empty placeholders for this provider
      # @!attribute config_env_sources [Hash{Symbol => Array<String>}] config
      #   keys mapped to their ordered ENV sources in config.defaults.yaml;
      #   parity specs verify every source, fallback order, and default value
      # @!attribute dns_defaults [Hash] hardcoded defaults for DNS
      #   provisioning/validation options (was ProviderConfig::DEFAULTS)
      Descriptor = Data.define(
        :name,
        :label,
        :required_credential_keys,
        :optional_credential_keys,
        :summary_credential_groups,
        :masked_config_keys,
        :provisioning,
        :feedback,
        :sender_strategy_class_name,
        :validation_strategy_class_name,
        :delivery_class_name,
        :provider_config_method,
        :detect_keys,
        :env_placeholders,
        :config_env_sources,
        :dns_defaults,
      ) do
        def provisioning? = provisioning

        def feedback? = feedback

        # @return [Class] the Mail::SenderStrategies strategy class
        def sender_strategy_class
          Object.const_get(sender_strategy_class_name)
        end

        # @return [Class, nil] the DomainValidation strategy class, if any
        def validation_strategy_class
          return nil if validation_strategy_class_name.nil?

          Object.const_get(validation_strategy_class_name)
        end

        # @return [Class] the Mail::Delivery backend class
        def delivery_class
          Object.const_get(delivery_class_name)
        end
      end

      # Ordered registry. ORDER MATTERS: it is the auto-detection precedence
      # for Mailer.determine_provider (ses's region+user pair must be tested
      # before smtp's bare host, which would otherwise shadow it).
      DESCRIPTORS = [
        Descriptor.new(
          name: 'ses',
          label: 'Amazon SES',
          required_credential_keys: %w[access_key_id secret_access_key region].freeze,
          optional_credential_keys: [].freeze,
          summary_credential_groups: [%w[access_key_id secret_access_key].freeze].freeze,
          masked_config_keys: %w[region].freeze,
          provisioning: true,
          feedback: true,
          sender_strategy_class_name: 'Onetime::Mail::SenderStrategies::SESSenderStrategy',
          validation_strategy_class_name: 'Onetime::DomainValidation::SenderStrategies::SesValidation',
          delivery_class_name: 'Onetime::Mail::Delivery::SES',
          provider_config_method: :ses_provider_config,
          detect_keys: %w[region user].freeze,
          env_placeholders: %w[AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY].freeze,
          config_env_sources: {
            region: %w[CUSTOM_MAIL_SES_REGION].freeze,
            access_key_id: %w[CUSTOM_MAIL_SES_ACCESS_KEY_ID AWS_ACCESS_KEY_ID].freeze,
            secret_access_key: %w[CUSTOM_MAIL_SES_SECRET_ACCESS_KEY AWS_SECRET_ACCESS_KEY].freeze,
          }.freeze,
          dns_defaults: {
            region: 'us-east-1',
            dkim_selector_count: 3,
            spf_include: 'amazonses.com',
          }.freeze,
        ),
        Descriptor.new(
          name: 'sendgrid',
          label: 'SendGrid',
          required_credential_keys: %w[api_key].freeze,
          optional_credential_keys: [].freeze,
          summary_credential_groups: [%w[api_key].freeze].freeze,
          masked_config_keys: [].freeze,
          provisioning: true,
          feedback: false,
          sender_strategy_class_name: 'Onetime::Mail::SenderStrategies::SendGridSenderStrategy',
          validation_strategy_class_name: 'Onetime::DomainValidation::SenderStrategies::SendgridValidation',
          delivery_class_name: 'Onetime::Mail::Delivery::SendGrid',
          provider_config_method: :sendgrid_provider_config,
          detect_keys: %w[sendgrid_api_key].freeze,
          env_placeholders: %w[SENDGRID_API_KEY].freeze,
          config_env_sources: {
            subdomain: %w[CUSTOM_MAIL_SENDGRID_SUBDOMAIN].freeze,
          }.freeze,
          dns_defaults: {
            subdomain: 'em',
            dkim_selectors: %w[s1 s2].freeze,
            spf_include: 'sendgrid.net',
          }.freeze,
        ),
        Descriptor.new(
          name: 'lettermint',
          label: 'Lettermint',
          # team_token (Bearer auth) is what domain provisioning needs;
          # api_token (x-lettermint-token) only sends mail.
          required_credential_keys: %w[team_token].freeze,
          optional_credential_keys: %w[api_token base_url timeout].freeze,
          summary_credential_groups: [%w[api_token].freeze, %w[team_token].freeze].freeze,
          masked_config_keys: [].freeze,
          provisioning: true,
          feedback: true,
          sender_strategy_class_name: 'Onetime::Mail::SenderStrategies::LettermintSenderStrategy',
          validation_strategy_class_name: 'Onetime::DomainValidation::SenderStrategies::LettermintValidation',
          delivery_class_name: 'Onetime::Mail::Delivery::Lettermint',
          provider_config_method: :lettermint_provider_config,
          detect_keys: %w[lettermint_api_token].freeze,
          env_placeholders: %w[LETTERMINT_API_TOKEN LETTERMINT_TEAM_TOKEN].freeze,
          config_env_sources: {
            api_token: %w[LETTERMINT_API_TOKEN].freeze,
            team_token: %w[LETTERMINT_TEAM_TOKEN].freeze,
            api_base_url: %w[LETTERMINT_BASE_URL].freeze,
            spf_cname_prefix: %w[CUSTOM_MAIL_LETTERMINT_SPF_CNAME_PREFIX].freeze,
            spf_cname_target: %w[CUSTOM_MAIL_LETTERMINT_SPF_CNAME_TARGET].freeze,
          }.freeze,
          dns_defaults: {
            dkim_selectors: %w[lm1 lm2].freeze,
            spf_cname_prefix: 'lm-bounces',
            spf_cname_target: 'bounces.lmta.net',
            api_base_url: 'https://api.lettermint.co/v1',
          }.freeze,
        ),
        Descriptor.new(
          name: 'smtp2go',
          label: 'SMTP2GO',
          # The single API key covers both sending and domain provisioning.
          # NOTE: smtp2go_provider_config signals a missing api_key with an
          # empty hash (the returnpath/tracking subdomain defaults are only
          # baked in once the key is present), so both creds.empty? guards
          # and missing_required_credentials detect it.
          required_credential_keys: %w[api_key].freeze,
          optional_credential_keys: %w[base_url returnpath_subdomain tracking_subdomain timeout].freeze,
          summary_credential_groups: [%w[api_key].freeze].freeze,
          masked_config_keys: [].freeze,
          provisioning: true,
          # Suppression-list import + per-address lookup via
          # POST /suppression/view, cycle stats via POST /stats/email_summary
          # (Feedback::Smtp2go).
          feedback: true,
          sender_strategy_class_name: 'Onetime::Mail::SenderStrategies::Smtp2goSenderStrategy',
          validation_strategy_class_name: 'Onetime::DomainValidation::SenderStrategies::Smtp2goValidation',
          delivery_class_name: 'Onetime::Mail::Delivery::Smtp2go',
          provider_config_method: :smtp2go_provider_config,
          detect_keys: %w[smtp2go_api_key].freeze,
          env_placeholders: %w[SMTP2GO_API_KEY].freeze,
          config_env_sources: {
            api_key: %w[SMTP2GO_API_KEY].freeze,
            api_base_url: %w[SMTP2GO_BASE_URL].freeze,
            returnpath_subdomain: %w[CUSTOM_MAIL_SMTP2GO_RETURNPATH_SUBDOMAIN].freeze,
            tracking_subdomain: %w[CUSTOM_MAIL_SMTP2GO_TRACKING_SUBDOMAIN].freeze,
          }.freeze,
          # fastaccept is a boolean with ENV override, not a passthrough - lives here
          dns_defaults: {
            api_base_url: 'https://api.smtp2go.com/v3',
            returnpath_subdomain: 'bounce',
            tracking_subdomain: 'track',
            fastaccept: false,
          }.freeze,
        ),
        Descriptor.new(
          name: 'smtp',
          label: 'Generic SMTP',
          required_credential_keys: %w[host].freeze,
          optional_credential_keys: %w[port username password domain tls allow_unauthenticated_fallback].freeze,
          summary_credential_groups: [%w[username password].freeze].freeze,
          masked_config_keys: %w[host port domain tls].freeze,
          provisioning: false, # manual DNS configuration; strategy is a no-op
          feedback: false,
          sender_strategy_class_name: 'Onetime::Mail::SenderStrategies::SMTPSenderStrategy',
          validation_strategy_class_name: nil,
          delivery_class_name: 'Onetime::Mail::Delivery::SMTP',
          provider_config_method: :smtp_provider_config,
          detect_keys: %w[host].freeze,
          env_placeholders: %w[SMTP_HOST SMTP_USERNAME SMTP_PASSWORD].freeze,
          config_env_sources: {}.freeze,
          dns_defaults: {}.freeze,
        ),
      ].to_h { |descriptor| [descriptor.name, descriptor] }.freeze

      class << self
        # @return [Array<String>] ordered canonical provider names
        def providers
          DESCRIPTORS.keys
        end

        # @return [Array<Descriptor>] descriptors in registry order
        def descriptors
          DESCRIPTORS.values
        end

        # @param name [String, Symbol, nil] provider name (case-insensitive)
        # @return [Descriptor, nil] nil when unknown
        def descriptor(name)
          DESCRIPTORS[normalize(name)]
        end

        # @param name [String, Symbol] provider name
        # @return [Descriptor]
        # @raise [ArgumentError] naming the supported providers when unknown
        def descriptor!(name)
          descriptor(name) or raise ArgumentError,
            "Unknown mail provider: '#{name}'. Supported: #{providers.join(', ')}"
        end

        # @return [Array<String>] providers supporting automated provisioning
        def provisioning_providers
          descriptors.select(&:provisioning?).map(&:name)
        end

        # @param name [String, Symbol, nil] provider name
        # @return [Boolean] true when the provider supports provisioning
        def provisioning_provider?(name)
          descriptor(name)&.provisioning? || false
        end

        # @return [Array<String>] providers with a pollable feedback API
        def feedback_providers
          descriptors.select(&:feedback?).map(&:name)
        end

        # Required credential keys that are missing or blank.
        #
        # Tolerates string or symbol credential keys and a nil credentials
        # hash. Unknown providers have no known requirements → [].
        #
        # @param provider [String, Symbol, nil] provider name
        # @param credentials [Hash, nil] credential hash
        # @return [Array<String>] missing required key names
        def missing_required_credentials(provider, credentials)
          desc = descriptor(provider)
          return [] unless desc

          creds = credentials.is_a?(Hash) ? credentials : {}
          desc.required_credential_keys.select do |key|
            value = creds[key] || creds[key.to_sym]
            value.to_s.empty?
          end
        end

        # @param name [String, Symbol] provider name
        # @return [Class] the Mail::SenderStrategies strategy class
        # @raise [ArgumentError] when the provider is unknown
        def sender_strategy_for(name)
          descriptor!(name).sender_strategy_class
        end

        # @param name [String, Symbol] provider name
        # @return [Class, nil] the DomainValidation strategy class, if any
        # @raise [ArgumentError] when the provider is unknown
        def validation_strategy_for(name)
          descriptor!(name).validation_strategy_class
        end

        # @param name [String, Symbol] provider name
        # @return [Hash] hardcoded DNS provisioning defaults ({} when unknown)
        def dns_defaults(name)
          descriptor(name)&.dns_defaults || {}
        end

        # Providers with non-empty DNS defaults, keyed by name. Shape matches
        # the legacy ProviderConfig::DEFAULTS constant exactly.
        #
        # @return [Hash{String => Hash}]
        def dns_defaults_by_provider
          descriptors.reject { |d| d.dns_defaults.empty? }
            .to_h { |d| [d.name, d.dns_defaults] }
        end

        # Auto-detect the provider from an emailer config hash: first
        # descriptor (in registry order) whose detect_keys are all present.
        #
        # @param conf [Hash] string-keyed emailer config
        # @return [String, nil] provider name or nil when nothing matches
        def detect_provider(conf)
          conf ||= {}
          match  = descriptors.find do |d|
            d.detect_keys.any? && d.detect_keys.all? { |key| conf[key] }
          end
          match&.name
        end

        private

        def normalize(name)
          name.to_s.downcase.strip
        end
      end
    end
  end
end
