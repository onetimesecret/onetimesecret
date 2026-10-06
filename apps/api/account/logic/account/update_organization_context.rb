# apps/api/account/logic/account/update_organization_context.rb
#
# frozen_string_literal: true

module AccountAPI::Logic
  module Account
    # Updates the user's organization (workspace) selection in their session
    #
    # The selection is stored in the session so it persists across page
    # refreshes and new tabs: a page load carries no O-Organization-ID
    # header, so without it the server falls back to the default
    # organization (#4565). OrganizationLoader reads the value on every
    # request and re-checks it there.
    #
    # The organization is named by its objid, the same identifier the
    # O-Organization-ID header carries. It must be one the user:
    # - is a member of
    # - that is not archived
    # - that the membership's domain scope permits on this request
    #
    # A refusal does not say which of these failed, and the session is
    # left as it was.
    class UpdateOrganizationContext < UpdateAccountField
      include Onetime::LoggerMethods

      attr_reader :new_organization_id, :old_organization_id

      # Organization objids are UUID strings (36 chars); anything much longer
      # is not one and is kept out of the datastore key lookup.
      MAX_ORGANIZATION_ID_LENGTH = 64
      # Allowed characters in an identifier. A value with anything else is
      # refused rather than stripped down to a different identifier.
      ORGANIZATION_ID_PATTERN    = /\A[a-zA-Z0-9_-]+\z/

      def process_params
        @new_organization_id = normalize_organization_id(params['organization_id'])
        @old_organization_id = sess&.[]('organization_id')
      end

      def normalize_organization_id(value)
        return nil if value.nil?

        normalized = value.to_s.strip

        return nil if normalized.empty? || normalized.length > MAX_ORGANIZATION_ID_LENGTH
        return nil unless normalized.match?(ORGANIZATION_ID_PATTERN)

        normalized
      end

      def raise_concerns
        # Require authentication - anonymous users have no organization to select
        verify_authenticated!

        field_specific_concerns
      end

      def success_data
        {
          organization_id: new_organization_id,
          previous_organization_id: old_organization_id,
        }
      end

      private

      def field_name
        :organization_context
      end

      def field_specific_concerns
        raise_form_error 'Organization is required' if new_organization_id.nil? || new_organization_id.empty?
        raise_form_error 'Invalid organization' unless selectable_organization
      end

      def valid_update?
        !selectable_organization.nil?
      end

      def perform_update
        app_logger.debug 'Updating organization context in session',
          {
            old_organization_id: old_organization_id,
            new_organization_id: new_organization_id,
            customer_id: cust.extid,
          }

        # The loader writes sess['organization_id'] after repeating the checks.
        # They can fail here even though raise_concerns passed: the membership
        # or the organization may have changed in between. Refuse the same way
        # as the first check, so the response never reports a selection the
        # session does not hold.
        selected = Onetime::Application::OrganizationLoader.select_organization(
          cust,
          sess,
          new_organization_id,
          request_organization_context,
        )
        raise_form_error 'Invalid organization' unless selected

        app_logger.info 'Organization context updated',
          {
            customer_id: cust.extid,
            session_id: session_sid,
            old_organization_id: old_organization_id,
            new_organization_id: new_organization_id,
          }
      end

      # The organization the param names, when this user may select it on
      # this request; nil otherwise. Membership, archived state and domain
      # scope are decided by OrganizationLoader, so this endpoint and the
      # request that later reads the selection cannot disagree.
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

      # The context the auth strategy loaded for this request. It carries
      # the request's custom domains (:scope_domains), which a logic class
      # cannot work out for itself: it never sees the Rack env.
      def request_organization_context
        strategy_result.metadata[:organization_context]
      end

      # The base class logs before perform_update runs. The update is only
      # known to have happened after the loader's recheck, so the info line
      # is emitted from perform_update instead.
      def log_update; end
    end
  end
end
