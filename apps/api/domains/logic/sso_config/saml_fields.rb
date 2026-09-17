# apps/api/domains/logic/sso_config/saml_fields.rb
#
# frozen_string_literal: true

require 'onetime/sso_provider/saml'
require_relative 'ssrf_protection'

module DomainsAPI
  module Logic
    module SsoConfig
      # Request handling for the SAML IdP trio (#4450), shared by PUT, PATCH
      # and test_connection so the three endpoints cannot disagree about what
      # they accept.
      #
      #   idp_sso_service_url  https URL of the IdP's SSO endpoint
      #   idp_entity_id        the IdP's EntityID — the issuer every identity
      #                        from this domain is keyed on
      #   idp_cert             ONE PEM X.509 signing certificate
      #
      # The structural rules are the platform definition's own
      # (Onetime::SsoProvider::Saml.sso_url_problem / entity_id_problem /
      # cert_problem) — this module adds only what is specific to a value
      # arriving over the API:
      #
      #   - the SSRF host check the OIDC issuer gets (SsrfProtection). The
      #     server never fetches a SAML SSO URL — the browser is redirected to
      #     it — but the URL's origin is admitted into this domain's CSP
      #     form-action and HttpOrigin allowances, so it is held to the same
      #     "public https host" bar.
      #   - certificate EXPIRY. The model deliberately does not treat expiry
      #     as a record invariant (SsoConfig#saml_validation_errors); the
      #     point where a certificate is ACCEPTED is here.
      #   - refusing fingerprint parameters outright (see FORBIDDEN_PARAMS).
      #
      # Includes SsrfProtection. Includers must respond to `params` and
      # `raise_form_error`.
      module SamlFields
        include SsrfProtection

        # Never accepted, in any spelling ruby-saml understands. A
        # fingerprint-only configuration trusts whatever certificate the
        # RESPONSE embeds (SHA1 by default), and idp_cert_multi would widen
        # the trusted set past the one pinned certificate. Refused loudly
        # rather than ignored: a client that sends one believes it configured
        # something.
        FORBIDDEN_PARAMS = %w[
          idp_cert_fingerprint
          idp_cert_fingerprint_algorithm
          idp_cert_multi
        ].freeze

        # Reads the trio into @idp_sso_service_url / @idp_entity_id / @idp_cert.
        #
        # Surrounding whitespace is stripped at this boundary (pasted values
        # routinely carry it). For the EntityID that is safe precisely BECAUSE
        # it happens before storage: the stored string is what the strategy
        # compares byte-for-byte with the response Issuer and what identities
        # are keyed on, and entity_id_problem refuses a value that still has
        # any. The certificate is normalized the way the platform env value is
        # (literal "\n" → newline) plus CRLF → LF.
        def process_saml_params
          @idp_sso_service_url = params['idp_sso_service_url'].to_s.strip
          @idp_entity_id       = params['idp_entity_id'].to_s.strip
          @idp_cert            = Onetime::SsoProvider::Saml
            .normalize_pem(params['idp_cert'].to_s).gsub("\r\n", "\n").strip
        end

        def reject_forbidden_saml_params!
          sent = FORBIDDEN_PARAMS.find { |name| !params[name].to_s.strip.empty? }
          return if sent.nil?

          raise_form_error(
            'Certificate fingerprints are not accepted. Provide the IdP signing certificate (PEM) in idp_cert.',
            field: sent.to_sym,
            error_type: :invalid,
          )
        end

        # Validate the trio as submitted.
        #
        # @param stored [Onetime::CustomDomain::SsoConfig, nil] PATCH semantics:
        #   a blank submitted field is acceptable when this record already
        #   holds a readable value for it (it will be preserved). nil — PUT,
        #   test_connection, or a create — makes every field required.
        def validate_saml_fields!(stored: nil)
          reject_forbidden_saml_params!

          saml_submitted.each do |field, value|
            if value.empty?
              next if stored_saml_value?(stored, field)

              raise_form_error("#{saml_label(field)} is required for SAML provider", field: field, error_type: :missing)
            end

            problem = saml_problem(field, value)
            raise_form_error(problem, field: field, error_type: :invalid) if problem
          end
        end

        # @return [String, nil] the first problem with a submitted value
        def saml_problem(field, value)
          saml = Onetime::SsoProvider::Saml

          case field
          when :idp_sso_service_url
            saml.sso_url_problem(value) ||
              (valid_issuer_host?(value) ? nil : 'IdP SSO service URL must be an HTTPS URL pointing to a public host')
          when :idp_entity_id
            saml.entity_id_problem(value)
          when :idp_cert
            saml.cert_problem(value)
          end
        end

        # @return [Hash{Symbol => String}]
        def saml_submitted
          {
            idp_sso_service_url: @idp_sso_service_url.to_s,
            idp_entity_id: @idp_entity_id.to_s,
            idp_cert: @idp_cert.to_s,
          }
        end

        # Whether the stored record holds a readable, non-blank value for the
        # field. An undecryptable value counts as absent — fail closed: the
        # caller must then supply a fresh one.
        def stored_saml_value?(stored, field)
          return false if stored.nil?

          !stored.reveal_saml_field(field).strip.empty?
        rescue StandardError
          false
        end

        def saml_label(field)
          {
            idp_sso_service_url: 'IdP SSO service URL',
            idp_entity_id: 'IdP EntityID',
            idp_cert: 'IdP certificate',
          }.fetch(field)
        end
      end
    end
  end
end
