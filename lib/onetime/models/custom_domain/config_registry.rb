# lib/onetime/models/custom_domain/config_registry.rb
#
# frozen_string_literal: true

# Self-contained: the registry references the config model classes and their
# enum constants at load time, so require them here rather than relying on the
# require ordering in lib/onetime/models.rb.
require_relative 'api_config'
require_relative 'homepage_config'
require_relative 'incoming_config'
require_relative 'mailer_config'
require_relative 'signin_config'
require_relative 'signup_config'
require_relative 'sso_config'

module Onetime
  class CustomDomain < Familia::Horreum
    # ConfigRegistry — the single catalog of the seven per-custom-domain config
    # record kinds (signin/signup/homepage/api/incoming/sso/mailer) consumed by
    # the colonel per-domain config endpoints (GET/PUT/DELETE
    # /api/colonel/domains/:extid/configs*).
    #
    # Owns, per kind:
    #   - the model class (all keyed on CustomDomain objid via
    #     `identifier_field :domain_id`)
    #   - whether the kind is colonel-editable (sso/mailer are view/delete only:
    #     their create paths enforce credential/from_address validation and their
    #     absent state means "fall back to platform")
    #   - whether the kind is materializable by the ensure-missing action
    #     (absent and present-but-disabled are behavior-equivalent for the five
    #     resolver-gated kinds, so creating disabled records is behavior-neutral)
    #   - the writable-field COERCIONS for PUT upserts; the specs themselves
    #     are COMPOSED from each model's FIELD_SPECS constant (see
    #     FIELD_SPECS below) — the model file is the single source of truth
    #   - the redacting serializer used by ALL colonel responses
    #
    # Boolean encodings differ across the models: SigninConfig (and the
    # signup_enabled/autoverify fields on SignupConfig) store REAL booleans,
    # while the other models store 'true'/'false' STRINGS. Each model declares
    # its own encoding (storage :native | :string) in its FIELD_SPECS,
    # next to its field declarations, and enables the boolean_encoding
    # feature, which builds tolerant predicates and normalizing setters from
    # those specs (#3951) — so writers that bypass apply_field (console,
    # create!/upsert) can no longer persist a mixed encoding that silently
    # reads as disabled. Serialization always goes through the model
    # predicates so the frontend sees real JSON booleans; writes go through
    # apply_field, which storage-encodes per the field spec (a no-op under
    # the normalizing setters, kept as the explicit encoding boundary).
    #
    # REDACTION INVARIANT: encrypted credentials (SsoConfig client_id /
    # client_secret, MailerConfig api_key) are NEVER serialized — presence
    # booleans only. The jsonkey diagnostic blobs on MailerConfig
    # (provider_dns_data / dns_records / dns_check_results) are excluded too.
    module ConfigRegistry
      # Reason recorded in ensure responses for the non-materializable kinds.
      SKIP_REASON = 'requires_credentials'

      # Kind slug => capabilities. Insertion order is the canonical display
      # order (mirrored by the admin UI rows).
      KINDS = {
        'signin' => { model: Onetime::CustomDomain::SigninConfig,   editable: true,  materializable: true },
        'signup' => { model: Onetime::CustomDomain::SignupConfig,   editable: true,  materializable: true },
        'homepage' => { model: Onetime::CustomDomain::HomepageConfig, editable: true, materializable: true },
        'api' => { model: Onetime::CustomDomain::ApiConfig, editable: true, materializable: true },
        'incoming' => { model: Onetime::CustomDomain::IncomingConfig, editable: true, materializable: true },
        'sso' => { model: Onetime::CustomDomain::SsoConfig, editable: false, materializable: false },
        'mailer' => { model: Onetime::CustomDomain::MailerConfig, editable: false, materializable: false },
      }.freeze

      # Colonel-writable field specs per editable kind, COMPOSED from each
      # model's own FIELD_SPECS constant. The model file — next to its
      # field declarations — is the ONLY place that names its writable fields
      # and their storage encoding, so adding a colonel-writable field is a
      # one-file change (edit the model's FIELD_SPECS).
      #
      # Spec semantics (interpreted by coerce_field! / apply_field below):
      #   type :boolean  — accepts JSON true/false plus 'true'/'false'/'1'/'0';
      #                    storage :native assigns the boolean as-is (SigninConfig,
      #                    SignupConfig's real-boolean fields), storage :string
      #                    assigns 'true'/'false' (the string-encoded models).
      #   type :enum     — value must be in :values; :nullable enums accept
      #                    nil/"" and store nil (clears the override).
      #   type :string_array — array of strings; validation happens in the model
      #                    setter (allowed_signup_domains= PublicSuffix-validates
      #                    and raises Onetime::Problem).
      #
      # Load-time transcription check: every spec'd field must have a public
      # setter on its model (apply_field writes via public_send, and the
      # boolean_encoding feature builds its accessors from the same specs),
      # so a typo'd or renamed field fails at require time, not at PUT time.
      # Runs for EVERY kind that declares FIELD_SPECS — including the
      # non-editable sso/mailer, whose specs exist for the boolean_encoding
      # feature rather than for colonel PUTs.
      KINDS.each do |slug, entry|
        model = entry[:model]
        next unless model.const_defined?(:FIELD_SPECS)

        model::FIELD_SPECS.each_key do |field|
          next if model.public_method_defined?("#{field}=")

          raise "ConfigRegistry: #{model}##{field}= missing for spec'd field '#{field}' (kind=#{slug})"
        end
      end

      # Colonel-WRITABLE specs only: composition stays editable-kind-only, so
      # sso/mailer declaring FIELD_SPECS does not make them PUTable
      # (field_specs returns {} for them and the routes reject via editable?).
      FIELD_SPECS = KINDS.each_with_object({}) do |(slug, entry), acc|
        next unless entry[:editable]

        acc[slug] = entry[:model]::FIELD_SPECS
      end.freeze

      class << self
        # All seven kind slugs in canonical display order.
        # @return [Array<String>]
        def slugs
          KINDS.keys
        end

        # @return [Boolean] whether the slug names a known config kind
        def kind?(kind)
          KINDS.key?(kind.to_s)
        end

        # @return [Class] the Familia model class for the kind
        def model_for(kind)
          KINDS.fetch(kind.to_s)[:model]
        end

        # @return [Boolean] whether the kind is colonel-editable (PUT upsert)
        def editable?(kind)
          entry = KINDS[kind.to_s]
          entry ? entry[:editable] : false
        end

        # @return [Boolean] whether the ensure action may materialize the kind
        def materializable?(kind)
          entry = KINDS[kind.to_s]
          entry ? entry[:materializable] : false
        end

        # The five kinds the ensure action materializes (model defaults,
        # everything disabled — behavior-neutral).
        # @return [Array<String>]
        def materializable_slugs
          KINDS.select { |_, e| e[:materializable] }.keys
        end

        # The always-skipped entries for ensure responses (sso/mailer).
        # @return [Array<Hash>] [{kind:, reason:}, ...]
        def credential_required_skips
          KINDS.reject { |_, e| e[:materializable] }.keys.map do |slug|
            { kind: slug, reason: SKIP_REASON }
          end
        end

        # Writable-field specs for an editable kind (empty hash for sso/mailer).
        # @return [Hash{String => Hash}]
        def field_specs(kind)
          FIELD_SPECS.fetch(kind.to_s, {})
        end

        # Coerce a raw param value for a writable field.
        #
        # @param kind [String] config kind slug
        # @param field [String] writable field name (must be in field_specs)
        # @param value [Object] raw param value
        # @return [Object] the coerced value (boolean / enum string or nil / string array)
        # @raise [Onetime::Problem] when the value is invalid for the field,
        #   or when the field spec declares an unknown :type (spec drift —
        #   without the raise, an unrecognized type would coerce every value
        #   to nil and apply_field would overwrite the stored value)
        def coerce_field!(kind, field, value)
          spec = field_specs(kind).fetch(field.to_s)
          case spec[:type]
          when :boolean      then coerce_boolean!(field, value)
          when :enum         then coerce_enum!(field, value, spec)
          when :string_array then coerce_string_array!(field, value)
          else
            raise Onetime::Problem, "#{field} has unknown field spec type #{spec[:type].inspect} (kind=#{kind})"
          end
        end

        # Assign an already-coerced value onto the model with the correct
        # storage encoding (string-boolean models store 'true'/'false').
        # Model setters may still raise Onetime::Problem
        # (allowed_signup_domains= PublicSuffix validation).
        #
        # @param config [Familia::Horreum] the config record
        # @param kind [String] config kind slug
        # @param field [String] writable field name
        # @param value [Object] coerced value from coerce_field!
        # @return [void]
        def apply_field(config, kind, field, value)
          spec    = field_specs(kind).fetch(field.to_s)
          encoded = spec[:type] == :boolean && spec[:storage] == :string ? value.to_s : value
          config.public_send("#{field}=", encoded)
        end

        # Serialize a config record for colonel API responses. Normalizes the
        # mixed boolean encodings to real JSON booleans (via model predicates),
        # timestamps to integers or nil, and NEVER includes credential values.
        #
        # @param kind [String] config kind slug
        # @param config [Familia::Horreum, nil] the record (nil passes through)
        # @return [Hash, nil]
        def serialize(kind, config)
          return nil if config.nil?

          case kind.to_s
          when 'signin'   then serialize_signin(config)
          when 'signup'   then serialize_signup(config)
          when 'homepage' then serialize_homepage(config)
          when 'api'      then serialize_api(config)
          when 'incoming' then serialize_incoming(config)
          when 'sso'      then serialize_sso(config)
          when 'mailer'   then serialize_mailer(config)
          end
        end

        private

        def coerce_boolean!(field, value)
          case value
          when true, 'true', '1', 1 then true
          when false, 'false', '0', 0 then false
          else
            raise Onetime::Problem, "#{field} must be a boolean"
          end
        end

        def coerce_enum!(field, value, spec)
          if value.nil? || value.to_s.strip.empty?
            return nil if spec[:nullable]

            raise Onetime::Problem, "#{field} must be one of: #{spec[:values].join(', ')}"
          end

          candidate = value.to_s
          return candidate if spec[:values].include?(candidate)

          raise Onetime::Problem, "#{field} must be one of: #{spec[:values].join(', ')}"
        end

        def coerce_string_array!(field, value)
          raise Onetime::Problem, "#{field} must be an array of strings" unless value.is_a?(Array)

          value.map(&:to_s)
        end

        # Unix-epoch integer or nil (legacy records may lack timestamps).
        def epoch_or_nil(value)
          value.to_s.empty? ? nil : value.to_i
        end

        # Non-empty string or nil.
        def presence(value)
          str = value.to_s
          str.empty? ? nil : str
        end

        # Presence check for an encrypted field WITHOUT exposing the value.
        # Same rescue-to-nil pattern as SsoConfig#validation_errors: a
        # decryption failure reads as "not present". The revealed value never
        # leaves this method.
        def encrypted_present?(concealed)
          value = begin
            concealed&.reveal { it }
          rescue StandardError
            nil
          end
          !value.to_s.empty?
        end

        def serialize_signin(config)
          {
            domain_id: config.domain_id,
            enabled: config.enabled?,
            signin_enabled: config.signin_enabled?,
            email_auth_enabled: config.email_auth_enabled?,
            sso_enabled: config.sso_enabled?,
            restrict_to: presence(config.restrict_to),
            created: epoch_or_nil(config.created),
            updated: epoch_or_nil(config.updated),
          }
        end

        def serialize_signup(config)
          {
            domain_id: config.domain_id,
            enabled: config.enabled?,
            signup_enabled: config.signup_enabled?,
            autoverify: config.autoverify?,
            validation_strategy: config.validation_strategy,
            allowed_signup_domains: config.allowed_signup_domains,
            created: epoch_or_nil(config.created),
            updated: epoch_or_nil(config.updated),
          }
        end

        # Deliberately EXCLUDES the deprecated read-echo signup_enabled /
        # signin_enabled fields (ADR-030: no display authority).
        def serialize_homepage(config)
          {
            domain_id: config.domain_id,
            enabled: config.enabled?,
            secrets_mode: config.secrets_mode_value,
            disabled_homepage_variant: config.disabled_homepage_variant_value,
            created: epoch_or_nil(config.created),
            updated: epoch_or_nil(config.updated),
          }
        end

        def serialize_api(config)
          {
            domain_id: config.domain_id,
            enabled: config.enabled?,
            created: epoch_or_nil(config.created),
            updated: epoch_or_nil(config.updated),
          }
        end

        def serialize_incoming(config)
          {
            domain_id: config.domain_id,
            enabled: config.enabled?,
            ready: config.ready?,
            recipients: config.recipients.map { |r| { email: r[:email], name: r[:name] } },
            created: epoch_or_nil(config.created),
            updated: epoch_or_nil(config.updated),
          }
        end

        # REDACTED: credential presence only, never client_id/client_secret.
        def serialize_sso(config)
          {
            domain_id: config.domain_id,
            enabled: config.enabled?,
            provider_type: config.provider_type,
            display_name: config.display_name,
            issuer: presence(config.issuer),
            tenant_id: presence(config.tenant_id),
            has_client_id: encrypted_present?(config.client_id),
            has_client_secret: encrypted_present?(config.client_secret),
            allowed_domains: config.allowed_domains,
            enforce_sso_only: config.enforce_sso_only?,
            grant_org_scope: config.grant_org_scope?,
            created: epoch_or_nil(config.created),
            updated: epoch_or_nil(config.updated),
          }
        end

        # REDACTED: api_key presence only; jsonkey diagnostic blobs
        # (provider_dns_data / dns_records / dns_check_results) excluded.
        def serialize_mailer(config)
          {
            domain_id: config.domain_id,
            enabled: config.enabled?,
            provider: presence(config.provider),
            from_name: config.from_name,
            from_address: config.from_address,
            reply_to: config.reply_to,
            sending_mode: config.sending_mode,
            verification_status: config.verification_status,
            dns_verified: config.dns_verified.to_s == 'true',
            provider_verified: config.provider_verified.to_s == 'true',
            has_api_key: encrypted_present?(config.api_key),
            created: epoch_or_nil(config.created),
            updated: epoch_or_nil(config.updated),
          }
        end
      end
    end
  end
end
