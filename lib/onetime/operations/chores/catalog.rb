# lib/onetime/operations/chores/catalog.rb
#
# frozen_string_literal: true

require 'onetime/jobs/job_run'
require 'onetime/jobs/scheduled/housekeeping_job'

module Onetime
  module Operations
    # Chores an operator can run on demand from the colonel console (#4343).
    #
    # Not to be confused with `Onetime::Chores`, the namespace of the chore
    # IMPLEMENTATIONS registered on each model. Every reference from inside
    # this namespace to anything under `Onetime` is written fully qualified
    # (`::Onetime::...`) so the two can never shadow each other.
    module Chores
      # The allowlist of runnable chores (#4343).
      #
      # One id per chore: `housekeeping.<model>.<chore>` for a housekeeping
      # chore registered on a model with `feature :housekeeping`, plus
      # `entitlement_materialize` for the billing entitlement run. The id is
      # also the typed confirmation token for a live run, so each one names
      # exactly one thing that will execute.
      #
      # ## Why an explicit list
      #
      # Housekeeping chores come and go: one is registered, runs nightly for a
      # few days, and is deleted once the data is clean. Building the console
      # list from whatever happens to be registered would put a new chore on
      # the console the day it merges, with nobody having decided it is safe to
      # trigger from a browser. So each chore is named here ({HOUSEKEEPING}) or
      # refused here with a reason ({EXCLUDED}).
      # spec/unit/onetime/operations/chores/catalog_spec.rb fails when a
      # registered chore is in neither list, and when an allowlisted chore is
      # no longer registered.
      #
      # ## What is listed at runtime
      #
      # An allowlisted housekeeping chore is listed only while
      # HousekeepingJob.models_with_chores returns its model and the model
      # still registers the chore: the console offers the same model set the
      # nightly sweep runs (including a `jobs.maintenance.housekeeping.models`
      # override). The entitlement run is listed only when billing is enabled.
      # Anything not listed is unknown: RunChore answers 404, the same as for a
      # typo.
      module Catalog
        HOUSEKEEPING_KIND = 'housekeeping'
        BILLING_KIND      = 'billing'

        ENTITLEMENT_MATERIALIZE = 'entitlement_materialize'

        # The full-fleet equivalent of the console's bounded entitlement run.
        # The pull comes first for the same reason the nightly job pulls first
        # (#4203): MaterializePlans reads only the cached catalog.
        ENTITLEMENT_CLI =
          'bin/ots billing catalog pull && bin/ots billing plans materialize --all --include-memberships --run'

        # id => [model class name, chore name]
        HOUSEKEEPING = {
          'housekeeping.organization.materialize_standalone_entitlements' =>
            ['Onetime::Organization', 'materialize_standalone_entitlements'],
          'housekeeping.organization.ensure_member_through_models' =>
            ['Onetime::Organization', 'ensure_member_through_models'],
          'housekeeping.organization.standardize_owner_id' =>
            ['Onetime::Organization', 'standardize_owner_id'],
          'housekeeping.organization.standardize_planid' =>
            ['Onetime::Organization', 'standardize_planid'],
          'housekeeping.custom_domain.migrate_ownership_verified' =>
            ['Onetime::CustomDomain', 'migrate_ownership_verified'],
          'housekeeping.custom_domain.migrate_incoming_secrets_to_config' =>
            ['Onetime::CustomDomain', 'migrate_incoming_secrets_to_config'],
          'housekeeping.customer.reserialize_fields' =>
            ['Onetime::Customer', 'reserialize_fields'],
        }.freeze

        CONFIG_MODEL_REASON =
          'registered on a CustomDomain config model, which the nightly housekeeping sweep ' \
          'skips unless listed in jobs.maintenance.housekeeping.models; run it per model ' \
          'with bin/ots housekeeping run'

        # Registered chores deliberately NOT runnable from the console.
        # id => reason. Requests for these ids get the same 404 as any unknown
        # id.
        EXCLUDED = {
          # Deletes vhosts at Approximated (a remote API), so a wrong run takes
          # customer domains offline and cannot be undone from here. Its only
          # gate is APPROXIMATED_VHOST_CLEANUP=apply in the environment.
          'housekeeping.custom_domain.remove_orphaned_approximated_vhosts' =>
            'deletes remote Approximated vhosts: irreversible, customer-outage risk; CLI-only',
          'housekeeping.signin_config.normalize_boolean_encoding' => CONFIG_MODEL_REASON,
          'housekeeping.signup_config.normalize_boolean_encoding' => CONFIG_MODEL_REASON,
          'housekeeping.homepage_config.normalize_boolean_encoding' => CONFIG_MODEL_REASON,
          'housekeeping.api_config.normalize_boolean_encoding' => CONFIG_MODEL_REASON,
          'housekeeping.incoming_config.normalize_boolean_encoding' => CONFIG_MODEL_REASON,
          'housekeeping.sso_config.normalize_boolean_encoding' => CONFIG_MODEL_REASON,
          'housekeeping.mailer_config.normalize_boolean_encoding' => CONFIG_MODEL_REASON,
        }.freeze

        # One runnable chore.
        #
        # @!attribute id [r] String the allowlist key and confirmation token
        # @!attribute kind [r] String {HOUSEKEEPING_KIND} or {BILLING_KIND}
        # @!attribute model [r] String model class name
        # @!attribute chore [r] String, nil the housekeeping chore name; nil
        #   for the entitlement run
        # @!attribute supports_dry_run [r] Boolean true only when a dry run
        #   evaluates every record without writing (housekeeping chores have
        #   no such mode)
        # @!attribute cli [r] String the equivalent full-fleet command
        Entry = Data.define(:id, :kind, :model, :chore, :supports_dry_run, :cli) do
          def housekeeping? = kind == HOUSEKEEPING_KIND

          # The chore names this entry runs, as the console lists them.
          def chores = chore ? [chore] : []

          # JobRun id for this chore's last-run record, namespaced so it never
          # collides with a scheduled job's id.
          def run_id = "chore.#{id}"
        end

        extend self

        # @return [Array<Entry>] the chores runnable right now, in allowlist
        #   order, the entitlement run last
        def all
          housekeeping_entries + billing_entries
        end

        # @param id [String]
        # @return [Entry, nil]
        def find(id)
          key = id.to_s
          all.find { |entry| entry.id == key }
        end

        def valid?(id) = !find(id).nil?

        # The id a housekeeping chore would have, derived the way the
        # allowlist keys are written (JobRun.job_id_for snake-cases the class
        # basename: Onetime::CustomDomain -> custom_domain).
        #
        # @param model [Class, String]
        # @param chore [Symbol, String]
        # @return [String]
        def housekeeping_id(model, chore)
          "#{HOUSEKEEPING_KIND}.#{::Onetime::Jobs::JobRun.job_id_for(model)}.#{chore}"
        end

        # @param entry [Entry] a housekeeping entry
        # @return [Class]
        def model_class(entry)
          ::Object.const_get(entry.model)
        end

        private

        def housekeeping_entries
          registered = registered_chores
          HOUSEKEEPING.filter_map do |id, (model, chore)|
            next unless registered.fetch(model, []).include?(chore)

            Entry.new(
              id: id,
              kind: HOUSEKEEPING_KIND,
              model: model,
              chore: chore,
              supports_dry_run: false,
              cli: "bin/ots housekeeping run #{model} #{chore}",
            )
          end
        end

        # { 'Onetime::Organization' => ['standardize_planid', ...] } for the
        # models the nightly sweep runs.
        def registered_chores
          ::Onetime::Jobs::Scheduled::HousekeepingJob.models_with_chores.to_h do |klass|
            [klass.name, klass.chores.keys.map(&:to_s)]
          end
        end

        def billing_entries
          return [] unless ::Onetime.billing_config.enabled?

          [
            Entry.new(
              id: ENTITLEMENT_MATERIALIZE,
              kind: BILLING_KIND,
              model: 'Onetime::Organization',
              chore: nil,
              supports_dry_run: true,
              cli: ENTITLEMENT_CLI,
            ),
          ]
        end
      end
    end
  end
end
