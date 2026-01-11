# apps/api/organizations/logic/organizations/update_organization.rb
#
# frozen_string_literal: true

require 'stripe'

module OrganizationAPI::Logic
  module Organizations
    # UpdateOrganization - Update organization settings including billing email
    #
    # When billing_email is updated and the organization has a linked Stripe
    # customer, this also updates the email in Stripe to keep them in sync.
    #
    # ## Stripe Customer Email Sync
    #
    # The billing email on the Stripe Customer is independent of the account
    # email. This allows customers to:
    # - Use a different email for billing (e.g., accounts@company.com)
    # - Update billing email via Customer Portal (Stripe -> OTS sync via webhook)
    # - Update billing email via OTS settings (OTS -> Stripe sync here)
    #
    # ## Important: Two-Way Sync
    #
    # - OTS -> Stripe: This logic class (on settings save)
    # - Stripe -> OTS: CustomerUpdated webhook handler (on portal changes)
    #
    class UpdateOrganization < OrganizationAPI::Logic::Base
      attr_reader :organization, :display_name, :description, :billing_email, :extid

      def process_params
        @extid         = sanitize_identifier(params['extid'])
        @display_name  = sanitize_plain_text(params['display_name'])
        @description   = sanitize_plain_text(params['description'])
        # Support both field names for backwards compatibility
        @billing_email = sanitize_email(params['billing_email'] || params['contact_email'])
      end

      def raise_concerns
        # Require authenticated user
        raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?

        # Validate extid parameter
        raise_form_error('Organization ID required', field: :extid, error_type: :missing) if @extid.to_s.empty?

        # Load organization
        @organization = load_organization(@extid)

        # Verify user is owner
        verify_organization_owner(@organization)

        # Validate display_name if provided
        unless display_name.empty?
          if display_name.empty?
            raise_form_error('Organization name must be at least 1 character', field: :display_name, error_type: :invalid)
          end

          if display_name.length > 100
            raise_form_error('Organization name must be less than 100 characters', field: :display_name, error_type: :invalid)
          end
        end

        # Validate description if provided
        if description.to_s.length > 500
          raise_form_error('Description must be less than 500 characters', field: :description, error_type: :invalid)
        end

        # Use unique_index finder for O(1) lookup (no iteration)
        existing_org  = Onetime::Organization.find_by_extid(extid)
        @organization = existing_org if existing_org
      end

      def process
        OT.ld "[UpdateOrganization] Updating organization #{@extid} for user #{cust.custid}"

        # Track if billing email changed for Stripe sync
        billing_email_changed = false
        old_billing_email     = @organization.billing_email

        # Update fields
        unless display_name.empty?
          @organization.display_name = display_name
        end

        unless description.empty?
          @organization.description = description
        end

        unless billing_email.empty?
          # Update both billing_email and contact_email for consistency
          @organization.billing_email  = billing_email
          @organization.contact_email  = billing_email
          billing_email_changed        = (old_billing_email != billing_email)
        end

        # Update timestamp and save
        @organization.updated = Familia.now.to_i
        @organization.save

        # Sync billing email to Stripe if changed and org has Stripe customer
        # Skip if the change originated from a Stripe webhook (prevents sync loops)
        if billing_email_changed && @organization.stripe_customer_id.to_s.length.positive?
          if Billing::WebhookSyncFlag.skip_stripe_sync?(@organization.extid)
            OT.info '[UpdateOrganization] Skipping Stripe sync (webhook-initiated change)',
              {
                org_extid: @organization.extid,
                new_email: billing_email,
              }
          else
            sync_billing_email_to_stripe(@organization, billing_email, old_billing_email)
          end
        end

        OT.info "[UpdateOrganization] Updated organization #{@extid}"

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
          extid: @extid,
          display_name: display_name,
          description: description,
          billing_email: billing_email,
        }
      end

      private

      # Sync billing email to Stripe Customer
      #
      # Updates the email on the Stripe Customer object. This is a best-effort
      # operation - if it fails, the local update is still preserved and logged.
      #
      # @param org [Onetime::Organization] Organization with stripe_customer_id
      # @param new_email [String] New billing email
      # @param old_email [String, nil] Previous billing email for logging
      def sync_billing_email_to_stripe(org, new_email, old_email)
        OT.info '[UpdateOrganization] Syncing billing email to Stripe',
          {
            org_extid: org.extid,
            stripe_customer_id: org.stripe_customer_id,
            old_email: old_email,
            new_email: new_email,
          }

        Stripe::Customer.update(
          org.stripe_customer_id,
          { email: new_email },
        )

        OT.info '[UpdateOrganization] Stripe customer email updated successfully',
          {
            org_extid: org.extid,
            stripe_customer_id: org.stripe_customer_id,
          }
      rescue Stripe::InvalidRequestError => ex
        # Customer doesn't exist in Stripe (maybe deleted) - log but don't fail
        OT.lw '[UpdateOrganization] Stripe customer not found, skipping email sync',
          {
            org_extid: org.extid,
            stripe_customer_id: org.stripe_customer_id,
            error: ex.message,
          }
      rescue Stripe::StripeError => ex
        # Other Stripe errors - log but don't fail the local update
        OT.le '[UpdateOrganization] Failed to sync billing email to Stripe',
          {
            org_extid: org.extid,
            stripe_customer_id: org.stripe_customer_id,
            error: ex.message,
          }
      end
    end
  end
end
