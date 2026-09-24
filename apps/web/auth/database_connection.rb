# apps/web/auth/database_connection.rb
#
# frozen_string_literal: true

require 'sequel'

module Auth
  # Opens authdb connections. Depends on Sequel alone, so the standalone
  # `rake auth:migrate` task opens its connection here without loading the
  # application. Auth::Database.connect wraps it with the application's SQL
  # logger; every authdb connection goes through .open.
  module DatabaseConnection
    # How long a SQLite connection waits for a lock another connection holds.
    # Sequel's own default for its `:timeout` option.
    SQLITE_BUSY_TIMEOUT_MS = 5_000

    # Open an authdb connection. The one place connection options live, so
    # the app, migration, probe and rake connections cannot drift.
    #
    # ## SQLite: two settings, and both are needed
    #
    # Concurrent sign-ups answered 500 (`SQLite3::BusyException: database is
    # locked` on the accounts INSERT): 7 of 8 parallel POST
    # /auth/create-account on a file-backed authdb. Two separate causes, and
    # fixing either alone changes nothing (measured with four threads that
    # each read, then insert, inside a transaction: three of four fail under
    # either fix alone, none under both):
    #
    # 1. `transaction_mode = :immediate`. Rodauth's create-account reads inside
    #    its transaction before it inserts. Under SQLite's default DEFERRED
    #    mode two connections then both hold a SHARED lock and both ask to
    #    upgrade; SQLite refuses the second AT ONCE, without consulting the
    #    busy handler, because waiting would deadlock. BEGIN IMMEDIATE takes
    #    the write lock up front, where waiting is safe. Read-only
    #    transactions queue behind writers too; on a single-instance SQLite
    #    authdb that is the price of not failing.
    #
    # 2. `busy_handler_timeout=` in place of `busy_timeout`. Sequel's
    #    `:timeout` option calls sqlite3_busy_timeout, which sleeps inside C
    #    while holding Ruby's GVL. In a threaded server the thread that owns
    #    the lock is then unable to run and release it: every waiter burns
    #    the whole timeout and fails anyway. The sqlite3 gem's
    #    busy_handler_timeout= does the same wait and releases the GVL between
    #    attempts. It is set per connection, after Sequel's own setting, which
    #    it replaces.
    #
    # A wait that still outlasts the timeout raises as before. Reaching it
    # takes more queued writers than the server has threads.
    #
    # Migration connections need the same: several processes booting at once
    # run migrations against the same SQLite file.
    #
    # PostgreSQL needs none of this: a duplicate insert waits on the row and
    # then raises a unique violation, which Rodauth handles. A multi-host
    # PostgreSQL URL is converted to a connection hash first (see
    # .parse_postgres_multihost_url).
    #
    # @param connection_opts [String, Hash] a database URL or a Sequel
    #   connection hash
    # @param logger [#info, nil] SQL logger, logged at trace level; nil for none
    # @return [Sequel::Database]
    def self.open(connection_opts, logger: nil)
      connection_opts = parse_postgres_multihost_url(connection_opts) if multihost_postgres_url?(connection_opts)

      sqlite  = connection_opts.is_a?(String) && connection_opts.start_with?('sqlite')
      options = logger ? { logger: logger, sql_log_level: :trace } : {} # SQL at trace level for safety

      if sqlite
        options[:timeout]       = SQLITE_BUSY_TIMEOUT_MS
        options[:after_connect] = ->(conn) { conn.busy_handler_timeout = SQLITE_BUSY_TIMEOUT_MS if conn.respond_to?(:busy_handler_timeout=) }
      end

      begin
        db = Sequel.connect(connection_opts, **options)
      rescue URI::InvalidURIError
        raise unless connection_opts.is_a?(String)

        # URI.parse quotes the whole URL, password included. A password with
        # an unescaped "#", "@" or "%" is enough to land here. cause: nil,
        # or the original message still travels with the new one.
        raise URI::InvalidURIError, "bad URI (is not URI?): #{redact_url(connection_opts)}", cause: nil
      end

      db.extension :date_arithmetic
      db.transaction_mode = :immediate if sqlite
      db
    end

    # A connection URL with its userinfo and query string replaced by "***",
    # for exception messages. libpq takes a password in either place
    # (`?password=`). Same rule as Onetime::Utils.redact_uri_userinfo, repeated
    # here rather than delegated because this file loads without the
    # application:
    # everything up to the LAST "@" counts as userinfo, so an unescaped "@" in
    # a password redacts too much rather than printing the rest of it. A "?"
    # before that "@" is either in the password or starts a query with an "@"
    # in it (`?password=p@ss`); neither split is safe, so everything after the
    # scheme is redacted.
    #
    #   redact_url('postgresql://u:s3cret@h1,h2/db?sslmode=require')
    #   #=> "postgresql://***@h1,h2/db?***"
    #
    # @param url [String]
    # @return [String]
    def self.redact_url(url)
      url   = url.to_s.scrub
      at    = url.rindex('@')
      query = url.index('?')
      return url.sub(%r{\A((?:[a-z][a-z0-9+.-]*:)?//)?.*}im, '\\1***') if at && query && query < at

      url
        .sub(%r{\A((?:[a-z][a-z0-9+.-]*:)?//)?.*@}im, '\\1***@')
        .sub(/\?.*\z/m, '?***')
    end

    # PostgreSQL multi-host URLs (host1:port1,host2:port2) are not valid URIs.
    #
    # @param connection_opts [String, Hash]
    # @return [Boolean]
    def self.multihost_postgres_url?(connection_opts)
      connection_opts.is_a?(String) &&
        connection_opts.start_with?('postgresql://') &&
        connection_opts.split('?').first.include?(',')
    end

    # Parses PostgreSQL multi-host connection URLs into Sequel connection hash.
    #
    # PostgreSQL libpq supports comma-separated hosts for failover:
    #   postgresql://user:pass@host1:5432,host2:5432/dbname?sslmode=require
    #
    # But this isn't a valid RFC 3986 URI, so Ruby's URI.parse fails.
    # Sequel needs either a single-host URL or a connection hash.
    #
    # This method extracts the first (primary) host and converts the URL
    # to a Sequel connection hash, which pg gem will handle correctly.
    #
    # @param url [String] PostgreSQL connection URL with comma-separated hosts
    # @return [Hash] Sequel connection parameters
    def self.parse_postgres_multihost_url(url)
      # Extract components using regex since URI.parse won't work
      match = url.match(
        %r{
                ^postgresql://
                (?:([^:@]+)(?::([^@]+))?@)?  # user:password (optional)
                ([^,/]+)                      # first host:port
                (?:,[^/]+)?                   # additional hosts (ignored - use primary)
                (?:/([^?]+))?                 # database name
                (?:\?(.+))?                   # query params
              }x,
      )

      raise ArgumentError, "Invalid PostgreSQL URL format: #{redact_url(url)}" unless match

      user, password, host_port, database, query_string = match.captures

      # Parse host and port from first host
      host, port = host_port.split(':')
      port     ||= '5432'

      # Parse query parameters
      params = {}
      if query_string
        query_string.split('&').each do |param|
          key, value         = param.split('=', 2)
          params[key.to_sym] = value
        end
      end

      # Build Sequel connection hash
      opts = {
        adapter: 'postgres',
        host: host,
        port: port.to_i,
        database: database || 'postgres',
      }

      opts[:user]     = user if user
      opts[:password] = password if password

      # Map PostgreSQL connection params to pg gem options
      opts[:sslmode] = params[:sslmode] if params[:sslmode]

      opts
    end
  end
end
