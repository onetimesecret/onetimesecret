# apps/api/teams/logic/members/add_member.rb

module TeamAPI::Logic
  module Members
    class AddMember < TeamAPI::Logic::Base
      attr_reader :team, :new_member, :email

      def process_params
        @teamid = params[:teamid]
        @email = params[:email].to_s.strip.downcase
      end

      def raise_concerns
        # Require authenticated user
        raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?

        # Validate teamid parameter
        raise_form_error('Team ID required', field: :teamid, error_type: :missing) if @teamid.to_s.empty?

        # Validate email parameter
        raise_form_error('Email address required', field: :email, error_type: :missing) if email.empty?

        # Validate email format
        unless valid_email?(email)
          raise_form_error('Invalid email address', field: :email, error_type: :invalid)
        end

        # Load team
        @team = load_team(@teamid)

        # Verify user is owner (only owners can add members)
        verify_team_owner(@team)

        # Find customer by email
        @new_member = Onetime::Customer.load_by_email(email)
        if @new_member.nil?
          raise_form_error("No account found for email: #{email}", field: :email, error_type: :not_found)
        end

        # Check if already a member
        if @team.member?(@new_member)
          raise_form_error("User is already a team member", field: :email, error_type: :already_exists)
        end
      end

      def process
        OT.ld "[AddMember] Adding member #{email} to team #{@teamid}"

        # Add member to team
        @team.add_member(@new_member, 'member')

        # Update team timestamp
        @team.updated = Familia.now.to_i
        @team.save

        OT.info "[AddMember] Added member #{@new_member.custid} to team #{@teamid}"

        success_data
      end

      def success_data
        {
          user_id: cust.objid,
          teamid: team.teamid,
          record: {
            custid: new_member.custid,
            email: new_member.email,
            role: 'member',
            added_at: Familia.now.to_i,
          },
        }
      end

      def form_fields
        {
          teamid: @teamid,
          email: email,
        }
      end
    end
  end
end
