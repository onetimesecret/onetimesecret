# apps/api/v2/logic/colonel.rb

require_relative 'base'

module V2
  module Logic
    module Colonel
    end
  end
end

require_relative 'colonel/get_colonel_info'
require_relative 'colonel/get_colonel_stats'
require_relative 'colonel/get_mutable_config'
require_relative 'colonel/update_mutable_config'
