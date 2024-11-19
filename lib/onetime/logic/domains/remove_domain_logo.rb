require_relative '../base'
require_relative '../../cluster'

module Onetime::Logic
  module Domains
    class RemoveDomainLogo < OT::Logic::Base
      attr_reader :greenlighted, :display_domain, :custom_domain

      def process_params
        @domain_id = params['domain'].to_s.strip
      end

      def raise_concerns
        OT.ld "[RemoveDomainLogo] Raising concerns for domain_id: #{@domain_id}"
        limit_action :remove_domain_logo

        raise_form_error "Domain ID is required" if @domain_id.empty?

        @custom_domain = OT::CustomDomain.load(@domain_id, @cust.custid)
        raise_form_error "Invalid domain ID" unless @custom_domain

        raise_form_error "No logo exists for this domain" unless logo_exists?
      end

      def process
        @greenlighted = true
        remove_logo
        @custom_domain.save
      end

      def success_data
        OT.ld "[RemoveDomainLogo] Preparing success data for domain_id: #{@domain_id}"
        {
          record: @custom_domain.safe_dump,
          details: {
            msg: "Logo removed successfully for #{@custom_domain.display_domain}"
          }
        }
      end

      private

      def logo_exists?
        @custom_domain.brand&.key?('image_encoded')
      end

      def remove_logo
        @custom_domain.brand&.remove('image_encoded')
        @custom_domain.brand&.remove('image_filename')
        @custom_domain.brand&.remove('image_content_type')
      end
    end
  end
end
