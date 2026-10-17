# apps/api/domains/logic/sso_config/run_diagnostics.rb
#
# frozen_string_literal: true

require 'time'
require 'onetime/models/custom_domain/sso_config'
require_relative 'base'
require_relative 'change_logger'
require_relative 'discovery_check'
require_relative '../../../../../lib/onetime/sso_provider/entra'
require_relative '../../../../../lib/onetime/sso_provider/entra_credential_probe'
require 'onetime/security/sso_diagnostics_rate_limiter'
require 'onetime/models/colonel_audit_event'

module DomainsAPI
  module Logic
    module SsoConfig
      # Check the SAVED SSO configuration of a custom domain
      #
      # @api Runs diagnostics against the stored SsoConfig record (not the
      #   form, which is TestConnection's job) and reports each layer
      #   separately, per docs/runbooks/sso-credential-health.md:
      #
      #   stored_configuration  all providers; the record reloaded,
      #                         SsoConfig#validation_errors, and every stored
      #                         client credential decrypts. When it fails,
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
      # Params:
      # - activate: Optional boolean. When the run passes, turn the stored
      #   record on (enabled = true). A run that fails or is inconclusive
      #   never activates, and no run turns a record off. The write commits
      #   only while the stored credential fields still match the ones the
      #   checks ran against (SsoConfig#credential_fingerprint, compared
      #   under WATCH), so an edit that lands during the provider calls
      #   leaves the record off. Activation emits the same
      #   domain_sso_config_enabled change event as PUT/PATCH, and refuses
      #   the records PUT/PATCH would refuse to switch on: a provider type
      #   outside PROVIDER_TYPES (validate_provider_type) and a saml record
      #   while SAML is off on the install (reject_saml_disabled!). The
      #   sign-in ladder refuses both anyway; this keeps the stored flag
      #   from claiming a state no write path allows.
      #
      # Response:
      # - user_id, provider_type, checked_at (ISO 8601 UTC)
      # - configuration_revision: SsoConfig#updated of the record checked, as
      #   loaded before any activation write (may be empty)
      # - overall: passed | failed | inconclusive — failed if any check
      #   failed; else inconclusive if any check inconclusive; else passed.
      #   unsupported and skipped checks do not affect it.
      # - checks: [{ check, status, message, details }], status one of
      #   passed | failed | inconclusive | unsupported | skipped
      # - enabled: the record's enabled state after the run
      # - activation: one of ACTIVATION_OUTCOMES
      #   not_requested          activate was not sent
      #   activated              this run turned the record on
      #   already_enabled        the record was on before this run wrote
      #   not_passed             overall was failed or inconclusive
      #   not_permitted          the provider type is unsupported, or saml
      #                          while SAML is off on the install
      #   configuration_changed  the credential fields changed, or the
      #                          record was deleted, while the checks ran
      # - activated_revision: only when activation is `activated`: the
      #   SsoConfig#updated the activation wrote. A client whose loaded
      #   record matched configuration_revision adopts it, so its next run
      #   is not mistaken for one about a record saved elsewhere.
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
      # Every completed run writes one `sso.diagnostics_run` event: the
      # acting customer, the domain, the overall verdict as the result, and
      # the configuration revision and each check's status and bare codes
      # in the detail. An owner's run is a self-service action and goes to
      # the SECURITY audit trail (Onetime::ColonelAuditEvent.record_security),
      # out of the operator trail (`events`), whose count cap with no TTL is
      # reserved for operator activity; a per-writer rate limit does not
      # protect that budget (ColonelAuditEvent's write-frequency invariant).
      # Self-service account purge records the same way. A colonel passes
      # the entitlement check on any domain (require_entitlement_in!), and
      # that run is operator activity, so it goes to the operator trail.
      # The event never carries a message, the secret, a token or Entra's
      # error_description. The write is best-effort on both trails: neither
      # writer raises, so a broken audit write never fails the run.
      #
      class RunDiagnostics < Base
        include DiscoveryCheck
        include ChangeLogger
        include Onetime::Security::SsoDiagnosticsRateLimiter

        STATUSES = %w[passed failed inconclusive unsupported skipped].freeze

        ACTIVATION_OUTCOMES = %w[
          not_requested activated already_enabled not_passed not_permitted configuration_changed
        ].freeze

        # Audit verb for one completed run. Namespaced `<resource>.<action>`
        # like the limiter's `sso.diagnostics_throttled`.
        AUDIT_VERB = 'sso.diagnostics_run'

        SKIPPED_MESSAGE = 'Fix the stored configuration first'

        TENANT_ID_FORMAT_ERROR = 'tenant_id must be a valid UUID for Entra ID provider'

        CREDENTIAL_PASSED_MESSAGE = 'Microsoft Entra ID accepted the saved client secret.'
        CREDENTIAL_PASSED_NOTE    = 'This check does not complete a user sign-in. Sign in through the custom domain once ' \
                                    'to verify the redirect URI, user assignment, Conditional Access policies, and claims.'
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
          @activate  = parse_boolean(params['activate'])
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

          # The credentials the checks below run against; activation
          # commits only while the stored record still has them.
          @checked_fingerprint = @sso_config.credential_fingerprint if @activate

          # Last, so only a run that will actually happen is charged.
          enforce_sso_diagnostics_rate_limit!(cust.extid)
        end

        def process
          OT.ld "[RunDiagnostics] Checking saved #{@provider_type} configuration for domain #{@domain_id}"

          @checked_at = Time.now.utc
          @checks     = run_checks
          @overall    = compute_overall(@checks)
          @activation = activate_if_requested

          OT.info "[RunDiagnostics] Saved configuration check #{@overall} for #{@provider_type}",
            {
              domain_id: @domain_id,
              provider_type: @provider_type,
              overall: @overall,
              activation: @activation,
              checks: @checks.to_h { |check| [check[:check], check[:status]] },
            }

          record_audit_event

          success_data
        end

        def success_data
          data                      = {
            user_id: cust.extid,
            provider_type: @provider_type,
            checked_at: @checked_at.iso8601,
            configuration_revision: @sso_config.updated.to_s,
            overall: @overall,
            checks: @checks,
            enabled: @enabled_after,
            activation: @activation,
          }
          data[:activated_revision] = @activated_revision if @activated_revision
          data
        end

        def form_fields
          { domain_id: @domain_id }
        end

        private

        # ──────────────────────────────────────────────────────────────────────────
        # Audit
        # ──────────────────────────────────────────────────────────────────────────

        # One event per completed run, on the trail the class note gives
        # (security for an owner, operator for a colonel). Statuses and bare
        # codes only: the
        # check messages are not copied (the discovery ones are built from
        # the fetch), and nothing here can hold the secret, a token or
        # Entra's error_description because no check stores them.
        #
        # The trail's redaction pass blanks every hash KEY matching
        # ColonelAuditEvent::SENSITIVE_KEY_PATTERN at any depth, and both
        # `credential` and `secret` match. So each check is an entry with the
        # check name as a VALUE, and the Secret-ID-shaped flag is `shape`,
        # not `secret_shape`.
        def record_audit_event
          record_on_actor_trail(
            actor: cust,
            verb: AUDIT_VERB,
            target: @custom_domain.identifier,
            result: @overall == 'failed' ? :failure : :success,
            detail: {
              display_domain: @custom_domain.display_domain,
              provider_type: @provider_type,
              overall: @overall,
              activation: @activation,
              checked_at: @checked_at.iso8601,
              configuration_revision: @sso_config.updated.to_s,
              checks: @checks.map { audit_check_entry(it) },
            }.compact,
          )
        end

        # Security trail for an owner, operator trail for a colonel (see the
        # class note).
        def record_on_actor_trail(**event)
          if has_system_role?('colonel')
            Onetime::ColonelAuditEvent.record(**event)
          else
            Onetime::ColonelAuditEvent.record_security(**event)
          end
        end

        # @return [Hash] { check:, status: } plus error_code, aadsts_code
        #   and shape when the check reported them.
        def audit_check_entry(check)
          details = check[:details] || {}
          {
            check: check[:check],
            status: check[:status],
            error_code: details[:error_code],
            aadsts_code: details[:aadsts_code],
            shape: details[:secret_shape],
          }.compact
        end

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

        # ──────────────────────────────────────────────────────────────────────────
        # Activation
        # ──────────────────────────────────────────────────────────────────────────

        # Sets @enabled_after and returns the activation outcome (see the
        # class note). The guarded write re-reads the record under WATCH,
        # so the fingerprint and enabled state compared are the stored ones,
        # not this request's copy, which is as old as the provider calls.
        #
        # @return [String] one of ACTIVATION_OUTCOMES
        def activate_if_requested
          # Early outcomes report storage after the checks, not the checked
          # snapshot. Activation attempts use the guarded write's state below.
          stored         = Onetime::CustomDomain::SsoConfig.find_by_domain_id(@custom_domain.identifier)
          @enabled_after = stored&.enabled? || false
          return 'not_requested' unless @activate
          return 'not_passed' unless @overall == 'passed'
          # provider_type is part of the fingerprint, so the guarded write
          # below refuses a record whose type changed after this check.
          return 'not_permitted' unless activation_permitted?

          refusal        = nil
          stored_enabled = false
          condition      = ->(stored) {
            stored_enabled = stored.enabled?
            refusal        = if stored.credential_fingerprint != @checked_fingerprint
                               'configuration_changed'
                             elsif stored_enabled
                               'already_enabled'
                             end
            refusal.nil?
          }
          # A write aborted by a concurrent change runs the block again, so
          # the value kept is the one from the attempt that committed.
          written_at     = nil
          committed      = Onetime::CustomDomain::SsoConfig.update_for_domain_if(@custom_domain.identifier, condition) do |stored|
            written_at     = Familia.now.to_i
            stored.enabled = true
            stored.updated = written_at
          end

          # nil: the condition refused, or the record is gone. A refusal
          # returns at once, so refusal and stored_enabled describe the
          # stored record. Gone: the condition never ran on the attempt that
          # returned (a retry follows only an aborted write), refusal is
          # nil, and there is no record to be on.
          unless committed
            @enabled_after = refusal.nil? ? false : stored_enabled
            return refusal || 'configuration_changed'
          end

          @enabled_after      = true
          @activated_revision = written_at.to_s
          log_sso_change_event(
            event: :domain_sso_config_enabled,
            domain: @custom_domain,
            org: @organization,
            actor: cust,
            provider_type: @provider_type,
          )
          'activated'
        end

        # PUT/PATCH's refusals for switching a record on that no check
        # above repeats (see the class note).
        #
        # @return [Boolean]
        def activation_permitted?
          return false unless Onetime::CustomDomain::SsoConfig::PROVIDER_TYPES.include?(@provider_type)
          return false if @provider_type == 'saml' && !Onetime::SsoProvider::Saml.enabled?

          true
        end

        def check(name, status, message, details = {})
          raise ArgumentError, "unknown check status #{status.inspect}" unless STATUSES.include?(status)

          { check: name, status: status, message: message, details: details }
        end

        # ──────────────────────────────────────────────────────────────────────────
        # stored_configuration
        # ──────────────────────────────────────────────────────────────────────────

        # validation_errors reports an undecryptable client credential as
        # missing ("client_secret is required"), and for oidc, whose secret
        # is optional, not at all, although build_oidc_options reveals it and
        # raises at sign-in. So a credential that is stored but will not
        # decrypt is reported here as unreadable instead. No error carries a
        # value.
        #
        # SsoConfig#validation_errors only requires tenant_id to be non-empty
        # for entra_id; the UUID shape is enforced on the write path
        # (TestConnection#validate_entra_id_fields). Both later checks
        # interpolate the stored tenant_id into a login.microsoftonline.com
        # path, so it is checked here, before either runs, and a non-UUID
        # value fails this check and skips the rest rather than sending an
        # unvalidated path segment to discovery while the probe refuses it.
        def stored_configuration_check
          unreadable = unreadable_client_credentials
          errors     = @sso_config.validation_errors.map(&:to_s) - unreadable.map { "#{it} is required" }
          errors.concat(unreadable.map { "#{it} cannot be read (re-enter the value)" })
          errors << TENANT_ID_FORMAT_ERROR if @provider_type == 'entra_id' && !tenant_id_uuid?
          if errors.empty?
            check('stored_configuration', 'passed', 'The saved configuration is complete and readable.')
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

        # Client credentials that are stored but fail to reveal, in the
        # wording SsoConfig#saml_validation_errors uses for the SAML trio.
        # An unset credential is not unreadable: an oidc public client has
        # no secret.
        #
        # @return [Array<String>] subset of client_id, client_secret
        def unreadable_client_credentials
          return [] unless Onetime::CustomDomain::SsoConfig.client_credentials?(@provider_type)

          %w[client_id client_secret].select do |name|
            @sso_config.public_send(name)&.reveal { nil }
            false
          rescue StandardError
            true
          end
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
        #   revealed (stored_configuration has already reported that as
        #   unreadable; this is a guard for a reveal that fails between the
        #   two reads).
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
