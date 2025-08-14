# apps/api/v2/models/team.rb

require 'rack/utils'

require_relative 'definitions/team_definition'

module V2
  # Team Model (aka Group)
  #
  class Team < Familia::Horreum
  end
end
