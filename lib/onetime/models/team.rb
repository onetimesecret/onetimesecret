# lib/onetime/models/team.rb

require 'rack/utils'

module Onetime
  # Team Model (aka Group)
  #
  class Team < Familia::Horreum

    using Familia::Refinements::TimeLiterals

    feature :safe_dump

    feature :relationships
    feature :object_identifier
    feature :required_fields

    prefix :team

    identifier_field :teamid

    class_sorted_set :values

    field :teamid
    field :display_name
    field :description

    def init
      @teamid ||= Familia.generate_id
      nil
    end

    class << self
      def create(display_name = nil, contact_email = nil)
        raise Onetime::Problem, 'Team exists for that email address' if contact_email && exists?(contact_email)

        team = new display_name: display_name, contact_email: contact_email
        team.save

        OT.ld "[create] teamid: #{team.teamid}, #{team.to_s}"
        add team
        team
      end
    end
  end
end
