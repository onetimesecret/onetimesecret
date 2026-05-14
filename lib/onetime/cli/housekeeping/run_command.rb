# lib/onetime/cli/housekeeping/run_command.rb
#
# frozen_string_literal: true

# Run housekeeping chores against instances of a Familia::Horreum model.
#
# Usage:
#   bin/ots housekeeping run Onetime::Organization
#   bin/ots housekeeping run Onetime::Organization standardize_planid
#   bin/ots housekeeping run Onetime::Organization --limit 50

require_relative '../../jobs/scheduled/housekeeping_job'

module Onetime
  module CLI
    class HousekeepingRunCommand < Command
      desc 'Run housekeeping chores for a model'

      argument :model,
        type: :string,
        required: true,
        desc: 'Fully-qualified model class name (e.g. Onetime::Organization)'

      argument :chore,
        type: :string,
        required: false,
        desc: 'Chore name (omit to run all chores for the model)'

      option :limit,
        type: :integer,
        default: nil,
        desc: 'Maximum number of records to scan'

      def call(model:, chore: nil, limit: nil, **)
        boot_application!

        puts "Running housekeeping for #{model}..."
        report = Onetime::Jobs::Scheduled::HousekeepingJob.perform(
          model,
          chore,
          limit: limit,
        )

        report[:chores].each do |chore_name, stats|
          puts format(
            '  %s: %d scanned, %d modified, %d errors',
            chore_name,
            report[:scanned],
            stats[:modified],
            stats[:errors],
          )
        end
        puts 'Done.'
      rescue ArgumentError, NameError => ex
        warn ex.message
        exit 1
      end
    end

    register 'housekeeping run', HousekeepingRunCommand
  end
end
