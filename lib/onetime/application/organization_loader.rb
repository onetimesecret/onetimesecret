# lib/onetime/application/organization_loader.rb
#
# frozen_string_literal: true

#
# Organization context loading for authenticated requests.
#
# This module provides centralized logic for determining which organization
# should be active for a given authenticated user request.
#
# Selection Priority (READ-ONLY):
# 1. Explicit selection via session['organization_id']
# 2. Domain-based selection (custom domain routing)
# 3. Default organization (is_default = true)
# 4. First available organization
# 5. Return nil (lazy creation happens later in auth_org)
#
# Performance:
# - Positive results cached in session for 5 minutes
# - Negative results (nil org) are NOT cached, allowing immediate retry
# - Cache invalidated on explicit organization switch
#
# Usage:
#   class MyAuthStrategy < Otto::Security::AuthStrategy
#     include Onetime::Application::OrganizationLoader
#
#     def authenticate(env, requirement)
#       # ... authenticate user ...
#       org_context = load_organization_context(customer, session, env)
#       success(user: customer, metadata: { organization_context: org_context })
#     end
#   end

module Onetime
  module Application
    module OrganizationLoader
      # Load organization context for authenticated customer
      #
      # @param customer [Onetime::Customer] Authenticated customer
      # @param session [Hash] Rack session
      # @param env [Hash] Rack environment
      # @return [Hash] Context hash with organization data
      def load_organization_context(customer, session, env)
        return {} if customer.nil? || customer&.anonymous?

        # Check session cache first (only stores IDs, not full objects)
        cache_key = "org_context:#{customer.objid}"
        cached    = session[cache_key] if session

        if cached && cached[:expires_at] && cached[:expires_at] > Familia.now.to_i
          OT.ld "[OrganizationLoader] Using cached IDs for #{customer.objid}"

          # Reload objects from cached IDs
          org = cached[:organization_id] ? Onetime::Organization.load(cached[:organization_id]) : nil

          return {
            organization: org,
            organization_id: org&.objid,
            expires_at: cached[:expires_at],
          }
        end

        # Determine organization (read-only - no writes during auth phase)
        org = determine_organization(customer, session, env)

        # Only cache positive results (when org is found).
        # Negative results (nil) are NOT cached, allowing immediate retry
        # when org creation fails or is pending.
        if session && org
          session[cache_key] = {
            organization_id: org.objid,
            expires_at: Familia.now.to_i + 60, # 1 minute cache
          }
        end

        OT.ld "[OrganizationLoader] Loaded context for #{customer.objid}: org=#{org&.objid}"

        {
          organization: org,
          organization_id: org&.objid,
          expires_at: Familia.now.to_i + 60,
        }
      end

      # Clear organization context cache for customer
      #
      # Call this after organization switch or membership changes
      #
      # @param customer [Onetime::Customer] Customer
      # @param session [Hash] Rack session
      def clear_organization_cache(customer, session)
        return unless customer && session

        cache_key = "org_context:#{customer.objid}"
        session.delete(cache_key)

        OT.ld "[OrganizationLoader] Cleared cache for #{customer.objid}"
      end

      private

      # Determine which organization should be active for this request
      #
      # @param customer [Onetime::Customer] Authenticated customer
      # @param session [Hash] Rack session
      # @param env [Hash] Rack environment
      # @return [Onetime::Organization, nil] Selected organization
      def determine_organization(customer, session, env)
        # 1. Explicit selection from session
        if session && session['organization_id']
          org = Onetime::Organization.load(session['organization_id'])
          if org && org.member?(customer)
            OT.ld "[OrganizationLoader] Using explicit selection: #{org.objid}"
            return org
          else
            # Clear invalid selection
            session.delete('organization_id')
          end
        end

        # 2. Domain-based selection
        if env && env['HTTP_HOST']
          host   = env['HTTP_HOST'].split(':').first # Remove port
          domain = Onetime::CustomDomain.from_display_domain(host)
          if domain
            org = domain.primary_organization
            if org && org.member?(customer)
              OT.ld "[OrganizationLoader] Using domain-based selection: #{org.objid} (#{host})"
              return org
            end
          end
        end

        # 3. Default organization (preferred workspace)
        orgs        = customer.organization_instances.to_a
        default_org = orgs.find { |o| o.is_default }
        if default_org
          OT.ld "[OrganizationLoader] Using default organization: #{default_org.objid}"
          return default_org
        end

        # 4. First available organization
        first_org = orgs.first
        if first_org
          OT.ld "[OrganizationLoader] Using first organization: #{first_org.objid}"
          return first_org
        end

        # 5. No organization found - return nil (read-only phase)
        #
        # Previously this called create_default_workspace() which performed
        # Redis writes during authentication. This caused race conditions,
        # negative caching bugs, and skipped federation checks.
        #
        # Org creation now happens lazily in auth_org (Logic::OrganizationContext)
        # when an entitlement-gated action actually needs the organization.
        # See: apps/web/auth/operations/create_default_workspace.rb
        OT.ld "[OrganizationLoader] No organizations found for #{customer.objid}, deferring creation"
        nil
      end
    end
  end
end
