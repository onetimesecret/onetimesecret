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
# 3. Customer's default_org_id (per-customer preference: set by the customer
#    via POST /api/account/update-default-organization, or by support)
# 4. Organization with is_default flag that the customer OWNS (their personal
#    workspace; another member's default workspace carries the flag too)
# Steps 3-4 are #default_organization, which the API payloads use too.
# Operations that act on the workspace the customer OWNS (SSO self-heal,
# federation claim, pro-bono grant, organization quota) use
# #owned_default_organization instead; it never follows a preference or a
# flag to another member's workspace.
# 5. First available organization
# 6. Return nil (lazy creation happens later in auth_org)
#
# Domain scope:
# Every selection above (header, session, domain, fallbacks) is subject to
# the membership's domain scope when the request has a custom domain. See
# #scope_permits? for where the request's domains come from.
# On an unregistered host, a display domain that was read and has no
# record, every organization is withheld (#4225), and so is the default
# workspace auth_org would otherwise create for a customer who has none.
# When the scope leaves no organization, the context carries
# domain_scope_refused: true and auth_org does not select one either.
#
# Explicit selection (#4565):
# session['organization_id'] is the server's record of the workspace the
# user picked. It is written only by #select_organization (reached through
# POST /api/account/update-organization-context), which applies the same
# membership, archived and domain-scope checks as the header. Page loads
# carry no O-Organization-ID header, so this value is what keeps the
# selection across a full reload. It is re-checked on every request and
# cleared once the membership is gone or the organization is archived.
# session['organization_selected_at'] is written with it: when the user made
# the selection (epoch milliseconds, server clock). The endpoint uses it to
# refuse a selection sent again after a page load once the session holds a
# different one made since.
#
# No caching:
# Every call resolves from the datastore. There is no session cache of the
# result: membership, archived state and domain scope are read each time,
# including on the second load a request makes (Sessions::TrackMetadata at
# session commit). An 'org_context:<customer objid>' key in an older
# session blob is a leftover from the removed cache and is not read.
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
      # So the selection methods can be called without mixing the loader in
      # (RequestHelpers#switch_organization, the Account API logic class).
      extend self

      # What #request_scope_domains answers on an unregistered host: the
      # display domain was read and has no record (#4225). The nil element
      # reaches OrganizationMembership#can_access_domain?, which refuses a
      # nil domain, so #scope_permits? refuses every membership, org-scoped
      # ones included, and #scope_withheld_any? reports the refusal for
      # every customer, one with no organization yet included.
      UNREGISTERED_HOST = [nil].freeze

      # Load organization context for authenticated customer
      #
      # @param customer [Onetime::Customer] Authenticated customer
      # @param session [Hash] Rack session
      # @param env [Hash] Rack environment
      # @return [Hash] Context hash with organization data. :scope_domains is
      #   the request's custom domains (see #request_scope_domains), kept so a
      #   selection made later in the request is checked against the same scope.
      def load_organization_context(customer, session, env)
        return {} if customer.nil? || customer&.anonymous?

        # Resolve the request's scope before any selection.
        # Canonical hosts need no lookup; a failed custom-domain read raises here.
        domains = request_scope_domains(env)

        # The header decides first (SPA XHRs), then the session selection and
        # the fallbacks (read-only - no writes during auth phase).
        org = resolve_header_org(customer, env, domains)
        if org
          OT.ld "[OrganizationLoader] Using header override: #{org.objid}"
        else
          org = determine_organization(customer, session, env, domains)
        end

        OT.ld "[OrganizationLoader] Loaded context for #{customer.objid}: org=#{org&.objid}"

        context = {
          organization: org,
          organization_id: org&.objid,
          scope_domains: domains,
        }

        # No organization because the domain scope withheld one is a refusal,
        # not the "no workspace yet" case. Logic::OrganizationContext#auth_org
        # reads this and returns nil instead of falling back to the customer's
        # first organization.
        context[:domain_scope_refused] = true if org.nil? && scope_withheld_any?(customer, domains)

        context
      end

      # The organization `org_id` names, when the customer may select it on
      # this request: a member, not archived, and permitted by the membership's
      # domain scope. The same checks the O-Organization-ID header gets.
      #
      # @param customer [Onetime::Customer] Authenticated customer
      # @param org_id [String] Organization objid
      # @param context [Hash, nil] the context #load_organization_context
      #   returned for this request. Without its :scope_domains the scope cannot
      #   be checked and nothing is selectable.
      # @return [Onetime::Organization, nil]
      def selectable_organization(customer, org_id, context)
        domains = context[:scope_domains] if context.is_a?(Hash)
        return unless customer && !customer.anonymous? && domains.is_a?(Array)

        permitted_organization(customer, org_id, domains)
      end

      # Record an explicit organization selection in the session, after the
      # checks in #selectable_organization. Takes effect on the next request;
      # the session is left as it was when the selection is refused.
      #
      # @param customer [Onetime::Customer] Authenticated customer
      # @param session [Hash] Rack session
      # @param org_id [String] Organization objid
      # @param context [Hash, nil] see #selectable_organization
      # @param at [Integer, nil] when the user made the selection, in epoch
      #   milliseconds on the server clock. Now, unless the caller knows it
      #   was made earlier.
      # @return [Onetime::Organization, nil] the selected organization, or nil
      #   when refused
      def select_organization(customer, session, org_id, context, at: nil)
        return unless session

        org = selectable_organization(customer, org_id, context)
        return unless org

        session['organization_id']          = org.objid
        session['organization_selected_at'] = at || (Familia.now * 1000).to_i
        OT.ld "[OrganizationLoader] Recorded explicit selection for #{customer.objid}: #{org.objid}"
        org
      end

      # This customer's default organization: the one the loader falls back
      # to (steps 3 and 4) when no header, session selection or custom domain
      # chooses another. Organization#is_default marks the organization its
      # OWNER's auto-created workspace, so another member's default workspace
      # carries the flag too; only one the customer owns counts here.
      #
      # 1. The non-archived organization in `orgs` named by
      #    customer.default_org_id.
      # 2. Else the first non-archived organization in `orgs` with is_default
      #    that the customer owns.
      #
      # @param customer [Onetime::Customer]
      # @param orgs [Array<Onetime::Organization>, nil] the organizations to
      #   choose among. The customer's memberships when nil; the loader passes
      #   them already filtered by the request's domain scope.
      # @return [Onetime::Organization, nil]
      def default_organization(customer, orgs = nil)
        return if customer.nil? || customer.anonymous?

        orgs ||= customer.organization_instances.to_a
        return if orgs.empty?

        default_org_id = customer.default_org_id.to_s
        unless default_org_id.empty?
          chosen = orgs.find { |o| o.objid == default_org_id && !o.archived? }
          return chosen if chosen
        end

        # owner? reads the membership, so it is checked last.
        orgs.find { |o| o.is_default && !o.archived? && o.owner?(customer) }
      end

      # The default workspace this customer OWNS. #default_organization
      # answers "where does this user land": its explicit step honours a
      # default_org_id that names an organization the user merely belongs to.
      # Operations that write to, bill, or draw entitlements from "the
      # customer's workspace" need the one the customer owns instead: the
      # SSO self-heal archives it, the deferred federation claim and the
      # pro-bono grant change its plan, checkout binds its Stripe customer,
      # and organization creation is funded by it. Another member's default
      # workspace carries the is_default flag too and is never eligible here,
      # whatever order the memberships are listed in.
      #
      # 1. The non-archived organization in `orgs` named by
      #    customer.default_org_id, when the customer owns it. The preference
      #    is honoured only within the customer's own workspaces; one that
      #    names a joined organization is ignored rather than followed.
      # 2. Else the first non-archived organization in `orgs` with is_default
      #    that the customer owns.
      #
      # @param customer [Onetime::Customer]
      # @param orgs [Array<Onetime::Organization>, nil] see #default_organization
      # @return [Onetime::Organization, nil]
      def owned_default_organization(customer, orgs = nil)
        return if customer.nil? || customer.anonymous?

        orgs ||= customer.organization_instances.to_a
        live   = orgs.reject(&:archived?)
        return if live.empty?

        default_org_id = customer.default_org_id.to_s
        unless default_org_id.empty?
          chosen = live.find { |o| o.objid == default_org_id }
          return chosen if chosen&.owner?(customer)
        end

        live.find { |o| o.is_default && o.owner?(customer) }
      end

      # The non-archived organizations the customer owns, in membership
      # order. One membership read per live organization.
      #
      # @param customer [Onetime::Customer]
      # @param orgs [Array<Onetime::Organization>, nil] see #default_organization
      # @return [Array<Onetime::Organization>]
      def owned_organizations(customer, orgs = nil)
        return [] if customer.nil? || customer.anonymous?

        orgs ||= customer.organization_instances.to_a
        orgs.reject(&:archived?).select { |o| o.owner?(customer) }
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
        # first. If we reach here, no valid header was present.

        # 1. Explicit selection from session
        if session && session['organization_id']
          org = Onetime::Organization.load(session['organization_id'])
          if org && org.member?(customer) && !org.archived?
            if scope_permits?(org, customer, domains)
              OT.ld "[OrganizationLoader] Using explicit selection: #{org.objid}"
              return org
            end
            # A member, but not on this request's domain. The selection is
            # kept (it is valid on the domain the membership is scoped to)
            # and the steps below choose among what the scope permits.
            OT.ld "[OrganizationLoader] Explicit selection outside the member's domain scope: #{org.objid}"
          else
            # Clear a selection that no longer holds: the organization is
            # gone or archived, or the membership was removed.
            session.delete('organization_id')
            session.delete('organization_selected_at')
          end
        end

        # 2. Domain-based selection. Which organization a request is GIVEN is
        # keyed on the Host header's record only, as before; whether it may
        # be given is decided over all of the request's domains.
        #
        # An archived organization can still own the domain
        # (Organization#archive! leaves domains attached), so it is skipped
        # here as in every other step and the steps below choose instead.
        if env && env['HTTP_HOST']
          host   = env['HTTP_HOST'].split(':').first # Remove port
          domain = request_host_domain(env, host)
          if domain
            org = domain.primary_organization
            if org && org.member?(customer) && !org.archived?
              if scope_permits?(org, customer, domains)
                OT.ld "[OrganizationLoader] Using domain-based selection: #{org.objid} (#{host})"
                return org
              end
              OT.ld "[OrganizationLoader] Domain-scoped member cannot access #{host}: #{customer.objid}"
            end
          end
        end

        # 3-4. The customer's default organization (#default_organization):
        # customer.default_org_id (set by the customer, support, or the SSO
        # self-heal), else the is_default workspace the customer owns.
        # Archived organizations are skipped; a default workspace that was
        # archived has been superseded by a domain org.
        #
        # Steps 3-5 choose only among organizations the membership's domain
        # scope permits for this request, so an organization refused above
        # cannot come back through a different selection path. With no
        # custom domain on the request nothing is filtered and no membership
        # is read.
        orgs = customer.organization_instances.to_a
        orgs = orgs.select { |o| scope_permits?(o, customer, domains) } unless domains.empty?

        default_org    = default_organization(customer, orgs)
        default_org_id = customer.default_org_id.to_s

        if !default_org_id.empty? && default_org&.objid != default_org_id
          # Customer's default_org_id references an org they're not a member of,
          # or the org is archived. Fall through to other selection methods.
          OT.ld "[OrganizationLoader] Customer default_org_id archived/invalid/not member: #{default_org_id}"
        end

        if default_org
          if default_org.objid == default_org_id
            OT.ld "[OrganizationLoader] Using customer's default_org_id: #{default_org.objid}"
          else
            OT.ld "[OrganizationLoader] Using organization is_default flag: #{default_org.objid}"
          end
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

      # Resolve org from O-Organization-ID header, verifying membership,
      # archived state and domain scope. Returns nil if header absent,
      # invalid, or denied.
      def resolve_header_org(customer, env, domains)
        org_id_header = env&.dig('HTTP_O_ORGANIZATION_ID')
        return unless org_id_header.is_a?(String) && !org_id_header.empty?

        org = permitted_organization(customer, org_id_header, domains)
        OT.ld "[OrganizationLoader] Header org invalid or unauthorized: #{org_id_header}" unless org
        org
      end

      # The organization with objid `org_id` when the customer is a member, it
      # is not archived, and the domain scope permits it. A header or an
      # explicit selection chooses among accessible organizations; it does not
      # bypass scoping.
      def permitted_organization(customer, org_id, domains)
        return unless org_id.is_a?(String) && !org_id.empty?

        org = Onetime::Organization.load(org_id)
        return unless org && org.member?(customer) && !org.archived?
        return unless scope_permits?(org, customer, domains)

        org
      end

      # Whether the customer's membership in `org` may be used on this
      # request: true when the request has no custom domain, otherwise only
      # when the membership can access every one of them
      # (OrganizationMembership#can_access_domain?). No membership is a
      # refusal, and so is an unregistered host (UNREGISTERED_HOST): its nil
      # domain is one no membership can access.
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
      # Always true on an unregistered host (UNREGISTERED_HOST), whether or
      # not the customer has an organization yet: the refusal has to reach
      # Logic::OrganizationContext#auth_org for a customer with none too,
      # or it would create their default workspace on a host the install
      # does not serve.
      #
      # @param customer [Onetime::Customer]
      # @param domains [Array<Onetime::CustomDomain>] from #request_scope_domains
      # @return [Boolean]
      def scope_withheld_any?(customer, domains)
        return false if domains.empty?
        return true if domains.equal?(UNREGISTERED_HOST)

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
      # domain name different custom domains. UNREGISTERED_HOST when the
      # display domain was read and has no record (#4225), whatever the Host
      # header names.
      #
      # @param env [Hash, nil] Rack environment
      # @return [Array<Onetime::CustomDomain>] the request's custom domains,
      #   or UNREGISTERED_HOST
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
        published = env[Onetime::CustomDomain::Lookup::ENV_KEY]
        published.record! if published.is_a?(Onetime::CustomDomain::Lookup)

        # When that read found no record, the request is on a host the
        # deployment does not serve. Behind a proxy that rewrites Host to
        # the origin target the Host read found nothing either, and an empty
        # scope would admit every organization, as on a canonical host.
        if unregistered_display_host?(env, published)
          OT.ld "[OrganizationLoader] Unregistered host #{published.host}: withholding every organization"
          return UNREGISTERED_HOST
        end

        # Nothing published for an :invalid request: detection rejected the
        # host (an IP literal, `localhost`, a malformed or missing Host), so
        # no display domain was read. Decided on #4678 and recorded in
        # ADR-050, "Organization scope on a host that detection rejects":
        # when Host names no custom domain either, the request is scoped as
        # one for the canonical host. The Host read above does not depend on
        # detection. A trusted X-Forwarded-Host with userinfo in it stops
        # detection without trying Host (Rack::DetectHost, "Userinfo in an
        # authority"), and a Host that names a custom domain then carries
        # that record's scope, as it does with the domains feature off.
        strategy = env['onetime.domain_strategy'].to_s
        if strategy == 'invalid' && !published.is_a?(Onetime::CustomDomain::Lookup) && domains.empty?
          OT.ld "[OrganizationLoader] No custom domain for #{env['onetime.display_domain']} or Host: " \
                'no scope withheld (#4678)'
        end

        if strategy == 'custom'
          resolved = env['onetime.custom_domain']
          domains << resolved if resolved && domains.none? { |d| d.objid == resolved.objid }
        end

        domains
      end

      # CustomDomain for the raw Host header's host, or nil for a canonical host.
      #
      # Shares the request's lookup (#4220) when that host is the display
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

        Onetime::CustomDomain::Lookup.for_host(env, host).record!
      end

      # Whether the request's display domain was read and has no record:
      # DomainStrategy classified it :invalid and published an absent
      # lookup for it. An :invalid request with no lookup published is not
      # one: the host could not be detected or parsed, so nothing was read.
      # Nor is a failed read, which #request_scope_domains raises on first.
      #
      # @param env [Hash] Rack environment
      # @param published [Onetime::CustomDomain::Lookup, nil] the value under
      #   Onetime::CustomDomain::Lookup::ENV_KEY
      # @return [Boolean]
      def unregistered_display_host?(env, published)
        return false unless env['onetime.domain_strategy'].to_s == 'invalid'
        return false unless published.is_a?(Onetime::CustomDomain::Lookup) && published.absent?

        published.host == env['onetime.display_domain'].to_s
      end
    end
  end
end
