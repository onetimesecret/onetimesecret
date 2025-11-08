# apps/api/organizations/logic/organizations/update_organization.rb

module OrganizationAPI::Logic
  module Organizations
    class UpdateOrganization < OrganizationAPI::Logic::Base
      attr_reader :organization, :display_name, :description, :contact_email

      def process_params
        @orgid = params['orgid']
        @display_name = (params[:display_name] || params['display_name']).to_s.strip
        @description = (params[:description] || params['description']).to_s.strip
        @contact_email = (params[:contact_email] || params['contact_email']).to_s.strip
      end

      def raise_concerns
        # Require authenticated user
        raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?

        # Validate orgid parameter
        raise_form_error('Organization ID required', field: :orgid, error_type: :missing) if @orgid.to_s.empty?

        # Load organization
        @organization = load_organization(@orgid)

        # Verify user is owner
        verify_organization_owner(@organization)

        # Validate display_name if provided
        if !display_name.empty?
          if display_name.length < 1
            raise_form_error('Organization name must be at least 1 character', field: :display_name, error_type: :invalid)
          end

          if display_name.length > 100
            raise_form_error('Organization name must be less than 100 characters', field: :display_name, error_type: :invalid)
          end
        end

        # Validate description if provided
        if !description.empty? && description.length > 500
          raise_form_error('Description must be less than 500 characters', field: :description, error_type: :invalid)
        end

        # Validate contact_email if provided
        if !contact_email.empty?
          # Check if another organization already has this contact email
          if Onetime::Organization.contact_email_exists?(contact_email)
            existing_org = Onetime::Organization.values.members.find do |orgid|
              org = Onetime::Organization.load(orgid)
              org && org.contact_email == contact_email && org.orgid != @orgid
            end

            if existing_org
              raise_form_error('An organization with this contact email already exists', field: :contact_email, error_type: :exists)
            end
          end
        end

        # At least one field must be provided
        if display_name.empty? && description.empty? && contact_email.empty?
          raise_form_error('At least one field (display_name, description, or contact_email) must be provided', field: :display_name, error_type: :missing)
        end
      end

      def process
        OT.ld "[UpdateOrganization] Updating organization #{@orgid} for user #{cust.custid}"

        # Update fields
        if !display_name.empty?
          @organization.display_name = display_name
        end

        if !description.empty?
          @organization.description = description
        end

        if !contact_email.empty?
          @organization.contact_email = contact_email
        end

        # Update timestamp and save
        @organization.updated = Familia.now.to_i
        @organization.save

        OT.info "[UpdateOrganization] Updated organization #{@orgid}"

        success_data
      end

      def success_data
        {
          user_id: cust.objid,
          record: {
            orgid: organization.orgid,
            display_name: organization.display_name,
            description: organization.description,
            contact_email: organization.contact_email,
            owner_id: organization.owner_id,
            is_owner: true,
            member_count: organization.member_count,
            created: organization.created,
            updated: organization.updated,
          },
        }
      end

      def form_fields
        {
          orgid: @orgid,
          display_name: display_name,
          description: description,
          contact_email: contact_email,
        }
      end
    end
  end
end
