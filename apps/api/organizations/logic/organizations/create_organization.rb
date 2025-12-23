# apps/api/organizations/logic/organizations/create_organization.rb
#
# frozen_string_literal: true

module OrganizationAPI::Logic
  module Organizations
    class CreateOrganization < OrganizationAPI::Logic::Base
      attr_reader :organization, :display_name, :description, :contact_email

      def process_params
        @display_name  = params['display_name'].to_s.strip
        @description   = params['description'].to_s.strip
        @contact_email = params['contact_email'].to_s.strip
      end

      def raise_concerns
        # Require authenticated user
        raise_form_error('Authentication required', field: 'user_id', error_type: :unauthorized) if cust.anonymous?

        # Check organization quota (only enforced when billing enabled with plan cache)
        check_organization_quota!

        # Validate display_name
        if display_name.empty?
          raise_form_error('Organization name is required', field: 'display_name', error_type: :missing)
        end

        if display_name.empty?
          raise_form_error('Organization name must be at least 1 character', field: 'display_name', error_type: :invalid)
        end

        if display_name.length > 100
          raise_form_error('Organization name must be less than 100 characters', field: 'display_name', error_type: :invalid)
        end

        # Validate contact_email (optional, but must be unique if provided)
        if !contact_email.empty? && Onetime::Organization.contact_email_exists?(contact_email)
          raise_form_error('An organization with this contact email already exists', field: 'contact_email', error_type: :exists)
        end

        # Description is optional but limit length if provided
        if !description.empty? && description.length > 500
          raise_form_error('Description must be less than 500 characters', field: 'description', error_type: :invalid)
        end
      end

      def process
        OT.ld "[CreateOrganization] Creating organization '#{display_name}' for user #{cust.custid}"

        # Create organization using class method (contact_email is optional)
        email_value   = contact_email.empty? ? nil : contact_email
        @organization = Onetime::Organization.create!(display_name, cust, email_value)

        # Set description if provided
        unless description.empty?
          @organization.description = description
          @organization.save
        end

        OT.info "[CreateOrganization] Created organization #{@organization.objid}"

        success_data
      end

      def success_data
        {
          user_id: cust.objid,
          record: serialize_organization(organization),
        }
      end

      def form_fields
        {
          display_name: display_name,
          description: description,
          contact_email: contact_email,
        }
      end

      private

      # Check organization quota against customer's plan limits
      #
      # Uses customer's primary organization plan for billing context.
      # Only enforced when billing is enabled and plan cache is populated.
      # Skipped for first organization creation (no primary org to check against).
      def check_organization_quota!
        # Quota enforcement: fail-open when no billing, fail-closed when enabled.
        # See WithEntitlements module for design rationale.

        primary_org = cust.organization_instances.to_a.find { |o| o.is_default } || cust.organization_instances.first

        # Fail-open conditions: skip quota check
        return unless primary_org
        return unless primary_org.respond_to?(:at_limit?)
        return unless primary_org.entitlements.any?

        # Fail-closed: billing enabled, enforce quota
        current_count = cust.organization_instances.size

        if primary_org.at_limit?('organizations', current_count)
          raise_form_error(
            'Organization limit reached. Upgrade your plan to create more organizations.',
            field: 'display_name',
            error_type: :upgrade_required
          )
        end
      end
    end
  end
end
