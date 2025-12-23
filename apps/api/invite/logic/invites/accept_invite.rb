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
      attr_reader :invitation, :organization, :membership

      def process_params
        @token = params['token']
      end

      def raise_concerns
        # Must be authenticated
        raise_form_error('Authentication required', error_type: :unauthorized) if cust.anonymous?

        raise_form_error('Token is required', field: :token) if @token.nil? || @token.empty?

        @invitation   = load_invitation(@token)
        @organization = @invitation.organization

        # Check if organization still exists (may have been deleted)
        unless @organization
          raise_form_error('Organization no longer exists', field: :token)
        end

        # Check if invitation is still pending
        unless @invitation.pending?
          raise_form_error(
            "Invitation has already been #{@invitation.status}",
            field: :token,
          )
        end

        # Check if invitation has expired
        if @invitation.expired?
          raise_form_error('Invitation has expired', field: :token)
        end

        # Verify email match (with normalization)
        if @invitation.invited_email
          invited = normalize_email(@invitation.invited_email)
          user    = normalize_email(cust.email)

          unless emails_match?(invited, user)
            raise_form_error(
              'Your email address does not match the invitation',
              field: :email,
            )
          end
        end

        # Check if user is already a member
        if @organization.member?(cust)
          raise_form_error('You are already a member of this organization', field: :token)
        end
      end

      def process
        OT.ld "[AcceptInvite] Accepting invitation #{@invitation.objid} for user #{OT::Utils.obscure_email(cust.custid)}"

        # Accept the invitation (updates membership status and adds to org)
        @invitation.accept!(cust)

        OT.info "[AcceptInvite] User #{OT::Utils.obscure_email(cust.custid)} joined organization #{@organization.extid}"

        success_data
      end

      def success_data
        {
          user_id: cust.objid,
          organization: {
            id: @organization.extid,
            display_name: @organization.display_name,
          },
          role: @invitation.role,
          joined_at: @invitation.joined_at,
        }
      end

      protected

      def normalize_email(email)
        email.to_s.strip.downcase
      end

      # Match emails with support for + aliases
      def emails_match?(email1, email2)
        return false if email1.nil? || email2.nil?

        local1, domain1 = email1.split('@', 2)
        local2, domain2 = email2.split('@', 2)

        # Domains must match exactly
        return false unless domain1 == domain2

        # Strip + suffix from local parts
        base1 = local1.split('+', 2).first
        base2 = local2.split('+', 2).first

        base1 == base2
      end
    end
  end
end
