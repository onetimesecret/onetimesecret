# lib/onetime/application/organization_loader.rb
#
# frozen_string_literal: true

require_relative '../utils/canonical_hosts'
require_relative '../middleware/domain_strategy'

#
# Organization context loading for authenticated requests.
#
# This module provides centralized logic for determining which organization
# should be active for a given authenticated user request.
#
# Selection Priority (READ-ONLY):
# 0. Explicit header override via O-Organization-ID (SPA org switches)
# 1. Explicit selection via session['organization_id']
# 2. Domain-based selection (custom domain routing)
# 3. Customer's default_org_id (per-customer preference set by support)
# 4. Organization with is_default flag (typically personal workspace)
# 5. First available organization
# 6. Return nil (lazy creation happens later in auth_org)
#
# Domain scope:
# Every selection above (header, cache hit, session, domain, fallbacks) is
# subject to the membership's domain scope when the request has a custom
# domain. See #scope_permits? for where the request's domains come from.
# When the scope leaves no organization, the context carries
# domain_scope_refused: true and auth_org does not select one either.
#
# Performance:
# - Positive results cached in session for 5 minutes
# - Negative results (nil org) are NOT cached, allowing immediate retry
# - Cache invalidated on explicit organization switch
# - The cache entry is written with symbol keys and the session blob is
#   JSON (Onetime::SessionCodec), so an entry read back on a LATER request
#   has string keys and the symbol-key reads below miss it. In practice
#   the entry is hit only by a second load in the request that wrote it
#   (Sessions::TrackMetadata at commit). Pinned in
#   spec/unit/organization_loader_cache_scope_spec.rb; left as it is here.
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
      # Cache TTL for organization context (seconds)
      CACHE_TTL = 300

      # Load organization context for authenticated customer
      #
      # @param customer [Onetime::Customer] Authenticated customer
      # @param session [Hash] Rack session
      # @param env [Hash] Rack environment
      # @return [Hash] Context hash with organization data
      def load_organization_context(customer, session, env)
        return {} if customer.nil? || customer&.anonymous?

        cache_key = "org_context:#{customer.objid}"

        # Resolve the request's scope before any selection, including cache hits.
        # Canonical hosts need no lookup; a failed custom-domain read raises here.
        domains = request_scope_domains(env)

        # Check header override BEFORE cache — SPA org switches must bypass cache
        header_result = resolve_header_context(customer, session, cache_key, env, domains)
        return header_result if header_result

        # Check session cache (only stores IDs, not full objects)
        cached = session[cache_key] if session

        if cached && cached[:expires_at] && cached[:expires_at] > Familia.now.to_i
          OT.ld "[OrganizationLoader] Using cached IDs for #{customer.objid}"

          # Reload objects from cached IDs
          org = cached[:organization_id] ? Onetime::Organization.load(cached[:organization_id]) : nil

          # Invalidate cache if the org was archived since it was cached
          # (e.g. SSO self-heal archived the personal workspace mid-session)
          if org&.archived?
            session.delete(cache_key)
            OT.ld "[OrganizationLoader] Cached org #{org.objid} is archived, invalidating"
          elsif org && !scope_permits?(org, customer, domains)
            # The entry was written for another domain, or the membership's
            # scope changed since. Drop it and select again below.
            session.delete(cache_key)
            OT.ld "[OrganizationLoader] Cached org #{org.objid} is outside the member's domain scope, invalidating"
          else
            return {
              organization: org,
              organization_id: org&.objid,
              expires_at: cached[:expires_at],
            }
          end
        end

        # Determine organization (read-only - no writes during auth phase)
        org = determine_organization(customer, session, env, domains)

        # Only cache positive results (when org is found).
        # Negative results (nil) are NOT cached, allowing immediate retry
        # when org creation fails or is pending.
        if session && org
          session[cache_key] = {
            organization_id: org.objid,
            expires_at: Familia.now.to_i + CACHE_TTL,
          }
        end

        OT.ld "[OrganizationLoader] Loaded context for #{customer.objid}: org=#{org&.objid}"

        context = {
          organization: org,
          organization_id: org&.objid,
          expires_at: Familia.now.to_i + CACHE_TTL,
        }

        # No organization because the domain scope withheld one is a refusal,
        # not the "no workspace yet" case. Logic::OrganizationContext#auth_org
        # reads this and returns nil instead of falling back to the customer's
        # first organization.
        context[:domain_scope_refused] = true if org.nil? && scope_withheld_any?(customer, domains)

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
      # rubocop:disable Metrics/PerceivedComplexity -- 6-step priority chain is inherently branchy
      # @param customer [Onetime::Customer] Authenticated customer
      # @param session [Hash] Rack session
      # @param env [Hash] Rack environment
      # @param domains [Array<Onetime::CustomDomain>] the request's custom
      #   domains, from #request_scope_domains
      # @return [Onetime::Organization, nil] Selected organization
      def determine_organization(customer, session, env, domains = request_scope_domains(env))
        # NOTE: Header override (O-Organization-ID) is handled in load_organization_context
        # BEFORE the cache check. If we reach here, no valid header was present.

        # 1. Explicit selection from session
        if session && session['organization_id']
          org = Onetime::Organization.load(session['organization_id'])
          if org && org.member?(customer)
            if scope_permits?(org, customer, domains)
              OT.ld "[OrganizationLoader] Using explicit selection: #{org.objid}"
              return org
            end
            # A member, but not on this request's domain. The selection is
            # kept (it is valid on the domain the membership is scoped to)
            # and the steps below choose among what the scope permits.
            OT.ld "[OrganizationLoader] Explicit selection outside the member's domain scope: #{org.objid}"
          else
            # Clear invalid selection
            session.delete('organization_id')
          end
        end

        # 2. Domain-based selection. Which organization a request is GIVEN is
        # keyed on the Host header's record only, as before; whether it may
        # be given is decided over all of the request's domains.
        if env && env['HTTP_HOST']
          host   = env['HTTP_HOST'].split(':').first # Remove port
          domain = request_host_domain(env, host)
          if domain
            org = domain.primary_organization
            if org && org.member?(customer)
              if scope_permits?(org, customer, domains)
                OT.ld "[OrganizationLoader] Using domain-based selection: #{org.objid} (#{host})"
                return org
              end
              OT.ld "[OrganizationLoader] Domain-scoped member cannot access #{host}: #{customer.objid}"
            end
          end
        end

        # 3. Customer's explicitly set default organization
        # This takes precedence over the org's is_default flag, allowing
        # customer support to set a specific org as default per-customer.
        #
        # Steps 3-5 choose only among organizations the membership's domain
        # scope permits for this request, so an organization refused above
        # cannot come back through a different selection path. With no
        # custom domain on the request nothing is filtered and no membership
        # is read.
        orgs = customer.organization_instances.to_a
        orgs = orgs.select { |o| scope_permits?(o, customer, domains) } unless domains.empty?

        if customer.default_org_id.to_s.length.positive?
          customer_default = orgs.find { |o| o.objid == customer.default_org_id && !o.archived? }
          if customer_default
            OT.ld "[OrganizationLoader] Using customer's default_org_id: #{customer_default.objid}"
            return customer_default
          else
            # Customer's default_org_id references an org they're not a member of,
            # or the org is archived. Fall through to other selection methods.
            OT.ld "[OrganizationLoader] Customer default_org_id archived/invalid/not member: #{customer.default_org_id}"
          end
        end

        # 4. Organization with is_default flag (typically personal workspace)
        #    Skip archived default workspaces — they've been superseded by a domain org.
        default_org = orgs.find { |o| o.is_default && !o.archived? }
        if default_org
          OT.ld "[OrganizationLoader] Using organization is_default flag: #{default_org.objid}"
          return default_org
        end

        # 5. First available organization (skip archived — they've been superseded)
        first_org = orgs.find { |o| !o.archived? }
        if first_org
          OT.ld "[OrganizationLoader] Using first organization: #{first_org.objid}"
          return first_org
        end

        # 6. No organization found - return nil (read-only phase)
        #
        # Previously this called ensure_default_workspace() which performed
        # Redis writes during authentication. This caused race conditions,
        # negative caching bugs, and skipped federation checks.
        #
        # Org creation now happens lazily in auth_org (Logic::OrganizationContext)
        # when an entitlement-gated action actually needs the organization.
        # See: apps/web/auth/operations/ensure_default_workspace.rb
        OT.ld "[OrganizationLoader] No organizations found for #{customer.objid}, deferring creation"
        nil
      end
      # rubocop:enable Metrics/PerceivedComplexity

      # Handle header-based org selection with cache short-circuit.
      # Returns a context hash if header resolves, nil otherwise.
      def resolve_header_context(customer, session, cache_key, env, domains)
        org_id_header = env&.dig('HTTP_O_ORGANIZATION_ID')
        return unless org_id_header.is_a?(String) && !org_id_header.empty?

        # Short-circuit: if header matches cached org and TTL is valid,
        # skip membership re-validation. The domain scope is still checked:
        # the entry may have been written on another domain.
        cached = session[cache_key] if session
        if cached && cached[:organization_id] == org_id_header && cached[:expires_at]&.>(Familia.now.to_i)
          org = Onetime::Organization.load(cached[:organization_id])
          if org && scope_permits?(org, customer, domains)
            OT.ld "[OrganizationLoader] Header cache hit for #{org.objid}"
            return { organization: org, organization_id: org.objid, expires_at: cached[:expires_at] }
          elsif org
            session.delete(cache_key)
            OT.ld "[OrganizationLoader] Header cache org #{org.objid} is outside the member's domain scope, invalidating"
          end
        end

        # Cache miss or org switch — full membership + scope validation
        header_org = resolve_header_org(customer, env, domains)
        return unless header_org

        OT.ld "[OrganizationLoader] Using header override: #{header_org.objid}"
        expires = Familia.now.to_i + CACHE_TTL
        if session
          session[cache_key] = { organization_id: header_org.objid, expires_at: expires }
        end
        { organization: header_org, organization_id: header_org.objid, expires_at: expires }
      end

      # Resolve org from O-Organization-ID header, verifying membership
      # and domain scope. Returns nil if header absent, invalid, or denied.
      def resolve_header_org(customer, env, domains)
        org_id_header = env&.dig('HTTP_O_ORGANIZATION_ID')
        return unless org_id_header.is_a?(String) && !org_id_header.empty?

        org = Onetime::Organization.load(org_id_header)
        unless org && org.member?(customer) && header_org_accessible?(org, customer, domains)
          OT.ld "[OrganizationLoader] Header org invalid or unauthorized: #{org_id_header}"
          return
        end

        org
      end

      # Verify that the header-selected org is accessible given domain scope.
      # The header should select among accessible orgs, not bypass scoping.
      def header_org_accessible?(org, customer, domains)
        scope_permits?(org, customer, domains)
      end

      # Whether the customer's membership in `org` may be used on this
      # request: true when the request has no custom domain, otherwise only
      # when the membership can access every one of them
      # (OrganizationMembership#can_access_domain?). No membership is a
      # refusal.
      #
      # @param org [Onetime::Organization]
      # @param customer [Onetime::Customer]
      # @param domains [Array<Onetime::CustomDomain>] from #request_scope_domains
      # @return [Boolean]
      def scope_permits?(org, customer, domains)
        return true if domains.empty?

        membership = Onetime::OrganizationMembership.find_by_org_customer(org.objid, customer.objid)
        return false unless membership

        domains.all? { |domain| membership.can_access_domain?(domain) }
      end

      # Whether the domain scope withheld at least one of the customer's
      # organizations on this request. Always false with no custom domain.
      #
      # @param customer [Onetime::Customer]
      # @param domains [Array<Onetime::CustomDomain>] from #request_scope_domains
      # @return [Boolean]
      def scope_withheld_any?(customer, domains)
        return false if domains.empty?

        customer.organization_instances.to_a.any? { |o| !scope_permits?(o, customer, domains) }
      end

      # The custom domains this request is for, from both places one can be
      # named:
      #
      # - the Host header's record, unless the host is canonical. Other hosts
      #   are read even with the domains feature off; a failed read raises
      #   (see #request_host_domain).
      # - env['onetime.custom_domain'], the record DomainStrategy resolved
      #   for the display domain, when it classified the request :custom.
      #   Behind a proxy that rewrites Host to the origin target, with
      #   site.network.public_host_rewrite off, this is the only place the
      #   tenant domain appears.
      #
      # Usually zero or one record; two when the Host header and the display
      # domain name different custom domains.
      #
      # @param env [Hash, nil] Rack environment
      # @return [Array<Onetime::CustomDomain>]
      def request_scope_domains(env)
        return [] unless env

        domains   = []
        http_host = env['HTTP_HOST']
        if http_host
          domain = request_host_domain(env, http_host.split(':').first)
          domains << domain if domain
        end

        # The read DomainStrategy made for the display domain. When it
        # failed, the request classified :invalid and carries no record, so
        # raise here as the Host read does rather than check no scope at all.
        published = env[Onetime::CustomDomainResolution::ENV_KEY]
        published.record! if published.is_a?(Onetime::CustomDomainResolution)

        if env['onetime.domain_strategy'].to_s == 'custom'
          resolved = env['onetime.custom_domain']
          domains << resolved if resolved && domains.none? { |d| d.objid == resolved.objid }
        end

        domains
      end

      # CustomDomain for the raw Host header's host, or nil for a canonical host.
      #
      # Shares the request's resolution (#4220) when that host is the display
      # domain DomainStrategy resolved; any other non-canonical host is read
      # directly. A failed read raises here, as CustomDomain.from_display_domain did.
      def request_host_domain(env, host)
        return if Onetime::Utils::CanonicalHosts.canonical_host?(host)

        # Classify the raw host independently: the middleware's classification
        # describes the display domain, which may name another host behind a proxy.
        return if Onetime::Middleware::DomainStrategy::Chooserator.canonical_without_lookup?(
          host,
          Onetime::Utils::CanonicalHosts.hosts,
          anchor_domains: Onetime::Utils::CanonicalHosts.anchor_hosts,
        )

        Onetime::CustomDomainResolution.for_host(env, host).record!
      end
    end
  end
end
