# lib/onetime/application/organization_loader.rb
#
# frozen_string_literal: true

#
# Organization and Team context loading for authenticated requests.
#
# This module provides centralized logic for determining which organization
# and team should be active for a given authenticated user request.
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
# - Lazy loading of team context (only when needed)
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
      # Load organization and team context for authenticated customer
      #
      # @param customer [Onetime::Customer] Authenticated customer
      # @param session [Hash] Rack session
      # @param env [Hash] Rack environment
      # @return [Hash] Context hash with organization and team data
      def load_organization_context(customer, session, env)
        return {} if customer.nil? || customer.anonymous?

        # Check session cache first
        cache_key = "org_context:#{customer.objid}"
        cached    = session[cache_key] if session

        if cached && cached[:expires_at] && cached[:expires_at] > Familia.now.to_i
          OT.ld "[OrganizationLoader] Using cached context for #{customer.objid}"
          return cached
        end

        # Determine organization and team
        org  = determine_organization(customer, session, env)
        team = determine_team(org, customer, session) if org

        context = {
          organization: org,
          organization_id: org&.objid,
          team: team,
          team_id: team&.objid,
          expires_at: Familia.now.to_i + 300, # 5 minute cache
        }

        # Cache in session
        session[cache_key] = context if session

        OT.ld "[OrganizationLoader] Loaded context for #{customer.objid}: org=#{org&.objid}, team=#{team&.objid}"

        context
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
          host = env['HTTP_HOST'].split(':').first # Remove port
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

      # Determine which team should be active within the organization
      #
      # @param organization [Onetime::Organization] Active organization
      # @param customer [Onetime::Customer] Authenticated customer
      # @param session [Hash] Rack session
      # @return [Onetime::Team, nil] Selected team
      def determine_team(organization, customer, session)
        return nil unless organization

        # 1. Explicit selection from session
        if session && session['team_id']
          team = Onetime::Team.load(session['team_id'])
          if team && team.org_id == organization.objid && team.member?(customer)
            OT.ld "[OrganizationLoader] Using explicit team selection: #{team.objid}"
            return team
          else
            # Clear invalid selection
            session.delete('team_id')
          end
        end

        # 2. First team in organization where customer is a member
        team_ids = organization.teams.to_a
        return nil if team_ids.empty?

        teams = Onetime::Team.load_multi(team_ids).compact
        member_team = teams.find { |t| t.member?(customer) }

        if member_team
          OT.ld "[OrganizationLoader] Using first team: #{member_team.objid}"
          return member_team
        end

        nil
      end

      # Create default workspace (organization + team) for customer
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

        # Create default organization
        display_name = "#{customer.email}'s Workspace"
        org = Onetime::Organization.create!(display_name, customer, customer.email)
        org.is_default = true
        org.save

        OT.info "[OrganizationLoader] Created default organization #{org.objid} for #{customer.objid}"

        # Create default team
        team = Onetime::Team.create!('Default Team', customer, org.objid)
        OT.info "[OrganizationLoader] Created default team #{team.objid} in org #{org.objid}"

        org
      rescue StandardError => ex
        OT.le "[OrganizationLoader] Failed to create default workspace: #{ex.message}"
        OT.ld ex.backtrace.first(3).join("\n")
        nil
      end
    end
  end
end
