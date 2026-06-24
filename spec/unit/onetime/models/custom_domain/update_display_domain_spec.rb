# spec/unit/onetime/models/custom_domain/update_display_domain_spec.rb
#
# frozen_string_literal: true

# Coverage gap: the instance method `update_display_domain` re-parses via
# PublicSuffix.parse directly (line 196) and does NOT go through the
# class-level methods that call `contains_control_chars?`.
#
# The control-character tests are expected to FAIL (red-phase) until a
# guard is added to `update_display_domain`. The sanity / trailing-dot
# tests are expected to PASS, proving the harness itself is sound.

require 'spec_helper'

RSpec.describe Onetime::CustomDomain, '#update_display_domain' do
  # Build a minimal CustomDomain instance with enough stubs to reach the
  # PublicSuffix.parse call at line 196 without hitting Redis.
  let(:domain) do
    cd = described_class.new
    cd.instance_variable_set(:@display_domain, 'old.example.com')
    cd.instance_variable_set(:@org_id, 'org-test-001')
    cd.instance_variable_set(:@base_domain, 'example.com')
    cd.instance_variable_set(:@trd, 'old')
    cd.instance_variable_set(:@tld, 'com')
    cd.instance_variable_set(:@sld, 'example')

    # Stub Redis-touching operations so this stays a unit test
    index_double = instance_double('Familia::UniqueIndex',
                                   get: nil, remove: nil, put: nil)
    allow(described_class).to receive(:display_domain_index).and_return(index_double)
    allow(cd).to receive(:remove_from_class_display_domain_index)
    allow(cd).to receive(:save).and_return(true)
    allow(cd).to receive(:identifier).and_return('cd-test-id')

    cd
  end

  # ------------------------------------------------------------------ #
  # Sanity checks — expected GREEN (proves the harness works)
  # ------------------------------------------------------------------ #

  context 'with a normal domain update' do
    it 'updates display_domain to the new value' do
      domain.update_display_domain('new.example.com')
      expect(domain.display_domain).to eq('new.example.com')
    end

    it 'updates base_domain from the new value' do
      domain.update_display_domain('sub.otherdomain.org')
      expect(domain.instance_variable_get(:@base_domain)).to eq('otherdomain.org')
    end

    it 'calls save' do
      domain.update_display_domain('new.example.com')
      expect(domain).to have_received(:save)
    end
  end

  # ------------------------------------------------------------------ #
  # Trailing dot normalization — expected GREEN (regression guard)
  #
  # PublicSuffix.parse strips the trailing dot, so derived fields should
  # be clean even though the raw display_domain stores what was passed.
  # ------------------------------------------------------------------ #

  context 'with a trailing dot' do
    it 'parses base_domain without the trailing dot' do
      domain.update_display_domain('sub.example.com.')
      expect(domain.instance_variable_get(:@base_domain)).to eq('example.com')
    end

    it 'does not raise' do
      expect { domain.update_display_domain('sub.example.com.') }.not_to raise_error
    end
  end

  # ------------------------------------------------------------------ #
  # Control characters — expected RED (the coverage gap)
  #
  # update_display_domain passes input directly to PublicSuffix.parse
  # without calling contains_control_chars?. These tests document the
  # gap: they should raise Onetime::Problem but currently do not.
  # ------------------------------------------------------------------ #

  context 'with a null byte' do
    it 'rejects a domain containing a null byte' do
      expect {
        domain.update_display_domain("new\x00.example.com")
      }.to raise_error(Onetime::Problem)
    end
  end

  context 'with control characters' do
    it 'rejects SOH (0x01)' do
      expect {
        domain.update_display_domain("new\x01.example.com")
      }.to raise_error(Onetime::Problem)
    end

    it 'rejects TAB (0x09)' do
      expect {
        domain.update_display_domain("new\t.example.com")
      }.to raise_error(Onetime::Problem)
    end

    it 'rejects LF (0x0A)' do
      expect {
        domain.update_display_domain("new\n.example.com")
      }.to raise_error(Onetime::Problem)
    end

    it 'rejects DEL (0x7F)' do
      expect {
        domain.update_display_domain("new\x7F.example.com")
      }.to raise_error(Onetime::Problem)
    end
  end
end
