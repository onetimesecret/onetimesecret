# apps/api/v2/models/features/with_custom_domains.rb

module V2
  module Models
    module Features
      #
      #
      module WithCustomDomains

        Familia::Base.add_feature self, :with_custom_domains

        def self.included(base)
          OT.ld "[#{name}] Included in #{base}"
          base.extend ClassMethods
          base.include InstanceMethods

          base.class_hashkey :domains, dbkey: 'onetime:customers:domain'
          base.sorted_set :custom_domains, suffix: 'custom_domain'
        end

        module ClassMethods
        end

        module InstanceMethods


          def custom_domains_list
            custom_domains.revmembers.collect do |domain|
              V2::CustomDomain.load domain, custid
            rescue Onetime::RecordNotFound => ex
              OT.le "[custom_domains_list] Error: #{ex.message} (#{domain} / #{custid})"
            end.compact
          end

          def add_custom_domain(obj)
            OT.ld "[add_custom_domain] adding #{obj} to #{self}"
            custom_domains.add obj.display_domain # not the object identifier
          end

          def remove_custom_domain(obj)
            custom_domains.remove obj.display_domain # not the object identifier
          end


        end

      end
    end
  end
end
