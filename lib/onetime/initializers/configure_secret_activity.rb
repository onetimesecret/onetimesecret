# lib/onetime/initializers/configure_secret_activity.rb
#
# frozen_string_literal: true

module Onetime
  module Initializers
    # ConfigureSecretActivity initializer
    #
    # Applies features.secret_activity.max_events, .max_guest_events and
    # .coalesce_window to the organization secret-activity trail (see
    # SecretActivity.configure!). A value that is not an integer falls back
    # to that setting's default.
    #
    # Needs no datastore connection, so it also runs under
    # connect_to_db=false boots (tryouts) and is deliberately absent from
    # boot!'s skip-list.
    #
    class ConfigureSecretActivity < Onetime::Boot::Initializer
      @provides = [:secret_activity]

      def execute(_context)
        feature = Onetime::Organization::Features::SecretActivity

        feature.configure!(
          setting('max_events', feature::DEFAULT_MAX_EVENTS),
          max_guest_events: setting('max_guest_events', feature::DEFAULT_MAX_GUEST_EVENTS),
          coalesce_window: setting('coalesce_window', feature::DEFAULT_COALESCE_WINDOW),
        )
        app_logger.debug "[init] ConfigureSecretActivity #{feature.settings}"
      end

      private

      def setting(name, default)
        Integer(OT.conf.get("features.secret_activity.#{name}", default))
      rescue ArgumentError, TypeError
        default
      end
    end
  end
end
