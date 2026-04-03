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
      # - Uses IncomingConfig.enabled? toggle (new model with explicit toggle)
      # - Falls back to legacy IncomingSecretsConfig.has_incoming_recipients? if no IncomingConfig exists
      # - Verifies site_secret is configured (without it, recipient hashes cannot be computed)
      #
      # @return [Boolean]
      def enabled?
        case @domain_strategy
        when :canonical, nil
          incoming_config['enabled'] || false
        when :custom
          # Use new IncomingConfig model if it exists (explicit enabled toggle)
          # Otherwise fall back to legacy IncomingSecretsConfig (has_incoming_recipients?)
          config     = custom_domain_record&.incoming_config
          is_enabled = if config
                         config.enabled?
                       else
                         # Legacy fallback: enabled if recipients exist
                         custom_domain_record&.incoming_secrets_config&.has_incoming_recipients? || false
                       end

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

      # Returns hashed recipients list for frontend display
      #
      # @return [Array<Hash>] Array of {hash:, name:} hashes
      def public_recipients
        case @domain_strategy
        when :canonical, nil
          OT.incoming_public_recipients # Global boot-time hashed list
        when :custom
          custom_domain_record&.cached_public_incoming_recipients(site_secret) || []
        else
          []
        end
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
          custom_domain_record&.cached_incoming_recipient_lookup(site_secret)&.[](hash_key)
        end
      end

      # Require that the domain-owning org has a specific entitlement.
      #
      # On canonical domains, this is a no-op (global config controls).
      # On custom domains, resolves the org that owns the domain and
      # checks its entitlements. Fails closed if no owning org can be
      # resolved for a custom domain (orphaned domain).
      #
      # @param entitlement [String] The entitlement to check
      # @raise [Onetime::EntitlementRequired] If org lacks the entitlement
      # @raise [OT::Forbidden] If custom domain has no resolvable owner
      # @return [true]
      def require_domain_entitlement!(entitlement)
        return true unless @domain_strategy == :custom

        owning_org = custom_domain_record&.primary_organization

        if owning_org.nil?
          raise OT::Forbidden, 'Custom domain organization could not be resolved'
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
        )
      end

      # Returns full config data for GetConfig API response.
      #
      # No cross-system fallback: custom domains use their own config
      # or defaults; canonical domains use global YAML config.
      #
      # @return [Hash] Config data for API response
      def config_data
        defaults = Onetime::CustomDomain::IncomingSecretsConfig::DEFAULTS
        case @domain_strategy
        when :custom
          config = custom_domain_config
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

      # Returns IncomingSecretsConfig only for custom domains
      def custom_domain_config
        return nil unless @domain_strategy == :custom

        custom_domain_record&.incoming_secrets_config
      end
    end
  end
end
