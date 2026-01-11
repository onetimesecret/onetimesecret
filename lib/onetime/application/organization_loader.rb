# lib/onetime/application/organization_loader.rb
#
# frozen_string_literal: true

#
# Organization context loading for authenticated requests.
#
# This module provides centralized logic for determining which organization
# should be active for a given authenticated user request.
#
# Selection Priority:
# 1. Explicit selection via session['organization_id']
# 2. Domain-based selection (custom domain routing)
# 3. Default organization (is_default = true)
# 4. First available organization
# 5. Auto-create default workspace (self-healing)
#
# Performance:
# - Results cached in session for 5 minutes
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
        return {} if customer.nil? || customer.anonymous?

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

        # Determine organization
        org = determine_organization(customer, session, env)

        # Store only IDs in session cache (not full objects - they can't serialize)
        if session
          session[cache_key] = {
            organization_id: org&.objid,
            expires_at: Familia.now.to_i + 300, # 5 minute cache
          }
        end

        OT.ld "[OrganizationLoader] Loaded context for #{customer.objid}: org=#{org&.objid}"

        {
          organization: org,
          organization_id: org&.objid,
          expires_at: Familia.now.to_i + 300,
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

        # 5. Auto-create default workspace (self-healing)
        OT.info "[OrganizationLoader] No organizations found for #{customer.objid}, creating default"
        create_default_workspace(customer)
      end

      # Create default workspace (organization) for customer
      #
      # This is a self-healing mechanism for customers who don't have
      # any organizations yet (e.g., legacy users, or edge cases).
      #
      # @param customer [Onetime::Customer] Customer needing workspace
      # @return [Onetime::Organization] Created organization
      def create_default_workspace(customer)
        # Check if another request already created it
        orgs = customer.organization_instances.to_a
        return orgs.first if orgs.any?

        # Create default organization (self-healing fallback)
        # See: apps/web/auth/operations/create_default_workspace.rb
        display_name = "#{customer.email}'s Workspace"
        org          = Onetime::Organization.create!(display_name, customer, customer.email, is_default: true)

        OT.info "[OrganizationLoader] Created default organization #{org.objid} for #{customer.objid}"

        org
      rescue StandardError => ex
        OT.le "[OrganizationLoader] Failed to create default workspace: #{ex.message}"
        OT.ld ex.backtrace.first(3).join("\n")
        nil
      end
    end
  end
end
