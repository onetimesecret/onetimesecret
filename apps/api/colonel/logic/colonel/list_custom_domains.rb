# apps/api/colonel/logic/colonel/list_custom_domains.rb
#
# frozen_string_literal: true

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      # List Custom Domains (Colonel)
      #
      # @api Returns a paginated list of all custom domains across all
      #   organizations, including verification state, brand settings,
      #   logo/icon presence, and the owning organization. Requires
      #   colonel role.
      class ListCustomDomains < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'customDomains' }.freeze

        attr_reader :domains, :total_count, :page, :per_page, :total_pages

        def process_params
          @page     = (params['page'] || 1).to_i
          @per_page = (params['per_page'] || 50).to_i
          @per_page = 100 if @per_page > 100 # Max 100 per page
          @page     = 1 if @page < 1
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          # Get all custom domains using efficient loading
          all_domain_ids = Onetime::CustomDomain.instances.to_a
          all_domains    = Onetime::CustomDomain.load_multi(all_domain_ids).compact

          @total_count = all_domains.size
          @total_pages = (@total_count.to_f / @per_page).ceil

          # Sort by created timestamp (most recent first)
          all_domains.sort_by! { |domain| -(domain.created || 0) }

          # Paginate
          start_idx         = (@page - 1) * @per_page
          end_idx           = start_idx + @per_page - 1
          paginated_domains = all_domains[start_idx..end_idx] || []

          # Batch-load sibling configs for the page in two pipelined fetches.
          # HomepageConfig / ApiConfig use `identifier_field :domain_id`, so the
          # CustomDomain identifiers serve directly as load_multi keys. Missing
          # records come back as nil and are dropped by compact; lookup-misses
          # in the loop below become nil blocks in the JSON response.
          #
          # NOTE: deliberate inconsistency with CustomDomain's predicates
          # (`#allow_public_homepage?` / `#allow_public_api?`) which RAISE on
          # a missing record. Different error policies for the same underlying
          # condition is a calculated trade-off: user-facing paths fail loudly
          # so corruption is impossible to ignore; this admin diagnostic view
          # degrades gracefully so the operator can actually SEE which domains
          # are broken. If you change one policy, update the comment above
          # `#allow_public_homepage?` in lib/onetime/models/custom_domain.rb
          # to match.
          domain_identifiers = paginated_domains.map(&:identifier)
          homepage_by_id     = Onetime::CustomDomain::HomepageConfig
            .load_multi(domain_identifiers).compact
            .each_with_object({}) { |cfg, h| h[cfg.domain_id] = cfg }
          api_by_id          = Onetime::CustomDomain::ApiConfig
            .load_multi(domain_identifiers).compact
            .each_with_object({}) { |cfg, h| h[cfg.domain_id] = cfg }

          # Format domain data
          @domains = paginated_domains.map do |domain|
            # Get organization details
            org = domain.primary_organization

            # Brand carries cosmetic fields only; the homepage / API toggles
            # live in their own per-domain records (#3026) and are emitted
            # alongside brand below.
            brand_raw  = domain.brand.hgetall
            brand_data = {
              name: brand_raw['name'],
              tagline: brand_raw['tagline'],
              homepage_url: brand_raw['homepage_url'],
            }

            homepage_config = homepage_by_id[domain.identifier]
            api_config      = api_by_id[domain.identifier]

            # Check if images exist
            has_logo = !domain.logo['filename'].to_s.empty?
            has_icon = !domain.icon['filename'].to_s.empty?

            {
              domain_id: domain.domainid,
              extid: domain.extid,
              display_domain: domain.display_domain,
              base_domain: domain.base_domain,
              subdomain: domain.subdomain,
              status: domain.status,
              verified: domain.verified.to_s == 'true',
              resolving: domain.resolving.to_s == 'true',
              verification_state: domain.verification_state.to_s,
              ready: domain.ready?,
              created: domain.created,
              updated: domain.updated,
              org_id: domain.org_id,
              org_name: org ? org.display_name : 'Unknown',
              brand: brand_data,
              homepage_config: homepage_config && {
                domain_id: homepage_config.domain_id,
                enabled: homepage_config.enabled?,
                created_at: homepage_config.created&.to_i,
                updated_at: homepage_config.updated&.to_i,
              },
              api_config: api_config && {
                domain_id: api_config.domain_id,
                enabled: api_config.enabled?,
                created_at: api_config.created&.to_i,
                updated_at: api_config.updated&.to_i,
              },
              has_logo: has_logo,
              has_icon: has_icon,
              logo_url: has_logo ? "/imagine/#{domain.domainid}/logo.png" : nil,
              icon_url: has_icon ? "/imagine/#{domain.domainid}/icon.png" : nil,
            }
          end

          success_data
        end

        def success_data
          {
            record: {},
            details: {
              domains: domains,
              pagination: {
                page: page,
                per_page: per_page,
                total_count: total_count,
                total_pages: total_pages,
              },
            },
          }
        end
      end
    end
  end
end
