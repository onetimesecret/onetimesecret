# apps/api/domains/logic/sso_config/saml_fields.rb
#
# frozen_string_literal: true

require 'onetime/sso_provider/saml'

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
      #   - NO SSRF host check on the SSO URL. The server never fetches a
      #     SAML SSO URL — it is a browser-navigation target — so the check
      #     the OIDC issuer gets (SsrfProtection, for a URL the server DOES
      #     fetch at discovery) is deliberately NOT applied: an IdP on a
      #     private network is a legitimate configuration for a browser that
      #     can reach it. That the URL's ORIGIN is one this domain's CSP
      #     form-action and HttpOrigin allowances can carry
      #     (AuthConfig#tenant_idp_origin) is part of sso_url_problem itself,
      #     so the platform env, the model and this path share the rule.
      #   - certificate EXPIRY. The model deliberately does not treat expiry
      #     as a record invariant (SsoConfig#saml_validation_errors); the
      #     point where a certificate is ACCEPTED is here.
      #   - refusing fingerprint parameters outright (see FORBIDDEN_PARAMS).
      #   - the install's SESSION COOKIE. A saml config under a cookie that
      #     is not SameSite=None + Secure can never complete a sign-in
      #     (Saml.session_cookie_problem), and an org admin cannot change the
      #     install's cookie. Refused when a request ACTIVATES a saml config:
      #     one that introduces it (PUT, or a PATCH creating / switching to
      #     saml) or one that (re-)enables a disabled saml record. Re-enabling
      #     counts as activation because the persisted result would run under
      #     a cookie it cannot work with — every sign-in fails, and with
      #     enforce_sso_only that locks the tenant out, while the cookie rule
      #     is deliberately not a rung in tenant_sso_unavailable_reason so
      #     SSO stays advertised. A PATCH editing a record that STAYS disabled
      #     — rotating a field, renaming — or one that is already enabled is
      #     not blocked, so a record saved before the cookie changed can
      #     always be repaired or switched off, and a live one is never
      #     stranded mid-edit.
      #
      # Includers must respond to `params` and `raise_form_error`.
      module SamlFields
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
        #   holds a readable value for it (it will be preserved). The EFFECTIVE
        #   value of every field — submitted, else stored — is validated
        #   whenever the persisted result is enabled; only while the config
        #   remains disabled may an unchanged or omitted stored value skip
        #   re-validation. This permits repairing or editing a disabled record
        #   whose certificate expired, without allowing that unusable record
        #   to be re-enabled by any request shape (a bare enabled=true with
        #   the trio omitted included). nil — PUT, test_connection, or a
        #   create — makes every field required and validates every one.
        # @param enabled [Boolean] the enabled flag the persisted result will
        #   carry, as the caller computes it (for PATCH: the parsed request
        #   value when the key is present and non-null, else the stored
        #   flag). Ignored when stored is nil. It must be the value that is
        #   actually written, not a reading of the raw param: the body is
        #   typed JSON with no schema, so "false" and null are legal
        #   spellings of enabled, and a disable that PERSISTS must not be
        #   refused for a certificate the result will never run on. The same
        #   flag decides the session-cookie rule (see the header): a request
        #   that introduces a saml config (stored nil) or flips a disabled
        #   record to enabled is an activation and is refused under a cookie
        #   SAML cannot use; one that leaves the record disabled, or edits a
        #   record that is already enabled, is not.
        def validate_saml_fields!(stored: nil, enabled: true)
          reject_forbidden_saml_params!

          activating = stored.nil? || (enabled && !stored.enabled?)
          reject_incompatible_session_cookie! if activating

          remains_disabled = saml_config_remains_disabled?(stored, enabled)

          saml_submitted.each do |field, value|
            stored_value = stored_saml_value(stored, field)

            if value.empty?
              if stored_value.nil?
                raise_form_error("#{saml_label(field)} is required for SAML provider", field: field, error_type: :missing)
              end

              # Preserved as-is; the stored value is what the result runs on.
              value = stored_value
            end

            next if value == stored_value && remains_disabled

            problem = saml_problem(field, value)
            raise_form_error(problem, field: field, error_type: :invalid) if problem
          end
        end

        # See the header: one rule (Saml.session_cookie_problem) shared with
        # the boot warning, surfaced on provider_type because no field of the
        # trio is at fault.
        def reject_incompatible_session_cookie!
          problem = Onetime::SsoProvider::Saml.session_cookie_problem
          return if problem.nil?

          raise_form_error(
            "SAML sign-in cannot complete on this install: #{problem}. " \
            'The operator must change site.session before a SAML configuration can be saved.',
            field: :provider_type,
            error_type: :invalid,
          )
        end

        # An unchanged or omitted, formerly valid value may bypass
        # re-validation only while the persisted result remains disabled. In
        # particular, any request that persists as enabled (true, "true", 1)
        # must re-check a stored certificate that may have expired since it
        # was accepted, whether the request resends that certificate or
        # leaves it out. `enabled` is the caller's effective persisted flag
        # (see validate_saml_fields!), never re-derived from the raw param.
        def saml_config_remains_disabled?(stored, enabled)
          !stored.nil? && !enabled
        end

        # @return [String, nil] the first problem with a submitted value
        def saml_problem(field, value)
          saml = Onetime::SsoProvider::Saml

          case field
          when :idp_sso_service_url
            saml.sso_url_problem(value)
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

        # The stored record's readable, non-blank value for the field,
        # stripped the way process_saml_params strips a submitted one. nil
        # when there is no record, the value is blank, or it cannot be
        # revealed — an undecryptable value counts as absent, fail closed:
        # the caller must then supply a fresh one, which IS validated.
        #
        # @return [String, nil]
        def stored_saml_value(stored, field)
          return nil if stored.nil?

          value = stored.reveal_saml_field(field).strip
          value.empty? ? nil : value
        rescue StandardError
          nil
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
