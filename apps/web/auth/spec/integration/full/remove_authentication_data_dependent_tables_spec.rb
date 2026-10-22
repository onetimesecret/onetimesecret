# apps/web/auth/spec/integration/full/remove_authentication_data_dependent_tables_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode)
# =============================================================================
#
# RemoveAuthenticationData::DEPENDENT_TABLES is a hand-maintained list of the
# tables with a foreign key to accounts.id, in delete order, and
# ACCOUNT_ID_KEYED_TABLES names the ones whose key column is :account_id.
# Account closure (#4819) deletes through that list as the last statements of
# Rodauth's close_account transaction, so a table missing from it fails the
# accounts delete on the foreign key and rolls the closure back. This file
# derives the same facts from the migrated schema and holds the list to them,
# on whichever engine the lane runs (`full-sqlite`, `full-pg-agnostic`).
#
# The test factory keeps its own table list for cleanup
# (AuthAccountFactory::RODAUTH_TABLES); the last example keeps it in step,
# allowing only tables whose foreign key cascades to be left out.
# =============================================================================

require_relative '../../spec_helper'
require_relative '../../../../../../spec/support/factories/auth_account_factory'

RSpec.describe 'RemoveAuthenticationData::DEPENDENT_TABLES against the schema', type: :integration do
  before(:all) do
    require 'onetime' unless defined?(Onetime)
    Onetime.boot! :test unless Onetime.ready?
    require 'auth/operations/remove_authentication_data'
  end

  let(:db) { Auth::Database.connection }
  let(:operation) { Auth::Operations::RemoveAuthenticationData }

  # {table => {column:, on_delete:}} for every table with a foreign key to
  # accounts, read from the schema.
  let(:referencing) do
    db.tables.each_with_object({}) do |table, map|
      next if table == :accounts

      db.foreign_key_list(table).each do |fk|
        next unless fk[:table].to_s == 'accounts'

        map[table] = { column: fk[:columns].first, on_delete: fk[:on_delete] }
      end
    end
  end

  it 'finds the foreign keys it is checking against' do
    expect(referencing).to include(:account_authentication_audit_logs, :account_password_hashes)
  end

  it 'lists every table with a foreign key to accounts, and nothing else' do
    expect(operation::DEPENDENT_TABLES.sort).to eq(referencing.keys.sort)
  end

  it 'names the referencing column of every table' do
    referencing.each do |table, fk|
      expect(operation.fk_column_for(table)).to eq(fk[:column]),
        "#{table} references accounts through #{fk[:column]}, not #{operation.fk_column_for(table)}"
    end
  end

  # One catalog read per closure replaces 22 table_exists? probes (each a
  # savepoint inside the open transaction); the result must be the full list
  # on a migrated schema, in delete order, minus whatever the caller excepts.
  it 'resolves the present tables from one catalog read, in list order, honoring except:' do
    expect(operation.existing_dependent_tables(db)).to eq(operation::DEPENDENT_TABLES)
    expect(operation.existing_dependent_tables(db, except: [:account_authentication_audit_logs]))
      .to eq(operation::DEPENDENT_TABLES - [:account_authentication_audit_logs])
  end

  it 'keeps the test factory table list in step, cascading tables excepted' do
    missing = referencing.keys - AuthAccountFactory::RODAUTH_TABLES
    missing.each do |table|
      expect(referencing[table][:on_delete]).to eq(:cascade),
        "#{table} does not cascade and is missing from AuthAccountFactory::RODAUTH_TABLES"
    end
    expect(AuthAccountFactory::RODAUTH_TABLES - [:accounts] - referencing.keys).to be_empty
  end
end
