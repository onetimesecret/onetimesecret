# apps/api/colonel/logic/colonel/list_custom_domains.rb
#
# frozen_string_literal: true

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      class ListCustomDomains < ColonelAPI::Logic::Base
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

          # Format domain data
          @domains = paginated_domains.map do |domain|
            # Get organization details
            org = domain.primary_organization

            # Get brand details from the hashkey
            brand_data = {
              name: domain.brand['name'],
              tagline: domain.brand['tagline'],
              homepage_url: domain.brand['homepage_url'],
              allow_public_homepage: domain.allow_public_homepage?,
              allow_public_api: domain.allow_public_api?,
            }

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
              org_name: org ? org.name : 'Unknown',
              brand: brand_data,
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
