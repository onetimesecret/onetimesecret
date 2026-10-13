# apps/api/domains/logic/sso_config/run_diagnostics.rb
#
# frozen_string_literal: true

require 'time'
require 'onetime/models/custom_domain/sso_config'
require_relative 'base'
require_relative 'discovery_check'
require_relative '../../../../../lib/onetime/sso_provider/entra'
require_relative '../../../../../lib/onetime/sso_provider/entra_credential_probe'
require 'onetime/security/sso_diagnostics_rate_limiter'

module DomainsAPI
  module Logic
    module SsoConfig
      # Check the SAVED SSO configuration of a custom domain
      #
      # @api Runs diagnostics against the stored SsoConfig record (not the
      #   form, which is TestConnection's job) and reports each layer
      #   separately, per docs/runbooks/sso-credential-health.md:
      #
      #   stored_configuration  all providers; the record reloaded and
      #                         SsoConfig#validation_errors. When it fails,
      #                         every later check is "skipped".
      #   discovery             oidc, entra_id; the same discovery fetch Test
      #                         Connection does, from the STORED issuer /
      #                         tenant_id (DiscoveryCheck).
      #   certificate           saml; local validity window of the stored
      #                         IdP certificate.
      #   credential            entra_id: one client-credentials token request
      #                         with the stored client_id / client_secret
      #                         (Onetime::SsoProvider::EntraCredentialProbe).
      #                         oidc: unsupported — OIDC does not guarantee
      #                         the client-credentials grant and the scope
      #                         cannot be known.
      #
      #   A passing credential check means Entra accepted the saved secret
      #   for a client-credentials request, nothing more: it does not
      #   exercise redirect URIs, user assignment, Conditional Access or
      #   claims.
      #
      # Response:
      # - user_id, provider_type, checked_at (ISO 8601 UTC)
      # - configuration_revision: SsoConfig#updated as stored (may be empty)
      # - overall: passed | failed | inconclusive — failed if any check
      #   failed; else inconclusive if any check inconclusive; else passed.
      #   unsupported and skipped checks do not affect it.
      # - checks: [{ check, status, message, details }], status one of
      #   passed | failed | inconclusive | unsupported | skipped
      #
      # Never returns, logs or raises the client secret, a token, or Entra's
      # error_description (correlation ids, app id). The credential check
      # reports the bare AADSTS code only.
      #
      # Rate limited per CUSTOMER (Onetime::Security::SsoDiagnosticsRateLimiter,
      # kind `sso_diagnostics`, 10 runs per hour by default), charged on the
      # last line of raise_concerns: after the session, ownership and
      # entitlement guards and after the stored record is found, so a refused
      # request costs nothing. Over the cap the API answers 429 with
      # retry_after and a Retry-After header, and no check runs.
      #
      class RunDiagnostics < Base
        include DiscoveryCheck
        include Onetime::Security::SsoDiagnosticsRateLimiter

        STATUSES = %w[passed failed inconclusive unsupported skipped].freeze

        SKIPPED_MESSAGE = 'Fix the stored configuration first'

        TENANT_ID_FORMAT_ERROR = 'tenant_id must be a valid UUID for Entra ID provider'

        CREDENTIAL_PASSED_MESSAGE = 'The identity provider accepted the saved client secret.'
        CREDENTIAL_PASSED_NOTE    = 'This does not test a full sign-in (redirect URI, user assignment, ' \
                                    'Conditional Access, claims). Sign in once on the custom domain to confirm.'
        SECRET_ID_SHAPE_NOTE      = 'The saved secret has the shape of an Entra Secret ID (a UUID). ' \
                                    'Entra needs the secret Value, shown once when the secret is created.'
        OIDC_CREDENTIAL_MESSAGE   = 'There is no safe credential probe for a generic OIDC provider. ' \
                                    'Sign in once on the custom domain to confirm the client secret.'

        CREDENTIAL_FAILURE_MESSAGES = {
          'invalid_client_secret' => 'The identity provider rejected the saved client secret (AADSTS7000215).',
          'client_secret_expired' => 'The saved client secret has expired (AADSTS7000222).',
          'app_not_found_in_tenant' => 'The identity provider found no application with the saved client ID ' \
                                       'in this tenant (AADSTS700016).',
          'invalid_tenant_id' => 'The saved tenant ID is not a valid UUID.',
        }.freeze

        CREDENTIAL_INCONCLUSIVE_MESSAGES = {
          'provider_error' => 'The identity provider returned an error that is not about the client secret.',
          'timeout' => 'The identity provider did not answer in time.',
          'connection_failed' => 'The identity provider could not be reached.',
          'ssl_error' => 'The TLS connection to the identity provider failed.',
          'invalid_response' => 'The identity provider returned an unexpected response.',
          'unexpected_error' => 'An unexpected error occurred. Please try again.',
        }.freeze

        attr_reader :sso_config

        def process_params
          @domain_id = sanitize_identifier(params['extid'])
        end

        def raise_concerns
          raise_form_error('Authentication required', field: :user_id, error_type: :authentication_required) if cust.anonymous?
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          authorize_domain_sso!(@domain_id)

          @sso_config = Onetime::CustomDomain::SsoConfig.find_by_domain_id(@custom_domain.identifier)
          if @sso_config.nil?
            raise_form_error('No SSO configuration is saved for this domain', field: :domain_id, error_type: :missing)
          end

          # DiscoveryCheck and TokenEndpointAuthMethodReport read these.
          @provider_type              = @sso_config.provider_type.to_s
          @issuer                     = @sso_config.issuer.to_s
          @tenant_id                  = @sso_config.tenant_id.to_s
          @token_endpoint_auth_method = @sso_config.token_endpoint_auth_method.to_s.strip

          # Last, so only a run that will actually happen is charged.
          enforce_sso_diagnostics_rate_limit!(cust.extid)
        end

        def process
          OT.ld "[RunDiagnostics] Checking saved #{@provider_type} configuration for domain #{@domain_id}"

          @checked_at = Time.now.utc
          @checks     = run_checks
          @overall    = compute_overall(@checks)

          OT.info "[RunDiagnostics] Saved configuration check #{@overall} for #{@provider_type}",
            {
              domain_id: @domain_id,
              provider_type: @provider_type,
              overall: @overall,
              checks: @checks.to_h { |check| [check[:check], check[:status]] },
            }

          success_data
        end

        def success_data
          {
            user_id: cust.extid,
            provider_type: @provider_type,
            checked_at: @checked_at.iso8601,
            configuration_revision: @sso_config.updated.to_s,
            overall: @overall,
            checks: @checks,
          }
        end

        def form_fields
          { domain_id: @domain_id }
        end

        private

        # ──────────────────────────────────────────────────────────────────────────
        # Orchestration
        # ──────────────────────────────────────────────────────────────────────────

        def run_checks
          stored = stored_configuration_check
          rest   = later_check_names.map do |name|
            if stored[:status] == 'failed'
              check(name, 'skipped', SKIPPED_MESSAGE)
            else
              run_check(name)
            end
          end
          [stored, *rest]
        end

        def later_check_names
          case @provider_type
          when 'oidc', 'entra_id' then %w[discovery credential]
          when 'saml'             then %w[certificate]
          else []
          end
        end

        def run_check(name)
          case name
          when 'discovery'   then discovery_check
          when 'certificate' then certificate_check
          when 'credential'  then credential_check
          end
        end

        def compute_overall(checks)
          statuses = checks.map { it[:status] }
          return 'failed' if statuses.include?('failed')
          return 'inconclusive' if statuses.include?('inconclusive')

          'passed'
        end

        def check(name, status, message, details = {})
          raise ArgumentError, "unknown check status #{status.inspect}" unless STATUSES.include?(status)

          { check: name, status: status, message: message, details: details }
        end

        # ──────────────────────────────────────────────────────────────────────────
        # stored_configuration
        # ──────────────────────────────────────────────────────────────────────────

        # validation_errors reports an undecryptable credential as missing
        # ("client_secret is required") and never includes a value.
        #
        # SsoConfig#validation_errors only requires tenant_id to be non-empty
        # for entra_id; the UUID shape is enforced on the write path
        # (TestConnection#validate_entra_id_fields). Both later checks
        # interpolate the stored tenant_id into a login.microsoftonline.com
        # path, so it is checked here, before either runs, and a non-UUID
        # value fails this check and skips the rest rather than sending an
        # unvalidated path segment to discovery while the probe refuses it.
        def stored_configuration_check
          errors = @sso_config.validation_errors.map(&:to_s)
          errors << TENANT_ID_FORMAT_ERROR if @provider_type == 'entra_id' && !tenant_id_uuid?
          if errors.empty?
            check('stored_configuration', 'passed', 'The saved configuration loads and has every required field.')
          else
            check('stored_configuration', 'failed', 'The saved configuration is incomplete or unreadable.', errors: errors)
          end
        rescue StandardError => ex
          OT.le "[RunDiagnostics] validation_errors raised #{ex.class.name} for domain #{@domain_id}"
          check(
            'stored_configuration',
            'failed',
            'The saved configuration could not be read.',
            errors: ["configuration cannot be read (#{ex.class.name})"],
          )
        end

        # ──────────────────────────────────────────────────────────────────────────
        # discovery (oidc, entra_id)
        # ──────────────────────────────────────────────────────────────────────────

        def discovery_check
          result  = @provider_type == 'oidc' ? test_oidc_connection : test_entra_id_connection
          details = result[:details] || {}
          status  = if result[:success]
                      'passed'
                    elsif UNREACHABLE_ERROR_CODES.include?(details[:error_code].to_s)
                      'inconclusive'
                    else
                      'failed'
                    end
          check('discovery', status, result[:message].to_s, details)
        end

        # ──────────────────────────────────────────────────────────────────────────
        # certificate (saml)
        # ──────────────────────────────────────────────────────────────────────────

        def certificate_check
          pem = stored_idp_cert_pem
          if pem.nil?
            return check(
              'certificate',
              'failed',
              'The saved IdP certificate cannot be read.',
              error_code: 'invalid_certificate',
            )
          end

          cert = Onetime::SsoProvider::Saml.parse_cert(pem)
          if cert.nil?
            return check(
              'certificate',
              'failed',
              'The saved IdP certificate is not one PEM X.509 certificate.',
              error_code: 'invalid_certificate',
            )
          end

          certificate_window_check(cert)
        end

        # @return [String, nil] nil when the field cannot be revealed (the
        #   class name is logged; the message is not ours to vouch for)
        def stored_idp_cert_pem
          @sso_config.reveal_saml_field(:idp_cert)
        rescue StandardError => ex
          OT.le "[RunDiagnostics] idp_cert reveal raised #{ex.class.name} for domain #{@domain_id}"
          nil
        end

        def certificate_window_check(cert)
          now        = Time.now
          not_after  = cert.not_after.utc
          not_before = cert.not_before.utc
          window     = {
            certificate_subject: cert.subject.to_utf8,
            certificate_not_before: not_before.iso8601,
            certificate_not_after: not_after.iso8601,
            certificate_expires_in_days: ((not_after - now) / 86_400).floor,
          }

          if not_after < now
            check(
              'certificate',
              'failed',
              "The saved IdP certificate expired on #{not_after.strftime('%Y-%m-%d')}.",
              window.merge(error_code: 'certificate_expired'),
            )
          elsif not_before > now
            check(
              'certificate',
              'failed',
              "The saved IdP certificate is not valid until #{not_before.iso8601}.",
              window.merge(error_code: 'certificate_not_yet_valid'),
            )
          else
            check('certificate', 'passed', 'The saved IdP certificate is within its validity window.', window)
          end
        end

        # ──────────────────────────────────────────────────────────────────────────
        # credential (entra_id probe; oidc unsupported)
        # ──────────────────────────────────────────────────────────────────────────

        def credential_check
          return check('credential', 'unsupported', OIDC_CREDENTIAL_MESSAGE) if @provider_type == 'oidc'

          entra_credential_check
        end

        def entra_credential_check
          client_id, client_secret = reveal_client_credentials
          if client_id.nil? || client_secret.nil?
            return check(
              'credential',
              'failed',
              'The saved client credentials cannot be read.',
              error_code: 'unreadable_credentials',
            )
          end

          # Independent of the probe outcome: a UUID is the Secret ID Entra
          # shows next to the Value, and the ID is never the credential.
          shape = secret_shape(client_secret)

          result  = Onetime::SsoProvider::EntraCredentialProbe.call(
            tenant_id: @tenant_id, client_id: client_id, client_secret: client_secret,
          )
          details = { http_status: result.http_status, aadsts_code: result.aadsts_code }.compact

          case result.status
          when :passed
            details[:note] = CREDENTIAL_PASSED_NOTE
            message        = CREDENTIAL_PASSED_MESSAGE
            status         = 'passed'
          when :failed
            details[:error_code] = result.error_code
            message              = CREDENTIAL_FAILURE_MESSAGES.fetch(result.error_code, 'The identity provider rejected the saved credentials.')
            status               = 'failed'
          else
            details[:error_code] = result.error_code
            message              = CREDENTIAL_INCONCLUSIVE_MESSAGES.fetch(result.error_code, 'The credential check could not be completed.')
            status               = 'inconclusive'
          end

          if shape
            details[:secret_shape] = shape
            details[:note]         = [details[:note], SECRET_ID_SHAPE_NOTE].compact.join(' ')
          end

          check('credential', status, message, details)
        end

        # @return [Array(String, String)] or [nil, nil] when either cannot be
        #   revealed (validation_errors has already reported that as missing;
        #   this is a guard for a reveal that fails between the two reads).
        def reveal_client_credentials
          [@sso_config.client_id&.reveal { it }.to_s, @sso_config.client_secret&.reveal { it }.to_s]
        rescue StandardError => ex
          OT.le "[RunDiagnostics] credential reveal raised #{ex.class.name} for domain #{@domain_id}"
          [nil, nil]
        end

        def secret_shape(client_secret)
          'uuid' if Onetime::SsoProvider::Entra::TENANT_ID_FORMAT.match?(client_secret)
        end

        def tenant_id_uuid?
          Onetime::SsoProvider::Entra::TENANT_ID_FORMAT.match?(@tenant_id)
        end
      end
    end
  end
end
