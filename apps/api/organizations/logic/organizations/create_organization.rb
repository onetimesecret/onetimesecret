# apps/api/organizations/logic/organizations/create_organization.rb

module OrganizationAPI::Logic
  module Organizations
    class CreateOrganization < OrganizationAPI::Logic::Base
      attr_reader :organization, :display_name, :description, :contact_email

      def process_params
        @display_name = params['display_name'].to_s.strip
        @description = params['description'].to_s.strip
        @contact_email = params['contact_email'].to_s.strip
      end

      def raise_concerns
        # Require authenticated user
        raise_form_error('Authentication required', field: 'user_id', error_type: :unauthorized) if cust.anonymous?

        # Validate display_name
        if display_name.empty?
          raise_form_error('Organization name is required', field: 'display_name', error_type: :missing)
        end

        if display_name.length < 1
          raise_form_error('Organization name must be at least 1 character', field: 'display_name', error_type: :invalid)
        end

        if display_name.length > 100
          raise_form_error('Organization name must be less than 100 characters', field: 'display_name', error_type: :invalid)
        end

        # Validate contact_email
        if contact_email.empty?
          raise_form_error('Contact email is required', field: 'contact_email', error_type: :missing)
        end

        # Check if contact_email already exists
        if Onetime::Organization.contact_email_exists?(contact_email)
          raise_form_error('An organization with this contact email already exists', field: 'contact_email', error_type: :exists)
        end

        # Description is optional but limit length if provided
        if !description.empty? && description.length > 500
          raise_form_error('Description must be less than 500 characters', field: 'description', error_type: :invalid)
        end
      end

      def process
        OT.ld "[CreateOrganization] Creating organization '#{display_name}' for user #{cust.custid}"

        # Create organization using class method
        @organization = Onetime::Organization.create!(display_name, cust, contact_email)

        # Set description if provided
        if !description.empty?
          @organization.description = description
          @organization.save
        end

        OT.info "[CreateOrganization] Created organization #{@organization.orgid}"

        success_data
      end

      def success_data
        {
          user_id: cust.objid,
          record: {
            orgid: organization.orgid,
            display_name: organization.display_name,
            description: organization.description || '',
            owner_id: organization.owner_id,
            contact_email: organization.contact_email,
            member_count: organization.member_count,
            created_at: organization.created,
            updated_at: organization.updated,
            current_user_role: 'owner',
          },
        }
      end

      def form_fields
        {
          display_name: display_name,
          description: description,
          contact_email: contact_email,
        }
      end
    end
  end
end
