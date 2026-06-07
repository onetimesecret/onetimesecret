# lib/onetime/incoming/recipient_resolver.rb
#
# frozen_string_literal: true

require_relative '../models/custom_domain/incoming_config'

module Onetime
  module Incoming
    # Domain-aware recipient resolution for incoming secrets.
    #
    # Enforces the "no fallback" rule: canonical domains use global
    # boot-time recipients; custom domains use per-domain Redis config.
    # The two systems never intermix.
    #
    # @example Canonical domain
    #   resolver = RecipientResolver.new(domain_strategy: :canonical)
    #   resolver.enabled?           # => true (if YAML config enabled)
    #   resolver.public_recipients  # => global boot-time list
    #
    # @example Custom domain
    #   resolver = RecipientResolver.new(domain_strategy: :custom, display_domain: "secrets.acme.com")
    #   resolver.enabled?           # => true (if domain has recipients configured)
    #   resolver.public_recipients  # => per-domain hashed list
    #
    class RecipientResolver
      def initialize(domain_strategy:, display_domain: nil)
        @domain_strategy = domain_strategy&.to_sym
        @display_domain  = display_domain
      end

      # Check if incoming secrets are enabled for this domain context
      #
      # For custom domains:
      # - Uses IncomingConfig.enabled? toggle (explicit per-domain toggle).
      #   Absence of an IncomingConfig record means not enabled.
      # - Verifies site_secret is configured (without it, recipient hashes cannot be computed).
      #
      # @return [Boolean]
      def enabled?
        case @domain_strategy
        when :canonical, nil
          incoming_config['enabled'] || false
        when :custom
          is_enabled = custom_domain_record&.incoming_config&.enabled? || false

          return false unless is_enabled

          # Fail closed if site_secret is missing - can't compute hashes
          if site_secret.nil? || site_secret.to_s.strip.empty?
            OT.lw "[RecipientResolver] site_secret missing but custom domain #{@display_domain} has incoming enabled"
            return false
          end

          true
        else
          false
        end
      end

      # Returns hashed recipients list for frontend display.
      #
      # Custom domains delegate to IncomingConfig#public_recipients, which
      # returns string-keyed hashes ({ 'digest' => ..., 'display_name' => ... })
      # matching the canonical-domain shape from SetupIncomingRecipients.
      #
      # @return [Array<Hash>] Array of { 'digest' => ..., 'display_name' => ... }
      def public_recipients
        case @domain_strategy
        when :canonical, nil
          OT.incoming_public_recipients # Global boot-time hashed list
        when :custom
          return [] if site_secret.nil? || site_secret.to_s.strip.empty?

          custom_domain_record&.incoming_config&.public_recipients || []
        else
          []
        end
      rescue OT::Problem
        # IncomingConfig#public_recipients raises if site.secret is missing.
        # Treat as fail-closed (empty list) for callers that don't already
        # guard via enabled?.
        []
      end

      # Look up email from recipient hash
      #
      # @param hash_key [String] The recipient hash
      # @return [String, nil] Email address if found
      def lookup(hash_key)
        case @domain_strategy
        when :canonical, nil
          OT.lookup_incoming_recipient(hash_key) # Global boot-time lookup
        when :custom
          return nil if site_secret.nil? || site_secret.to_s.strip.empty?

          custom_domain_record&.incoming_config&.lookup_recipient_email(hash_key)
        end
      rescue OT::Problem
        nil
      end

      # Require that the domain-owning org has a specific entitlement.
      #
      # On canonical domains, this is a no-op (global config controls).
      # On custom domains, resolves the org that owns the domain and
      # checks its entitlements. Fails closed if no owning org can be
      # resolved for a custom domain (orphaned domain).
      #
      # @param entitlement [String] The entitlement to check
      # @param error_key [String, nil] Optional dotted i18n key for the raised
      #   EntitlementRequired. Defaults to
      #   "api.entitlements.errors.#{entitlement}_required" so locale entries
      #   can be added per-entitlement without code changes.
      # @raise [Onetime::EntitlementRequired] If org lacks the entitlement
      # @raise [OT::Forbidden] If custom domain has no resolvable owner
      # @return [true]
      def require_domain_entitlement!(entitlement, error_key: nil)
        return true unless @domain_strategy == :custom

        entitlement = entitlement.to_s
        error_key ||= "api.entitlements.errors.#{entitlement}_required"

        owning_org = custom_domain_record&.primary_organization

        if owning_org.nil?
          raise OT::Forbidden.new(
            'Custom domain organization could not be resolved',
            error_key: 'api.incoming.errors.custom_domain_unresolved',
          )
        end

        return true if owning_org.can?(entitlement)

        current_plan = owning_org.planid
        upgrade_to   = if defined?(Billing::PlanHelpers)
                         Billing::PlanHelpers.upgrade_path_for(entitlement, current_plan)
                       end

        raise Onetime::EntitlementRequired.new(
          entitlement,
          current_plan: current_plan,
          upgrade_to: upgrade_to,
          error_key: error_key,
          args: { entitlement: entitlement },
        )
      end

      # Returns full config data for GetConfig API response.
      #
      # No cross-system fallback: custom domains use their own config
      # or defaults; canonical domains use global YAML config.
      #
      # @return [Hash] Config data for API response
      def config_data
        defaults = Onetime::CustomDomain::IncomingConfig::DEFAULTS
        case @domain_strategy
        when :custom
          config = custom_domain_record&.incoming_config
          {
            enabled: enabled?,
            memo_max_length: config&.memo_max_length || defaults[:memo_max_length],
            default_ttl: config&.default_ttl || defaults[:default_ttl],
            recipients: public_recipients,
          }
        else
          # Canonical or nil — use global YAML config
          {
            enabled: enabled?,
            memo_max_length: incoming_config['memo_max_length'] || defaults[:memo_max_length],
            default_ttl: incoming_config['default_ttl'] || defaults[:default_ttl],
            recipients: public_recipients,
          }
        end
      end

      private

      def incoming_config
        OT.conf.dig('features', 'incoming') || {}
      end

      def site_secret
        OT.conf.dig('site', 'secret')
      end

      def custom_domain_record
        return nil unless @display_domain

        @custom_domain_record ||= Onetime::CustomDomain.from_display_domain(@display_domain)
      end
    end
  end
end
