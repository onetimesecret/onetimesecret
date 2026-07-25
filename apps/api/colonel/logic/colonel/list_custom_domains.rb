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
      #
      # Optional server-side filters (all additive; omitting them reproduces the
      # previous unfiltered behaviour byte-for-byte):
      #
      #   search  — case-insensitive substring over display_domain / base_domain,
      #             or an exact extid / domain_id match.
      #   status  — exact verification_state ('verified', 'pending', ...).
      #   org_id  — exact owning-org match; accepts the org extid or objid.
      #
      # Scaling note: this endpoint loads every CustomDomain before slicing (the
      # incumbent behaviour). Filtering happens in the same in-memory pass, so it
      # does not make the read heavier — but a genuinely index-backed page read
      # is still the right fix if the domain population grows. Filters are
      # applied BEFORE pagination, so total_count reflects the filtered set.
      class ListCustomDomains < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'customDomains' }.freeze

        attr_reader :domains,
          :total_count,
          :page,
          :per_page,
          :total_pages,
          :search_term,
          :status_filter,
          :org_filter

        def process_params
          @page     = (params['page'] || 1).to_i
          @per_page = (params['per_page'] || 50).to_i
          @per_page = 100 if @per_page > 100 # Max 100 per page
          @page     = 1 if @page < 1

          @search_term   = sanitize_plain_text(params['search'], max_length: 255).to_s.strip
          @status_filter = sanitize_identifier(params['status']).to_s
          @org_filter    = sanitize_identifier(params['org_id']).to_s
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          # Get all custom domains using efficient loading
          all_domain_ids = Onetime::CustomDomain.instances.to_a
          all_domains    = Onetime::CustomDomain.load_multi(all_domain_ids).compact
          all_domains    = apply_filters(all_domains)

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
          # Consistent with CustomDomain's predicates (`#allow_public_homepage?`
          # / `#allow_public_api?`), which also fail-closed (return false +
          # log) when a sibling record is missing. Both read paths prefer
          # graceful degradation over raising so a single corrupt row can't
          # take down the admin list OR the user-facing authorization flow;
          # the write path (create! bootstrap, brand PUT upsert, migration)
          # is where integrity is enforced.
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
                secrets_mode: homepage_config.secrets_mode_value,
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
              # Server echo of the applied filters (additive key; mirrors
              # ListOrganizations). Never read for state by the frontend.
              filters: {
                search: search_term,
                status: status_filter,
                org_id: org_filter,
              },
            },
          }
        end

        private

        # All three filters are AND-ed. Empty/absent filters are no-ops, so an
        # unfiltered request returns exactly the previous result set.
        def apply_filters(all_domains)
          result = all_domains

          unless status_filter.empty?
            result = result.select { |d| d.verification_state.to_s == status_filter }
          end

          unless org_filter.empty?
            # Accept the org extid (what every admin surface routes by) or the
            # internal objid, which is what CustomDomain#org_id actually stores.
            org     = Onetime::Organization.find_by_extid(org_filter)
            org_ids = [org_filter, org&.objid].compact.map(&:to_s)
            result  = result.select { |d| org_ids.include?(d.org_id.to_s) }
          end

          return result if search_term.empty?

          needle = search_term.downcase
          result.select do |d|
            next true if d.extid.to_s == search_term
            next true if d.domainid.to_s == search_term

            d.display_domain.to_s.downcase.include?(needle) ||
              d.base_domain.to_s.downcase.include?(needle)
          end
        end
      end
    end
  end
end
