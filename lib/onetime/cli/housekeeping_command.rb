# lib/onetime/cli/housekeeping_command.rb
#
# frozen_string_literal: true

# CLI command for running Familia housekeeping chores. Shows usage and the
# list of models with registered chores when invoked without a subcommand.
#
# Usage:
#   bin/ots housekeeping                              # Show usage + model list
#   bin/ots housekeeping list                         # List models with chores
#   bin/ots housekeeping run Onetime::Organization    # Run all chores
#   bin/ots housekeeping run Onetime::Organization standardize_planid
#   bin/ots housekeeping run Onetime::Organization --limit 50

require_relative '../jobs/scheduled/housekeeping_job'

module Onetime
  module CLI
    class HousekeepingCommand < Command
      desc 'Run Familia model housekeeping chores'

      def call(**)
        boot_application!

        models = Onetime::Jobs::Scheduled::HousekeepingJob.models_with_chores

        puts format('%d model(s) with housekeeping chores', models.size)
        puts
        puts 'Usage:'
        puts '  bin/ots housekeeping list                      # List models and their chores'
        puts '  bin/ots housekeeping run MODEL                 # Run all chores for a model'
        puts '  bin/ots housekeeping run MODEL CHORE_NAME      # Run a single chore'
        puts '  bin/ots housekeeping run MODEL --limit 50      # Cap records scanned'
      end
    end

    register 'housekeeping', HousekeepingCommand
  end
end
