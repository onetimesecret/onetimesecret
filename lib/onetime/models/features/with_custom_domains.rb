# lib/onetime/models/features/with_custom_domains.rb
#
# frozen_string_literal: true

module Onetime
  module Models
    module Features
      #
      #
      module WithCustomDomains

        Familia::Base.add_feature self, :with_custom_domains

        def self.included(base)
          OT.ld "[features] #{base}: #{name}"
          base.extend ClassMethods
          base.include InstanceMethods

          base.class_hashkey :domains
          base.sorted_set :custom_domains, suffix: 'custom_domain'
        end

        module ClassMethods
        end

        module InstanceMethods


          def custom_domains_list
            # Domains are now owned by organizations, not individual customers
            # Get domains from all organizations this customer belongs to
            organization_instances.flat_map do |org|
              org.list_domains
            rescue => ex
              OT.le "[custom_domains_list] Error loading domains for org #{org.orgid}: #{ex.message}"
              []
            end.compact.uniq
          end

          def add_custom_domain(obj)
            # Domains are now managed at the organization level
            # Add to the customer's primary organization
            org = organization_instances.first
            if org
              OT.ld "[add_custom_domain] adding #{obj} to organization #{org.orgid}"
              org.add_domain(obj)
            else
              OT.le "[add_custom_domain] Customer #{custid} has no organization"
              false
            end
          end

          def remove_custom_domain(obj)
            # Domains are now managed at the organization level
            # Remove from the customer's organization(s)
            organization_instances.each do |org|
              OT.ld "[remove_custom_domain] removing #{obj} from organization #{org.orgid}"
              org.remove_domain(obj)
            end
          end


        end

      end
    end
  end
end
