# lib/onetime/jobs/registry.rb
#
# frozen_string_literal: true

require_relative 'scheduled_job'
require_relative 'maintenance_job'
require_relative 'job_run'

module Onetime
  module Jobs
    # The one discovery of scheduled job classes (#4343), shared by the
    # scheduler daemon (which schedules them), the colonel jobs endpoint and
    # `bin/ots scheduler status` (which list them).
    #
    # Loading the job files is side-effect free: each one only requires its
    # base class and helpers and defines a class. Nothing is scheduled until a
    # caller hands a Rufus::Scheduler to `.schedule`.
    #
    # Discovery walks `Class#subclasses` from ScheduledJob rather than
    # ObjectSpace: deterministic, cheap in the web process, and it holds no
    # references of its own, so throwaway test subclasses can still be
    # collected.
    module Registry
      JOBS_DIR  = File.expand_path('scheduled', __dir__)
      JOBS_GLOB = File.join(JOBS_DIR, '**', '*_job.rb')

      # Module#name, unbound, so a class that overrides `self.name` (a common
      # test idiom) is still seen as the anonymous class it is.
      CONSTANT_NAME = Module.instance_method(:name)

      @loaded = false

      extend self

      def job_files = Dir.glob(JOBS_GLOB).sort

      # Require every job file under lib/onetime/jobs/scheduled/. Idempotent.
      def load_all!
        return true if @loaded

        job_files.each { |file| require file }
        @loaded = true
      end

      # Concrete job classes: named ScheduledJob descendants that implement
      # their own `.schedule`. Abstract intermediates (MaintenanceJob) inherit
      # the base stub that raises NotImplementedError and are dropped by the
      # owner check; anonymous classes are dropped by the name check.
      #
      # @return [Array<Class>] sorted by class name
      def concrete_classes
        descendants(ScheduledJob)
          .select { |klass| concrete?(klass) && constant_name(klass) }
          .sort_by { |klass| constant_name(klass) }
      end

      # @return [Array<Hash>] string-keyed: 'job_id', 'job_class', 'group'
      def entries
        concrete_classes.map do |klass|
          {
            'job_id' => JobRun.job_id_for(constant_name(klass)),
            'job_class' => constant_name(klass),
            'group' => klass < MaintenanceJob ? 'maintenance' : 'scheduled',
          }
        end
      end

      # @return [Class, nil]
      def job_class_for(job_id)
        concrete_classes.find { |klass| JobRun.job_id_for(constant_name(klass)) == job_id.to_s }
      end

      def concrete?(klass)
        klass.method(:schedule).owner != ScheduledJob.singleton_class
      end

      def constant_name(klass) = CONSTANT_NAME.bind_call(klass)

      def descendants(klass)
        klass.subclasses.flat_map { |sub| [sub, *descendants(sub)] }.uniq
      end
    end
  end
end
