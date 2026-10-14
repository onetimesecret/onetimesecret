# lib/onetime/models/custom_domain/serving_policy.rb
#
# frozen_string_literal: true

module Onetime
  class CustomDomain < Familia::Horreum
    # Whether a registered custom domain is served as a tenant domain.
    #
    # One answer for every consumer that serves, publishes or selects a
    # custom-domain hostname:
    #
    # - Onetime::Middleware::DomainStrategy classifies a registered host
    #   :custom only when #served_as_tenant? is true, and :unverified (answered
    #   with a 404) otherwise.
    # - Secret creation accepts a custom share_domain only on the same answer
    #   (V1/V2 BaseSecretAction#validate_domain_verification).
    # - The domain-context picker lists, and UpdateDomainContext accepts, only
    #   such domains.
    #
    # Auth-link hosts (Auth::PublicHost), tenant SSO, the tenant CSP extras and
    # the ACME ask keep their own, stricter checks on the verified flag (and,
    # for the ask, on resolving).
    #
    # Every read here uses loaded fields and configuration only: no datastore
    # or DNS I/O.
    module ServingPolicy
      def self.included(base)
        base.extend(ClassMethods)
      end

      # Ownership basis for serving this domain, without the operator's
      # features.domains.serve_unverified setting.
      #
      # - A record with no organization is never served.
      # - Under a validation strategy that does not prove ownership
      #   (passthrough), registration by the owning organization is the basis
      #   (ADR-049), so an owned record is served.
      # - Otherwise ownership must be verified, by the strategy's TXT check or
      #   by a colonel override. Both set ownership_verified.
      #
      # @return [Boolean]
      def serving_authorized?
        return false if org_id.to_s.empty?
        return true unless self.class.ownership_proof_required?

        ownership_verified == true
      end

      # #serving_authorized?, or any record with an organization while the
      # operator has set features.domains.serve_unverified to true. A record
      # with no organization is never served, whatever the setting.
      #
      # @return [Boolean]
      def served_as_tenant?
        return false if org_id.to_s.empty?

        serving_authorized? || self.class.serve_unverified?
      end

      module ClassMethods
        SERVE_UNVERIFIED_WARNING = Mutex.new
        private_constant :SERVE_UNVERIFIED_WARNING

        # Whether the install's validation strategy proves ownership
        # (Onetime::DomainValidation::BaseStrategy#proves_ownership?):
        # true for approximated and caddy_on_demand, false for passthrough.
        #
        # Decided from the same configuration Strategy.for_config reads, and
        # kept for as long as that configuration is unchanged. A different
        # validation_strategy or strict_strategy value (a spec that swaps
        # OT.conf) is decided again on the next call; nothing has to be reset.
        #
        # A strategy that cannot be built (an unknown name under
        # strict_strategy) answers true, so serving fails closed.
        #
        # @return [Boolean]
        def ownership_proof_required?
          domains = configured_domains_section
          key     = [domains['validation_strategy'], domains['strict_strategy'] == true]
          decided = @ownership_proof_required
          return decided.last if decided && decided.first == key

          answer                    = strategy_proves_ownership?(domains)
          @ownership_proof_required = [key, answer].freeze
          answer
        end

        # features.domains.serve_unverified, read as a strict boolean. When
        # true, a record with an organization is served whatever its
        # ownership state (#served_as_tenant?).
        #
        # @return [Boolean]
        def serve_unverified?
          configured_domains_section['serve_unverified'] == true
        end

        # Logs one warning per process while features.domains.serve_unverified
        # is true. Called at boot by Onetime::Initializers::ConfigureDomains;
        # serving a request logs nothing.
        #
        # @return [Boolean] whether this call logged the warning
        def warn_if_serve_unverified
          return false unless serve_unverified?

          SERVE_UNVERIFIED_WARNING.synchronize do
            return false if @serve_unverified_warned

            @serve_unverified_warned = true
          end

          Onetime.get_logger('App').warn 'custom_domain.serve_unverified_enabled',
            {
              setting: 'features.domains.serve_unverified',
              effect: 'custom domains that have an organization are served whatever their ownership state',
            }
          true
        end

        # Clears the decided strategy and the warning latch. For specs.
        #
        # @return [void]
        def reset_serving_policy!
          SERVE_UNVERIFIED_WARNING.synchronize do
            @ownership_proof_required = nil
            @serve_unverified_warned  = false
          end
        end

        private

        def configured_domains_section
          conf    = OT.conf
          domains = conf.respond_to?(:dig) ? conf.dig('features', 'domains') : nil
          domains.is_a?(Hash) ? domains : {}
        end

        def strategy_proves_ownership?(domains)
          require_relative '../../domain_validation/strategy'

          config = { 'features' => { 'domains' => domains } }
          Onetime::DomainValidation::Strategy.for_config(config).proves_ownership? == true
        rescue StandardError => ex
          OT.le "[CustomDomain.ownership_proof_required?] #{ex.class}: #{ex.message}; " \
                'treating ownership proof as required'
          true
        end
      end
    end
  end
end
