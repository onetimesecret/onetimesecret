# apps/web/auth/operations/accept_invitation.rb
#
# frozen_string_literal: true

module Auth
  module Operations
    # Accepts a pending organization invitation during account creation.
    #
    # This operation is called from the after_create_account hook when an
    # invite_token is present in the signup request. It links the newly
    # created account to the organization specified in the invitation.
    #
    # Flow:
    # 1. User receives invitation email with token
    # 2. User clicks signup link containing invite_token
    # 3. Account creation completes (CreateCustomer, CreateDefaultWorkspace)
    # 4. This operation accepts the invitation, adding user to org
    #
    # Strict email binding: The email used for signup MUST match the
    # invited_email on the invitation. No acknowledgement option.
    #
    # Idempotent: If invitation is already accepted or invalid, returns
    # a structured result without raising.
    #
    # @example
    #   AcceptInvitation.new(
    #     customer: customer,
    #     token: 'abc123...'
    #   ).call
    #   #=> { accepted: true, organization_id: 'org_xyz', role: 'member' }
    #
    class AcceptInvitation
      include Onetime::LoggerMethods

      attr_reader :customer, :token

      # @param customer [Onetime::Customer] The newly created customer
      # @param token [String] The invitation token from signup URL
      def initialize(customer:, token:)
        @customer = customer
        @token    = token
      end

      # Execute the operation
      #
      # @return [Hash] Result with :accepted (boolean) and additional context
      def call
        return skip_result('no_token') if token.to_s.strip.empty?

        invitation = Onetime::OrganizationMembership.find_by_token(token)
        return skip_result('not_found') unless invitation
        return skip_result('not_pending') unless invitation.pending?
        return skip_result('expired') if invitation.expired?

        # Strict email binding - signup email must match invited email
        unless emails_match?(invitation.invited_email, customer.email)
          return skip_result('email_mismatch')
        end

        invitation.accept!(customer)

        # Invite link click proves email ownership — mark verified at Redis layer
        customer.verified    = true
        customer.verified_by = 'invite_token'
        customer.save

        Auth::Logging.log_operation(
          :invitation_accepted,
          level: :info,
          customer_id: customer.custid,
          email: customer.email,  # Use :email for automatic obscuring
          organization_id: invitation.organization_objid,
          organization_name: invitation.organization&.display_name,
          role: invitation.role,
          invite_token_prefix: token[0..7],
          verified_by: 'invite_token',
        )

        {
          accepted: true,
          organization_id: invitation.organization_objid,
          role: invitation.role,
        }
      rescue StandardError => ex
        Auth::Logging.log_error(
          :invitation_accept_error,
          exception: ex,
          customer_id: customer&.custid,
          email: customer&.email,  # Use :email for automatic obscuring
          invite_token_prefix: token.to_s[0..7],
        )
        {
          accepted: false,
          reason: 'error',
          error: ex.message,
        }
      end

      private

      def skip_result(reason)
        Auth::Logging.log_operation(
          :invitation_skipped,
          level: :debug,
          customer_id: customer&.custid,
          email: customer&.email,  # Use :email for automatic obscuring
          reason: reason,
          invite_token_prefix: token.to_s[0..7],
        )
        { accepted: false, reason: reason }
      end

      def emails_match?(invited_email, signup_email)
        normalize_email(invited_email) == normalize_email(signup_email)
      end

      def normalize_email(email)
        OT::Utils.normalize_email(email)
      end
    end
  end
end
