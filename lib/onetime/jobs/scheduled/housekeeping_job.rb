# lib/onetime/jobs/scheduled/housekeeping_job.rb
#
# frozen_string_literal: true

require_relative '../scheduled_job'

module Onetime
  module Jobs
    module Scheduled
      # Runs registered Familia housekeeping chores against model instances.
      #
      # Chores are defined on Familia::Horreum classes via `feature :housekeeping`
      # and the `chore :name do |obj| ... end` DSL. Iteration, error counting,
      # and stats aggregation are owned here; chore bodies own persistence.
      #
      # Designed for short-lived chores: register, run nightly for a few days,
      # remove the chore registration once data is clean.
      #
      # Configuration:
      #   jobs.maintenance.housekeeping.enabled: true
      #   jobs.maintenance.housekeeping.cron: '0 2 * * *'   # nightly at 2 AM
      #   jobs.maintenance.housekeeping.models:               # optional allowlist
      #     - Onetime::Organization
      #     - Onetime::Customer
      #
      # When `models:` is omitted, every model that declares
      # `feature :housekeeping` and registers at least one chore is included.
      #
      # Direct invocation (CLI / one-off):
      #   HousekeepingJob.perform('Onetime::Organization')
      #   HousekeepingJob.perform('Onetime::Organization', :standardize_planid)
      #   HousekeepingJob.perform('Onetime::Organization', limit: 50)
      #
      class HousekeepingJob < ScheduledJob
        JOB_KEY = 'housekeeping'

        class << self
          def schedule(scheduler)
            return unless job_enabled?

            cron_pattern = job_cron
            scheduler_logger.info "[HousekeepingJob] Scheduling with cron: #{cron_pattern}"

            cron(scheduler, cron_pattern) do
              run_scheduled
            end
          end

          # Run all registered chores against every instance of the given model,
          # or a single chore by name. Returns a stats hash:
          #
          #   {
          #     model: 'Onetime::Organization',
          #     scanned: 4200,
          #     chores: {
          #       standardize_planid: { modified: 37, errors: 0 },
          #     },
          #   }
          #
          # @param model_class_name [String] fully-qualified model class name
          # @param chore_name [Symbol, String, nil] specific chore, or nil for all
          # @param limit [Integer, nil] cap on records scanned; nil iterates all
          # @return [Hash] stats hash (see above)
          # @raise [ArgumentError] if the model is unknown or has no chores
          def perform(model_class_name, chore_name = nil, limit: nil)
            klass = resolve_model(model_class_name)

            unless klass.respond_to?(:chores)
              raise ArgumentError, "#{model_class_name} does not enable feature :housekeeping"
            end

            chore_keys = resolve_chore_keys(klass, chore_name)
            stats      = chore_keys.to_h { |key| [key, { modified: 0, errors: 0 }] }
            scanned    = 0

            klass.instances.each do |objid|
              break if limit && scanned >= limit

              record = klass.load(objid)
              next unless record

              scanned += 1

              chore_keys.each do |key|
                results = record.tidy!(key)
                stats[key][:modified] += 1 if results[key]
              rescue StandardError => ex
                stats[key][:errors] += 1
                OT.le "[HousekeepingJob] #{klass}##{record.identifier} chore=#{key} failed: #{ex.message}"
              end
            end

            { model: model_class_name, scanned: scanned, chores: stats }
          end

          # Discover model classes with at least one registered chore.
          #
          # When `jobs.maintenance.housekeeping.models` is configured, only those
          # explicit class names are returned (in declared order). Otherwise we
          # fall back to scanning the well-known set of instance models.
          #
          # @return [Array<Class>] model classes with chores registered
          def models_with_chores
            class_names = configured_models || default_model_names
            class_names.filter_map do |class_name|
              klass = resolve_model(class_name)
              klass if klass.respond_to?(:chores) && klass.chores.any?
            rescue NameError
              nil
            end
          end

          private

          # Iterate every model with chores and run all of them. Logs one
          # structured line per model so failures don't bring down the run.
          def run_scheduled
            models = models_with_chores
            if models.empty?
              scheduler_logger.info '[HousekeepingJob] No models have chores registered; skipping'
              return
            end

            models.each do |klass|
              report = perform(klass.name)
              scheduler_logger.info "[HousekeepingJob] #{JSON.generate(report)}"
            rescue StandardError => ex
              scheduler_logger.error "[HousekeepingJob] #{klass.name} failed: #{ex.message}"
            end
          end

          def resolve_chore_keys(klass, chore_name)
            if chore_name
              key = chore_name.to_sym
              unless klass.chores.key?(key)
                raise ArgumentError, "unknown chore #{chore_name.inspect} for #{klass}"
              end

              [key]
            else
              if klass.chores.empty?
                raise ArgumentError, "#{klass} has no chores registered"
              end

              klass.chores.keys
            end
          end

          def resolve_model(class_name)
            class_name.to_s.split('::').reduce(Object) do |mod, name|
              mod.const_get(name)
            end
          end

          def maintenance_config
            OT.conf.dig('jobs', 'maintenance') || {}
          end

          def job_config
            maintenance_config[JOB_KEY] || {}
          end

          def job_enabled?
            maintenance_config['enabled'] == true && job_config['enabled'] == true
          end

          def job_cron
            job_config['cron'] || '0 2 * * *'
          end

          def configured_models
            list = job_config['models']
            return nil unless list.is_a?(Array) && list.any?

            list
          end

          # Fallback list of models to scan for chores when not explicitly
          # configured. Mirrors MaintenanceJob::INSTANCE_MODELS so we stay
          # in sync with the canonical iterable models.
          def default_model_names
            require_relative '../maintenance_job'
            Onetime::Jobs::MaintenanceJob::INSTANCE_MODELS.map { |_label, class_name, _prefix| class_name }
          end
        end
      end
    end
  end
end
