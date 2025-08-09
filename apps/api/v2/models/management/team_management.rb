# apps/api/v2/models/management/team_management.rb

module V2
  class Team < Familia::Horreum
    module Management
      def create(display_name = nil, contact_email = nil)
        raise Onetime::Problem, 'Team exists for that email address' if contact_email && exists?(contact_email)

        team = new display_name: display_name, contact_email: contact_email
        team.save

        OT.ld "[create] teamid: #{teamid}, #{team..to_s}"
        add team
        team
      end

      def add(team)
        values.add OT.now.to_i, team.identifier
      end

      def all
        values.revrangeraw(0, -1).collect { |identifier| load(identifier) }
      end

      def recent(duration = 30.days, epoint = OT.now.to_i)
        spoint = OT.now.to_i - duration
        values.rangebyscoreraw(spoint, epoint).collect { |identifier| load(identifier) }
      end
    end
  end
end
