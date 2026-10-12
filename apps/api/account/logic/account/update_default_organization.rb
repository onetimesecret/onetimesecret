# apps/api/account/logic/account/update_default_organization.rb
#
# frozen_string_literal: true

require_relative 'update_organization_context'

module AccountAPI::Logic
  module Account
    # Sets the user's default organization (workspace): customer.default_org_id,
    # which OrganizationLoader prefers over the is_default flag when nothing
    # else chooses the organization for a request.
    #
    # POST /api/account/update-default-organization { organization_id: <objid> }
    #
    # The organization is named by its objid and must pass the same checks as
    # POST /api/account/update-organization-context: the user is a member, it
    # is not archived, and the membership's domain scope permits it on this
    # request. A refusal does not say which of these failed, and nothing is
    # written.
    #
    # The organization is also selected for the current session. Without
    # that, a selection the session already holds (session['organization_id'])
    # keeps winning over the new default in this browser.
    class UpdateDefaultOrganization < UpdateAccountField
      include Onetime::LoggerMethods

      MAX_ORGANIZATION_ID_LENGTH = UpdateOrganizationContext::MAX_ORGANIZATION_ID_LENGTH
      ORGANIZATION_ID_PATTERN    = UpdateOrganizationContext::ORGANIZATION_ID_PATTERN

      attr_reader :new_organization_id, :previous_default_organization_id

      def process_params
        @new_organization_id = normalize_organization_id(params['organization_id'])
      end

      def normalize_organization_id(value)
        return nil if value.nil?

        normalized = value.to_s.strip

        return nil if normalized.empty? || normalized.length > MAX_ORGANIZATION_ID_LENGTH
        return nil unless normalized.match?(ORGANIZATION_ID_PATTERN)

        normalized
      end

      def raise_concerns
        verify_authenticated!

        field_specific_concerns
      end

      # previous_default_organization_id is the organization that was the
      # user's default before this change (OrganizationLoader.default_organization),
      # nil when there was none.
      def success_data
        {
          organization_id: new_organization_id,
          previous_default_organization_id: previous_default_organization_id,
        }
      end

      private

      def field_name
        :default_organization
      end

      def field_specific_concerns
        raise_form_error 'Organization is required' if new_organization_id.nil?
        raise_form_error 'Invalid organization' unless selectable_organization
      end

      def valid_update?
        !selectable_organization.nil?
      end

      def perform_update
        @previous_default_organization_id =
          Onetime::Application::OrganizationLoader.default_organization(cust)&.objid

        # The loader repeats the checks before writing the session. They can
        # fail here even though raise_concerns passed (the membership or the
        # organization changed in between); refuse the same way, before the
        # default is written.
        selected = Onetime::Application::OrganizationLoader.select_organization(
          cust,
          sess,
          new_organization_id,
          request_organization_context,
        )
        raise_form_error 'Invalid organization' unless selected

        # Single-field write: leaves the customer's other fields as stored.
        cust.default_org_id!(selected.objid)

        app_logger.info 'Default organization updated',
          {
            customer_id: cust.extid,
            previous_default_organization_id: previous_default_organization_id,
            new_default_organization_id: selected.objid,
          }
      end

      # See UpdateOrganizationContext#selectable_organization.
      #
      # @return [Onetime::Organization, nil]
      def selectable_organization
        return @selectable_organization if defined?(@selectable_organization)

        @selectable_organization =
          if anonymous_user? || new_organization_id.nil?
            nil
          else
            Onetime::Application::OrganizationLoader.selectable_organization(
              cust,
              new_organization_id,
              request_organization_context,
            )
          end
      end

      # The context the auth strategy loaded for this request; it carries the
      # request's custom domains (:scope_domains) for the domain-scope check.
      def request_organization_context
        strategy_result.metadata[:organization_context]
      end

      # The update is only known to have happened after the loader's recheck,
      # so the info line is emitted from perform_update instead.
      def log_update; end
    end
  end
end
