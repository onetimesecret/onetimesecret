# apps/api/domains/logic/sso_config/serializers.rb
#
# frozen_string_literal: true

module DomainsAPI
  module Logic
    module SsoConfig
      # Shared serialization methods for Domain SSO config API responses.
      #
      # Provides consistent serialization across GET and PUT endpoints,
      # including proper field masking for sensitive credentials.
      #
      module Serializers
        # Serialize SSO config for API response with masked secrets.
        #
        # Field naming matches TypeScript schema contract:
        # - client_secret_masked (not client_secret)
        # - created_at/updated_at as Unix timestamps
        #
        # SAML (#4450). idp_sso_service_url / idp_entity_id / idp_cert are
        # returned in PLAINTEXT: none is a secret (an SSO URL, an EntityID and
        # a public certificate are what an IdP publishes). They are
        # encrypted_fields for integrity — bound to this domain through AAD —
        # which is why a value that will not decrypt must never be served as
        # a quiet null: a swapped or corrupted trust anchor is exactly what
        # the binding exists to catch. `unreadable_fields` names every
        # encrypted field whose reveal FAILED (as opposed to being unset), so
        # the UI can show an error state and demand the value be re-entered;
        # it is [] for a healthy record. It covers client_id / client_secret
        # too, which previously failed to null with only a log line.
        #
        # sp_entity_id / acs_url are read-only values for the admin to paste
        # into their IdP; null for non-saml records. See #saml_sp_identifiers.
        #
        # cert_expires_at / cert_expired describe the stored idp_cert's
        # validity window (ISO 8601 UTC / boolean). An expired certificate
        # stays advertised on the sign-in page — availability deliberately
        # ignores expiry (SsoConfig#idp_cert_not_after) — while every login
        # through it is refused as sso_config_unusable, so this is the one
        # place the admin learns WHY. null / false when there is no parseable
        # certificate (non-saml, unset, unreadable).
        #
        # @param config [Onetime::CustomDomain::SsoConfig] SSO config to serialize
        # @return [Hash] Serialized config matching TypeScript schema
        def serialize_sso_config(config)
          unreadable = []
          reveal     = ->(name) { reveal_field(config, name, unreadable) }
          sp         = saml_sp_identifiers(config)
          not_after  = config.idp_cert_not_after

          {
            domain_id: config.domain_id,
            provider_type: config.provider_type,
            display_name: config.display_name,
            enabled: config.enabled?,
            enforce_sso_only: config.enforce_sso_only?,
            grant_org_scope: config.grant_org_scope?,
            client_id: reveal.call(:client_id),
            client_secret_masked: mask_secret(config.client_secret, unreadable),
            tenant_id: config.tenant_id,
            issuer: config.issuer,
            idp_sso_service_url: reveal.call(:idp_sso_service_url),
            idp_entity_id: reveal.call(:idp_entity_id),
            idp_cert: reveal.call(:idp_cert),
            name_id_format: serialize_saml_policy(config, :name_id_format, unreadable) { config.saml_name_id_format },
            callback_origins: serialize_saml_policy(config, :callback_origins, unreadable) { config.callback_origins },
            sp_entity_id: sp[:sp_entity_id],
            acs_url: sp[:acs_url],
            cert_expires_at: not_after&.utc&.iso8601,
            cert_expired: !not_after.nil? && not_after <= Time.now,
            unreadable_fields: unreadable,
            allowed_domains: config.allowed_domains,
            requires_domain_filter: config.requires_domain_filter?,
            idp_controls_access: config.idp_controls_access?,
            created_at: config.created.to_i,
            updated_at: config.updated.to_i,
          }
        end

        def serialize_saml_policy(config, field, unreadable)
          return nil unless config.provider_type == 'saml'

          yield
        rescue StandardError
          unreadable << field.to_s
          nil
        end

        # Our SAML SP identifiers for this domain, as the tenant hook derives
        # them at login (Auth::Config::Hooks::OmniAuthTenant
        # .inject_saml_sp_identifiers — keep the path shapes in step):
        #
        #   acs_url      = <public origin>/auth/sso/<route>/callback
        #   sp_entity_id = <public origin>/auth/sso/<route>/metadata
        #
        # The hook has a request and uses strategy.full_host; this runs in the
        # API, usually on the canonical host, so the origin is composed from
        # the domain's display_domain and site.ssl. The two agree for a
        # verified custom domain served on the default port — the production
        # shape. They can differ for an UNVERIFIED domain (Auth::PublicHost
        # only roots auth URLs on a TXT-verified domain, so full_host falls
        # back to the request's own authority) or a non-default port; the SP
        # metadata URL itself is always authoritative, since it is served by
        # the same hook.
        #
        # Both nil for a non-saml record, or when the domain cannot be loaded.
        #
        # @return [Hash{Symbol => String, nil}]
        def saml_sp_identifiers(config)
          blank = { sp_entity_id: nil, acs_url: nil }
          return blank unless config.provider_type == 'saml'

          host = config.custom_domain&.display_domain.to_s.strip
          return blank if host.empty?

          scheme = OT.conf.dig('site', 'ssl') == false ? 'http' : 'https'
          base   = "#{scheme}://#{host}/auth/sso/#{config.platform_route_name}"

          { sp_entity_id: "#{base}/metadata", acs_url: "#{base}/callback" }
        rescue StandardError => ex
          OT.lw "[SsoConfig::Serializers] Could not derive SAML SP identifiers: #{ex.class.name}"
          blank
        end

        # Reveal one encrypted field, recording a FAILURE in `unreadable`.
        #
        # nil means "unset" only when `unreadable` does not name the field.
        # The log line carries scalars only — field name, domain id, exception
        # class (a decryption error message is not ours to vouch for).
        #
        # @param config [Onetime::CustomDomain::SsoConfig]
        # @param name [Symbol] encrypted field name
        # @param unreadable [Array<String>] collector, mutated
        # @return [String, nil] Plaintext value or nil
        def reveal_field(config, name, unreadable)
          concealed = config.public_send(name)
          return nil if concealed.nil?

          concealed.reveal { it }
        rescue StandardError => ex
          unreadable << name.to_s
          OT.lw "[SsoConfig::Serializers] Failed to reveal encrypted field #{name} " \
                "for domain #{config.domain_id}: #{ex.class.name}"
          nil
        end

        # Mask a secret value, showing only last 4 characters.
        #
        # Logs warnings for decryption failures to aid debugging.
        #
        # @param concealed [Familia::ConcealedString, nil] Encrypted secret
        # @param unreadable [Array<String>, nil] collector for a reveal failure
        # @return [String, nil] Masked secret (e.g., "••••••••abcd") or nil
        def mask_secret(concealed, unreadable = nil)
          return nil if concealed.nil?

          plaintext = concealed.reveal { it }
          return nil if plaintext.nil? || plaintext.empty?

          if plaintext.length <= 4
            '••••••••'
          else
            '••••••••' + plaintext[-4..]
          end
        rescue StandardError => ex
          unreadable&.push('client_secret')
          OT.lw "[SsoConfig::Serializers] Failed to mask secret: #{ex.class.name}"
          nil
        end
      end
    end
  end
end
