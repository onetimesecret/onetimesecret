# apps/web/auth/spec/operations/read_webauthn_credentials_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::ReadWebauthnCredentials (#4414).
#
# The operation projects rows from account_webauthn_keys into the shape
# Onetime::ReauthPolicy consumes — { scope: :platform } or
# { scope: :tenant, id: <domain_id> } — reading the surface_scope column
# added by migration 009. Every branch of the shape decoder is covered
# here: NULL (legacy), a canonical/subdomain descriptor, a custom
# descriptor with and without an id, and unparseable JSON.

require 'spec_helper'
require_relative '../../operations/read_webauthn_credentials'

RSpec.describe Auth::Operations::ReadWebauthnCredentials do
  # Minimal in-memory Sequel dataset stub. The operation calls
  # `.where(account_id: …).select(:surface_scope).all`, so this
  # simulates only that chain.
  class FakeDataset
    def initialize(rows_by_account = {})
      @rows_by_account = rows_by_account
      @filtered        = nil
    end

    def where(account_id:)
      @filtered = @rows_by_account.fetch(account_id, [])
      self
    end

    def select(_col)
      self
    end

    def all
      @filtered || []
    end
  end

  class FakeDb
    def initialize(rows_by_account = {})
      @ds = FakeDataset.new(rows_by_account)
    end

    def [](table)
      raise "unexpected table #{table}" unless table == :account_webauthn_keys

      @ds
    end
  end

  let(:db) { FakeDb.new(rows_by_account) }
  let(:op) { described_class.new(db) }

  describe '#call' do
    context 'with no credentials registered' do
      let(:rows_by_account) { {} }

      it 'returns []' do
        expect(op.call(42)).to eq([])
      end
    end

    context 'with a legacy row (NULL surface_scope)' do
      let(:rows_by_account) { { 42 => [{ surface_scope: nil }] } }

      it 'reads as { scope: :platform } (matches ReauthPolicy legacy default)' do
        expect(op.call(42)).to eq([{ scope: :platform }])
      end
    end

    context 'with a legacy row (empty-string surface_scope)' do
      let(:rows_by_account) { { 42 => [{ surface_scope: '' }] } }

      it 'reads as { scope: :platform }' do
        expect(op.call(42)).to eq([{ scope: :platform }])
      end
    end

    context 'with a canonical descriptor row' do
      let(:rows_by_account) do
        { 42 => [{ surface_scope: JSON.generate({ kind: 'canonical' }) }] }
      end

      it 'reads as { scope: :platform }' do
        expect(op.call(42)).to eq([{ scope: :platform }])
      end
    end

    context 'with a subdomain descriptor row' do
      let(:rows_by_account) do
        {
          42 => [
            { surface_scope: JSON.generate({ kind: 'subdomain', host: 'eu.example.com' }) },
          ],
        }
      end

      it 'reads as { scope: :platform } (subdomain shares canonical treatment today)' do
        expect(op.call(42)).to eq([{ scope: :platform }])
      end
    end

    context 'with a custom descriptor row carrying a domain id' do
      let(:rows_by_account) do
        {
          42 => [
            { surface_scope: JSON.generate({ kind: 'custom', id: 'tenant-a' }) },
          ],
        }
      end

      it 'reads as { scope: :tenant, id: "tenant-a" }' do
        expect(op.call(42)).to eq([{ scope: :tenant, id: 'tenant-a' }])
      end
    end

    context 'with a custom descriptor row missing its id (blip)' do
      let(:rows_by_account) do
        { 42 => [{ surface_scope: JSON.generate({ kind: 'custom' }) }] }
      end

      it 'reads as { scope: :platform } — a scopeless custom is not a tenant credential' do
        expect(op.call(42)).to eq([{ scope: :platform }])
      end
    end

    context 'with an unparseable surface_scope value' do
      let(:rows_by_account) do
        { 42 => [{ surface_scope: '{ not json' }] }
      end

      it 'reads as { scope: :platform } — unparseable falls back to the safe default' do
        expect(op.call(42)).to eq([{ scope: :platform }])
      end
    end

    context 'with a JSON scalar (not an object) in surface_scope' do
      let(:rows_by_account) do
        { 42 => [{ surface_scope: JSON.generate('canonical') }] }
      end

      it 'reads as { scope: :platform }' do
        expect(op.call(42)).to eq([{ scope: :platform }])
      end
    end

    context 'with a mixed cohort of platform, tenant, and legacy rows' do
      let(:rows_by_account) do
        {
          42 => [
            { surface_scope: nil },
            { surface_scope: JSON.generate({ kind: 'canonical' }) },
            { surface_scope: JSON.generate({ kind: 'custom', id: 'tenant-a' }) },
            { surface_scope: JSON.generate({ kind: 'custom', id: 'tenant-b' }) },
          ],
        }
      end

      it 'projects each row into its policy-shaped descriptor, preserving order' do
        expect(op.call(42)).to eq([
          { scope: :platform },
          { scope: :platform },
          { scope: :tenant, id: 'tenant-a' },
          { scope: :tenant, id: 'tenant-b' },
        ])
      end
    end

    context 'edge cases at the boundary' do
      let(:rows_by_account) { {} }

      it 'returns [] for a nil account_id (no unnecessary query)' do
        expect(op.call(nil)).to eq([])
      end

      it 'coerces a string account_id to Integer for the WHERE clause' do
        db_with_int_key = FakeDb.new(42 => [{ surface_scope: nil }])
        expect(described_class.new(db_with_int_key).call('42')).to eq([{ scope: :platform }])
      end

      it 'fails closed to [] on any StandardError during the read' do
        broken_db = Object.new
        def broken_db.[](_table); raise 'boom'; end

        expect(described_class.new(broken_db).call(42)).to eq([])
      end
    end
  end
end
