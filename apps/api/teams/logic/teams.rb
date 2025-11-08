# apps/api/teams/logic/teams.rb

require_relative 'base'

module TeamAPI
  module Logic
    module Teams
      using Familia::Refinements::TimeLiterals
    end
  end
end

require_relative 'teams/list_teams'
require_relative 'teams/get_team'
require_relative 'teams/create_team'
require_relative 'teams/update_team'
require_relative 'teams/delete_team'
