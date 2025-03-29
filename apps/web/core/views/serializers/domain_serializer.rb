# apps/web/core/views/serializers/domain_serializer.rb

module Core
  module Views
    module DomainSerializer
      # - canonical_domain, domain_strategy, domain_id, display_domain, domain_branding, domain_logo
      # - custom_domains, domains_enabled
      def self.serialize(vars, i18n)
        self[:jsvars][:domains_enabled] = jsvar(domains_enabled) # only for authenticated

        self[:jsvars][:canonical_domain] = jsvar(canonical_domain)
        self[:jsvars][:domain_strategy] = jsvar(domain_strategy)
        self[:jsvars][:domain_id] = jsvar(domain_id)
        self[:jsvars][:domain_branding] = jsvar(domain_branding)
        self[:jsvars][:domain_logo] = jsvar(domain_logo)
        self[:jsvars][:display_domain] = jsvar(display_domain)
      end

      private

      def self.output_template
        {}
      end

    end
  end
end
