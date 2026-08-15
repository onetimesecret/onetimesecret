# tests/lanes/support/provision_pg_database.rb
#
# frozen_string_literal: true

# Ensures the per-worktree PostgreSQL test database exists and carries the
# repo's role/grant model, so concurrent lane runs in a worktree forest do
# not share auth tables (#4168).
#
# Called by tests/lanes/run, once, before the lane's tasks exec — only for
# lanes that actually address PostgreSQL, and only when the runner assigned
# a nonzero worktree index. Reads AUTH_DATABASE_URL_MIGRATIONS (the elevated
# connection) because provisioning is DDL.
#
# WHY THIS NEEDS NO SUPERUSER, AND NO SQL OF ITS OWN
#
# `onetime_migrator` is created `WITH ... CREATEDB` by initialize_test_db.sql,
# so it can create a database and owns what it creates. Two consequences:
#
#   - It can install citext itself. citext is a *trusted* extension (PG 13+),
#     so a non-superuser with CREATE on the database may install it, which is
#     what migration 001_initial.rb already does on every fresh database.
#   - It can run initialize_test_db.sql wholesale against the new database,
#     `DROP SCHEMA public CASCADE` included: the public schema of a database
#     is owned by pg_database_owner (PG 15+), and the migrator is that owner.
#
# So provisioning is "CREATE DATABASE, then run the script the repo already
# has" — the grant model is never restated here. That matters: duplicating
# the least-privilege grants in this file is exactly the drift risk that
# argued against per-worktree *schemas*, which would have needed their own
# GRANT USAGE and ALTER DEFAULT PRIVILEGES per worktree.
#
# Role creation (section 1 of that script) is a no-op here: roles are
# cluster-scoped, so a database created in an already-provisioned cluster
# reuses the three roles that exist. Its `IF NOT EXISTS` guards make running
# it as a non-superuser safe.
#
# Idempotent, and cheap when there is nothing to do: the common case is one
# catalog lookup against the maintenance database, then exit.

require 'uri'

begin
  require 'pg'
rescue LoadError
  warn '[lane:pg] the `pg` gem is required to provision the test database; run `bundle install`'
  exit 69
end

module ProvisionPgDatabase
  # Mirrors the invariant initialize_test_db.sql enforces in SQL and
  # PostgresModeSuiteDatabase#clean_tables! enforces before TRUNCATE: this
  # script issues CREATE DATABASE and runs a script that drops a schema, so
  # it refuses to address anything not obviously a test database.
  TEST_NAME = /test/i.freeze

  INIT_SQL = File.join(
    'apps', 'web', 'auth', 'migrations', 'schemas', 'postgres', 'initialize_test_db.sql'
  ).freeze

  class << self
    def run(url)
      uri    = URI.parse(url)
      dbname = uri.path.to_s.delete_prefix('/')

      abort "[lane:pg] refusing to provision non-test database #{dbname.inspect}" unless dbname.match?(TEST_NAME)

      # Everything below runs under an advisory lock keyed on the database
      # name, because two lane runs starting together genuinely race — the
      # forest this feature exists for is exactly where that happens.
      #
      # The lock is not just about CREATE DATABASE colliding (which raises
      # either duplicate_database or a unique violation on
      # pg_database_datname_index, depending on how tight the race is). The
      # damaging window is wider: between CREATE and the end of the init
      # script the database exists but has no grants, so a loser that merely
      # checked existence would hand its specs a half-provisioned database.
      # Holding the lock across check-create-initialize closes that window;
      # the loser blocks, then observes a finished database and returns.
      #
      # hashtext() rather than a Ruby-side hash: String#hash is salted per
      # process, so two runners would derive different keys and never
      # contend. Advisory locks are session-scoped, and the session ends with
      # the connection, so a killed runner cannot wedge the lock.
      with_maintenance(uri) do |conn|
        conn.exec_params('SELECT pg_advisory_lock(hashtext($1))', [dbname])
        begin
          return if exists?(conn, dbname)

          create!(conn, dbname)
          begin
            initialize!(uri, dbname)
          rescue StandardError
            # A database that exists but never got its grants would be
            # treated as provisioned by every later run. Drop it so the
            # next attempt starts clean, then report the original failure.
            drop!(conn, dbname)
            raise
          end
          warn "[lane:pg] provisioned #{dbname}"
        ensure
          conn.exec_params('SELECT pg_advisory_unlock(hashtext($1))', [dbname])
        end
      end
    end

    private

    # Connection parameters for `uri`, pointed at `database`.
    def params(uri, database)
      {
        host: uri.host,
        port: uri.port,
        user: uri.user && URI.decode_www_form_component(uri.user),
        password: uri.password && URI.decode_www_form_component(uri.password),
        dbname: database,
      }.compact
    end

    # The maintenance database is addressed for catalog lookups and CREATE
    # DATABASE, which cannot run inside the database being created.
    def with_maintenance(uri)
      conn = PG.connect(**params(uri, 'postgres'))
      yield conn
    ensure
      conn&.close
    end

    def exists?(conn, dbname)
      conn.exec_params('SELECT 1 FROM pg_database WHERE datname = $1', [dbname]).ntuples.positive?
    end

    def create!(conn, dbname)
      conn.exec("CREATE DATABASE #{conn.quote_ident(dbname)}")
    end

    def drop!(conn, dbname)
      conn.exec("DROP DATABASE IF EXISTS #{conn.quote_ident(dbname)}")
    rescue PG::Error
      # Reporting the provisioning failure matters more than this cleanup.
      nil
    end

    # Run the repo's provisioning script against the new database. Multiple
    # statements in one exec is deliberate — the file is plain SQL with DO
    # blocks and no psql meta-commands, so it needs no client-side splitting.
    def initialize!(uri, dbname)
      sql  = File.read(INIT_SQL)
      conn = PG.connect(**params(uri, dbname))
      conn.exec(sql)
    ensure
      conn&.close
    end
  end
end

url = ENV['AUTH_DATABASE_URL_MIGRATIONS'].to_s
if url.empty?
  warn '[lane:pg] AUTH_DATABASE_URL_MIGRATIONS is unset; cannot provision'
  exit 69
end

begin
  ProvisionPgDatabase.run(url)
rescue PG::Error => e
  warn "[lane:pg] provisioning failed: #{e.message.strip}"
  exit 69
end
