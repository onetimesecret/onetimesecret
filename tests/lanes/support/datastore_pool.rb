# tests/lanes/support/datastore_pool.rb
#
# frozen_string_literal: true

require 'connection_pool'

module Lanes
  # A bounded Familia connection pool for a test process that has not run
  # the application's SetupConnectionPool initializer.
  #
  # Without a connection provider, every Familia.dbclient lookup falls
  # through to Familia's fallback handler, which creates a fresh Redis
  # client (familia 2.12, delano/familia#456). Unit specs never boot, and
  # unit tryouts that boot with connect_to_db=false skip the initializer,
  # so one datastore-heavy spec file opened thousands of short-lived
  # connections to the test valkey. On macOS those exhausted the ephemeral
  # port range (49152-65535): connects failed with Errno::EADDRNOTAVAIL and
  # the runner reported the test services lost mid-run (exit 69).
  #
  # install! gives such a process the same provider a full boot installs
  # (Onetime.pooled_connection_provider): the pinned-connection stack first,
  # otherwise a pool checkout. Connections are created lazily, so a helper
  # may install the pool before it knows whether the process will touch the
  # datastore, and every one of them targets the URI install! was given.
  #
  # The pool is also registered as Onetime::Runtime.infrastructure
  # .database_pool, so Onetime.with_pinned_dbclient and the WATCH-guarded
  # write paths behave as they do after a full boot.
  #
  # A full boot replaces the provider and the registered pool with its own;
  # the idle connections this pool holds stay open until the process ends.
  # A spec that snapshots the Familia pool configuration around its examples
  # (OnetimeStateHelpers) sees this pool as the baseline it restores.
  module DatastorePool
    DEFAULT_SIZE    = 25
    DEFAULT_TIMEOUT = 5

    # The isolated test valkey (tests/lanes/README.md). boot.rb refuses a
    # test boot against any other port; install! refuses a pool there.
    TEST_DATASTORE_PORT = 2163

    class << self
      # The pool install! created, or nil when it did not install one.
      attr_reader :pool

      # Install the pool unless a provider is already in place (an
      # application boot, or a spec fixture, owns it then; Familia.uri is
      # left alone too).
      #
      # +uri+ becomes Familia.uri and the target of every pooled connection.
      # The target is fixed here, not read from Familia.uri at each
      # checkout: Familia.uri defaults to 127.0.0.1:6379, the development
      # datastore, and a lookup made before a helper set the test URI would
      # otherwise keep a connection there for the life of the process.
      #
      # A +uri+ on any port but TEST_DATASTORE_PORT raises. spec_helper
      # passes the Familia.uri it reads from spec/config.test.yaml, and when
      # that load fails it warns and carries on with the 6379 default; the
      # refusal is what stops the run there.
      #
      # Connections are built as SetupConnectionPool builds them
      # (Onetime.create_pooled_dbclient), reconnect attempts included.
      #
      # Size and timeout read the initializer's FAMILIA_POOL_SIZE and
      # FAMILIA_POOL_TIMEOUT, so a lane env tunes both the same way. A value
      # that is not a decimal integer raises here, where the initializer's
      # String#to_i reads it as 0 (setup_connection_pool_spec pins that):
      # the test process stops at load instead of running on a pool that
      # cannot hand out a connection.
      #
      # @param uri [String, URI] the test datastore
      # @return [ConnectionPool, nil] the installed pool, or nil when a
      #   provider was already present
      # @raise [ArgumentError] when +uri+ is not on TEST_DATASTORE_PORT
      def install!(uri:,
                   size: env_integer('FAMILIA_POOL_SIZE', DEFAULT_SIZE),
                   timeout: env_integer('FAMILIA_POOL_TIMEOUT', DEFAULT_TIMEOUT))
        return nil if Familia.connection_provider

        target = Familia.normalize_uri(uri)
        unless target.port == TEST_DATASTORE_PORT
          raise ArgumentError,
            "Lanes::DatastorePool refuses #{OT::Utils.redact_uri_userinfo(target.to_s)}: a test process " \
            "uses the test datastore on port #{TEST_DATASTORE_PORT}. Did spec/config.test.yaml fail to load?"
        end

        Familia.uri = target
        pool        = ConnectionPool.new(size: size, timeout: timeout) { Onetime.create_pooled_dbclient(target) }
        Familia.connection_provider = Onetime.pooled_connection_provider(pool)
        Onetime::Runtime.update_infrastructure(database_pool: pool)
        @pool = pool
      end

      private

      # A decimal integer from ENV: '010' is 10, where Integer('010') is 8.
      def env_integer(name, default)
        Integer(ENV.fetch(name, default.to_s), 10)
      end
    end
  end
end
