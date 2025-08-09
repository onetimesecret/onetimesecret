# apps/api/v2/models/management/organization_management.rb

module V2
  class Organization < Familia::Horreum
    module Management
      def create(display_name = nil, contact_email = nil)
        raise Onetime::Problem, 'Organization exists for that email address' if contact_email && exists?(contact_email)

        org = new display_name: display_name, contact_email: contact_email
        org.save

        OT.ld "[create] orgid: #{orgid}, #{org..to_s}"
        add org
        org
      end

      def add(org)
        values.add OT.now.to_i, org.identifier
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
