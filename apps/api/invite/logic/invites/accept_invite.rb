# apps/api/invite/logic/invites/accept_invite.rb
#
# frozen_string_literal: true

module InviteAPI::Logic
  module Invites
    # Accept an invitation to join an organization
    #
    # POST /api/invite/:token/accept
    #
    # Auth: sessionauth (user must be authenticated)
    # The accepting user's email must match the invited email.
    # Creates the organization membership and clears the invitation token.
    #
    class AcceptInvite < InviteAPI::Logic::Base
      include Onetime::LoggerMethods

      attr_reader :invitation, :organization, :membership

      def process_params
        @token = sanitize_identifier(params['token'])
      end

      def raise_concerns
        # Must be authenticated
        verify_authenticated!

        if @token.nil? || @token.empty?
          raise_form_error(
            'Token is required',
            error_key: 'api.invite.errors.token_required',
            field: :token,
            error_type: :missing,
          )
        end

        @invitation   = load_invitation(@token)
        @organization = @invitation.organization

        # Check if organization still exists (may have been deleted)
        unless @organization
          raise_form_error(
            'Organization no longer exists',
            error_key: 'api.invite.errors.organization_no_longer_exists',
            field: :token,
            error_type: :missing,
          )
        end

        # Check if invitation is still pending
        raise_already_processed(@invitation) unless @invitation.pending?

        # Check if invitation has expired
        if @invitation.expired?
          raise_form_error(
            'Invitation has expired',
            error_key: 'api.invite.errors.invitation_expired',
            field: :token,
            error_type: :expired,
          )
        end

        # Strict email binding - no exceptions
        if @invitation.invited_email
          invited = normalize_email(@invitation.invited_email)
          user    = normalize_email(cust.email)

          unless invited == user
            raise_form_error(
              'Your email address does not match the invitation',
              error_key: 'api.invite.errors.email_mismatch',
              field: :email,
              error_type: :email_mismatch,
            )
          end
        end

        # Check if user is already a member
        return unless @organization.member?(cust)

        raise_form_error(
          'You are already a member of this organization',
          error_key: 'api.invite.errors.already_member',
          field: :token,
          error_type: :exists,
        )
      end

      def process
        auth_logger.debug 'Accepting invitation',
          invitation_id: @invitation.objid,
          user: cust.obscure_email

        # Accept the invitation (updates membership status and adds to org).
        # provisioning_source: 'invited' attributes lifecycle to the invitation
        # flow, distinct from SSO JIT provisioning. See OrganizationMembership.
        @invitation.accept!(cust, provisioning_source: 'invited')

        @organization_selected = select_joined_organization

        auth_logger.info 'User joined organization',
          event: 'invite.accepted',
          invitation_id: @invitation.objid,
          organization_id: @organization.extid,
          user: cust.obscure_email,
          role: @invitation.role,
          result: :success

        success_data
      end

      def success_data
        {
          user_id: cust.extid,
          organization: {
            id: @organization.extid,
            objid: @organization.objid,
            display_name: @organization.display_name,
          },
          # Whether this session now has the joined organization selected.
          # When false the client should load the page again rather than
          # assume it (see #select_joined_organization).
          organization_selected: @organization_selected == true,
          role: @invitation.role,
          joined_at: @invitation.joined_at,
        }
      end

      protected

      # Make the joined organization this session's selection, so the user
      # lands in it rather than in the default organization the loader would
      # otherwise fall back to. Goes through the same membership, archived
      # and domain-scope checks as POST /api/account/update-organization-context,
      # against the request's custom domains (:scope_domains in the
      # organization context the auth strategy loaded; a logic class never
      # sees the Rack env). The membership is already written: a refused
      # selection leaves the session as it was and the accept stands.
      #
      # @return [Boolean] whether the session now holds the joined organization
      def select_joined_organization
        selected = Onetime::Application::OrganizationLoader.select_organization(
          cust,
          sess,
          @organization.objid,
          strategy_result.metadata[:organization_context],
        )
        return true if selected

        auth_logger.debug 'Joined organization not selected for this session',
          invitation_id: @invitation.objid,
          organization_id: @organization.extid
        false
      end

      def normalize_email(email)
        OT::Utils.normalize_email(email)
      end
    end
  end
end
