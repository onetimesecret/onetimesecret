# lib/onetime/cli/housekeeping/list_command.rb
#
# frozen_string_literal: true

# List models that declare `feature :housekeeping` with at least one chore.
#
# Usage:
#   bin/ots housekeeping list

require_relative '../../jobs/scheduled/housekeeping_job'

module Onetime
  module CLI
    class HousekeepingListCommand < Command
      desc 'List models with registered housekeeping chores'

      def call(**)
        boot_application!

        models = Onetime::Jobs::Scheduled::HousekeepingJob.models_with_chores

        if models.empty?
          puts 'No models have chores registered.'
          return
        end

        models.each do |klass|
          puts klass.name
          klass.chores.each_key do |chore_name|
            puts "  - #{chore_name}"
          end
        end
      end
    end

    register 'housekeeping list', HousekeepingListCommand
  end
end
