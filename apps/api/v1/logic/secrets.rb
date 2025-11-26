# apps/api/v1/logic/secrets.rb
#
# frozen_string_literal: true

require_relative 'secrets/burn_secret'
require_relative 'secrets/conceal_secret'
require_relative 'secrets/generate_secret'
# NOTE: v1 does not have a reveal_secret action
require_relative 'secrets/show_metadata'
require_relative 'secrets/show_metadata_list'
require_relative 'secrets/show_secret'
