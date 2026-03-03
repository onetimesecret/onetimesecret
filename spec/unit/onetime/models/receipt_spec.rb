# spec/unit/onetime/models/receipt_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Unit tests for Receipt.spawn_pair
#
# These tests verify that spawn_pair creates a properly linked
# receipt+secret pair with all fields populated from a single
# persistence operation on the receipt.
#
# BUG: The current implementation calls receipt.save TWICE -- once
# before receipt-level fields (secret_ttl, kind, lifespan, share_domain)
# are set, and again after. This means:
#   1. There is a race window where a crash between saves leaves
#      a receipt in Redis missing those fields.
#   2. The first save is wasted work (writes incomplete data).
#
# These tests are written TDD-style: they SHOULD FAIL against the
# current (buggy) code, and pass once the fix is applied.
#
RSpec.describe Onetime::Receipt do
  describe '.spawn_pair' do
    let(:owner_id)   { 'testuser@example.com' }
    let(:lifespan)   { 86_400 } # 1 day in seconds
    let(:content)    { 'super secret content' }
    let(:domain)     { 'secrets.example.com' }
    let(:kind)       { 'share' }

    # Stubs for Redis-backed operations that spawn_pair touches.
    # We allow real Ruby field assignment but intercept persistence.
    before do
      # Stub save on any Receipt or Secret instance so nothing hits Redis.
      allow_any_instance_of(Onetime::Receipt).to receive(:save).and_return(true)
      allow_any_instance_of(Onetime::Secret).to receive(:save).and_return(true)

      # The ciphertext= setter is an encrypted_field that triggers Familia's
      # encryption pipeline, requiring key version config. Stub it to no-op
      # since we're testing receipt field population, not encryption.
      allow_any_instance_of(Onetime::Secret).to receive(:ciphertext=).and_return(nil)

      # update_passphrase writes passphrase fields; stub it to be a no-op
      # but still allow the receipt's has_passphrase to be set by spawn_pair.
      allow_any_instance_of(Onetime::Secret).to receive(:update_passphrase).and_return(true)

      # register_for_expiration_notifications touches class-level sorted sets
      allow_any_instance_of(Onetime::Receipt).to receive(:register_for_expiration_notifications).and_return(false)
    end

    # -----------------------------------------------------------
    # 1. Single save: receipt.save should be called exactly once
    # -----------------------------------------------------------
    # This is the core TDD test for the bug. The current code calls
    # save twice on the receipt; the fix should reduce it to one.
    context 'receipt persistence' do
      it 'calls save on the receipt exactly once' do
        receipt_double = instance_double(Onetime::Receipt).as_null_object
        allow(receipt_double).to receive(:save).and_return(true)
        allow(receipt_double).to receive(:register_for_expiration_notifications).and_return(false)
        allow(Onetime::Receipt).to receive(:new).and_return(receipt_double)

        secret_double = instance_double(Onetime::Secret).as_null_object
        allow(secret_double).to receive(:save).and_return(true)
        allow(secret_double).to receive(:objid).and_return('secret-objid-abc123')
        allow(secret_double).to receive(:shortid).and_return('secret-o')
        allow(Onetime::Secret).to receive(:new).and_return(secret_double)

        Onetime::Receipt.spawn_pair(owner_id, lifespan, content, domain: domain, kind: kind)

        expect(receipt_double).to have_received(:save).once
      end
    end

    # -----------------------------------------------------------
    # 2. Field completeness
    # -----------------------------------------------------------
    context 'receipt field population' do
      subject(:pair) do
        Onetime::Receipt.spawn_pair(
          owner_id, lifespan, content,
          domain: domain, kind: kind
        )
      end

      let(:receipt) { pair[0] }
      let(:secret)  { pair[1] }

      it 'sets secret_identifier to the secret objid' do
        expect(receipt.secret_identifier).to eq(secret.objid)
      end

      it 'sets secret_shortid to the secret shortid' do
        expect(receipt.secret_shortid).to eq(secret.shortid)
      end

      it 'sets secret_ttl to the lifespan argument' do
        expect(receipt.secret_ttl.to_i).to eq(lifespan)
      end

      it 'sets lifespan to the lifespan argument' do
        expect(receipt.lifespan.to_i).to eq(lifespan)
      end

      it 'sets share_domain to the domain argument' do
        expect(receipt.share_domain).to eq(domain)
      end

      it 'sets kind to the kind argument' do
        expect(receipt.kind).to eq(kind)
      end
    end

    context 'when a passphrase is provided' do
      subject(:pair) do
        Onetime::Receipt.spawn_pair(
          owner_id, lifespan, content,
          passphrase: 'hunter2', domain: domain, kind: kind
        )
      end

      let(:receipt) { pair[0] }

      it 'sets has_passphrase on the receipt' do
        expect(receipt.has_passphrase).to be true
      end
    end

    context 'when no passphrase is provided' do
      subject(:pair) do
        Onetime::Receipt.spawn_pair(
          owner_id, lifespan, content,
          domain: domain, kind: kind
        )
      end

      let(:receipt) { pair[0] }

      it 'does not set has_passphrase on the receipt' do
        expect(receipt.has_passphrase).to be_nil
      end
    end

    # -----------------------------------------------------------
    # 3. Mutual linking
    # -----------------------------------------------------------
    context 'mutual linking between receipt and secret' do
      subject(:pair) do
        Onetime::Receipt.spawn_pair(owner_id, lifespan, content, domain: domain, kind: kind)
      end

      let(:receipt) { pair[0] }
      let(:secret)  { pair[1] }

      it 'links receipt.secret_identifier to secret.objid' do
        expect(receipt.secret_identifier).to eq(secret.objid)
      end

      it 'links secret.receipt_identifier to receipt.objid' do
        expect(secret.receipt_identifier).to eq(receipt.objid)
      end
    end

    # -----------------------------------------------------------
    # 4. Return value
    # -----------------------------------------------------------
    context 'return value' do
      subject(:pair) do
        Onetime::Receipt.spawn_pair(owner_id, lifespan, content, domain: domain, kind: kind)
      end

      it 'returns a two-element array' do
        expect(pair).to be_an(Array)
        expect(pair.size).to eq(2)
      end

      it 'returns a Receipt as the first element' do
        expect(pair[0]).to be_a(Onetime::Receipt)
      end

      it 'returns a Secret as the second element' do
        expect(pair[1]).to be_a(Onetime::Secret)
      end
    end

    # -----------------------------------------------------------
    # 5. All receipt fields set BEFORE save is called
    # -----------------------------------------------------------
    # This test captures the essence of the bug: the receipt should
    # have all its fields populated at the time save is called, not
    # after a prior incomplete save. We capture the FIRST save's
    # state -- with the bug, the first save has nil for all
    # receipt-level fields.
    context 'field completeness at save time' do
      it 'has all fields populated on the first save call' do
        first_save_fields = nil

        allow_any_instance_of(Onetime::Receipt).to receive(:save) do |receipt_instance|
          # Only capture the FIRST save invocation's state.
          # With the bug, this will have nil for secret_ttl, kind, etc.
          first_save_fields ||= {
            secret_ttl: receipt_instance.instance_variable_get(:@secret_ttl),
            lifespan: receipt_instance.instance_variable_get(:@lifespan),
            share_domain: receipt_instance.instance_variable_get(:@share_domain),
            kind: receipt_instance.instance_variable_get(:@kind),
            secret_shortid: receipt_instance.instance_variable_get(:@secret_shortid),
            secret_identifier: receipt_instance.instance_variable_get(:@secret_identifier),
          }
          true
        end

        # Secret save is also stubbed (ciphertext= is handled by global before)
        allow_any_instance_of(Onetime::Secret).to receive(:save).and_return(true)
        allow_any_instance_of(Onetime::Secret).to receive(:update_passphrase).and_return(true)
        allow_any_instance_of(Onetime::Receipt).to receive(:register_for_expiration_notifications).and_return(false)

        Onetime::Receipt.spawn_pair(owner_id, lifespan, content, domain: domain, kind: kind)

        # The first (and ideally only) save should have all fields populated.
        expect(first_save_fields[:secret_ttl]).to eq(lifespan)
        expect(first_save_fields[:lifespan]).to eq(lifespan)
        expect(first_save_fields[:share_domain]).to eq(domain)
        expect(first_save_fields[:kind]).to eq(kind)
        expect(first_save_fields[:secret_shortid]).not_to be_nil
        expect(first_save_fields[:secret_identifier]).not_to be_nil
      end
    end

    # -----------------------------------------------------------
    # 6. First save should not persist incomplete receipt
    # -----------------------------------------------------------
    # Directly tests that the FIRST call to save already has all
    # receipt-level fields set. With the bug, the first save has
    # nil for secret_ttl, kind, lifespan, share_domain.
    context 'no incomplete save' do
      it 'does not persist a receipt with nil secret_ttl' do
        save_call_fields = []

        allow_any_instance_of(Onetime::Receipt).to receive(:save) do |receipt_instance|
          save_call_fields << {
            secret_ttl: receipt_instance.instance_variable_get(:@secret_ttl),
            kind: receipt_instance.instance_variable_get(:@kind),
            lifespan: receipt_instance.instance_variable_get(:@lifespan),
            share_domain: receipt_instance.instance_variable_get(:@share_domain),
          }
          true
        end

        allow_any_instance_of(Onetime::Secret).to receive(:save).and_return(true)
        allow_any_instance_of(Onetime::Secret).to receive(:update_passphrase).and_return(true)
        allow_any_instance_of(Onetime::Receipt).to receive(:register_for_expiration_notifications).and_return(false)

        Onetime::Receipt.spawn_pair(owner_id, lifespan, content, domain: domain, kind: kind)

        # Every save call should have secret_ttl populated.
        # With the bug, save_call_fields[0][:secret_ttl] is nil.
        save_call_fields.each_with_index do |fields, idx|
          expect(fields[:secret_ttl]).to eq(lifespan),
            "save call ##{idx + 1}: expected secret_ttl=#{lifespan}, got #{fields[:secret_ttl].inspect}"
          expect(fields[:kind]).to eq(kind),
            "save call ##{idx + 1}: expected kind=#{kind.inspect}, got #{fields[:kind].inspect}"
          expect(fields[:lifespan]).to eq(lifespan),
            "save call ##{idx + 1}: expected lifespan=#{lifespan}, got #{fields[:lifespan].inspect}"
          expect(fields[:share_domain]).to eq(domain),
            "save call ##{idx + 1}: expected share_domain=#{domain.inspect}, got #{fields[:share_domain].inspect}"
        end
      end
    end
  end
end
