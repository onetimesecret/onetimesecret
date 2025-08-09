# apps/api/v2/models/definitions/team_definitions.rb

require 'rack/utils'

module V2
  class Team < Familia::Horreum
    prefix :team

    identifier :teamid

    class_sorted_set :values

    field :teamid
    field :display_name
    field :description

    def init
      @teamid ||= OT::Utils.generate_short_id
    end
  end
end
