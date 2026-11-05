# lib/onetime/initializers/configure_secret_activity.rb
#
# frozen_string_literal: true

module Onetime
  module Initializers
    # ConfigureSecretActivity initializer
    #
    # Applies features.secret_activity.max_events to the organization
    # secret-activity trail's retention cap. Must run at boot, before any
    # Organization instance materializes (see SecretActivity.configure!):
    # Familia freezes the field definition at that point, and a different
    # cap requested afterwards raises Familia::RelatedFieldFrozenError and
    # fails the boot.
    #
    # Needs no datastore connection — it only replaces the stored field
    # definition — so it also runs under connect_to_db=false boots (tryouts)
    # and is deliberately absent from boot!'s skip-list. The model constants
    # it touches are safe there: lib/onetime.rb requires lib/onetime/models
    # eagerly at load time (a prerequisite of calling OT.boot! at all), so
    # Organization.related_fields[:secret_activity_events] exists whether or
    # not a connection was opened. connect_to_db gates connections, not
    # model loading.
    #
    class ConfigureSecretActivity < Onetime::Boot::Initializer
      @provides = [:secret_activity]

      def execute(_context)
        feature = Onetime::Organization::Features::SecretActivity

        max_events = begin
          Integer(OT.conf.dig('features', 'secret_activity', 'max_events'))
        rescue ArgumentError, TypeError
          feature::DEFAULT_MAX_EVENTS
        end

        applied = feature.configure!(max_events)
        app_logger.debug "[init] ConfigureSecretActivity max_events=#{applied}"
      end
    end
  end
end
