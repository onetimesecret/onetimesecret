# spec/unit/onetime/session/reauth_policy_spec.rb
#
# frozen_string_literal: true

# Unit tests for Onetime::ReauthPolicy — the surface-aware policy that
# answers which credential paths may be OFFERED for re-authentication on
# THIS request's surface (#4414, epic #4408). Every acceptance criterion
# from the issue lands here: password fallback, platform-only credential
# on tenant refused, tenant credential accepted, related-origins
# enabled/disabled cases, and fail-closed on an unresolved surface.

require 'spec_helper'
require 'onetime/session/reauth_policy'
require 'onetime/session/surface'

RSpec.describe Onetime::ReauthPolicy do
  let(:canonical) { { kind: :canonical } }
  let(:subdomain) { { kind: :subdomain, host: 'eu.example.com' } }
  let(:tenant_a)  { { kind: :custom, id: 'tenant-a' } }
  let(:tenant_b)  { { kind: :custom, id: 'tenant-b' } }

  let(:platform_credential) { { scope: :platform } }
  let(:tenant_a_credential) { { scope: :tenant, id: 'tenant-a', rp_id: 'tenant-a.example' } }
  let(:tenant_b_credential) { { scope: :tenant, id: 'tenant-b', rp_id: 'tenant-b.example' } }
  let(:canonical_member) { { origin: 'https://example.com', surface: canonical } }
  let(:tenant_a_member) { { origin: 'https://tenant-a.example', surface: tenant_a } }

  describe '.eligible_methods' do
    context 'password fallback' do
      it 'offers password when the install permits it, regardless of surface' do
        result = described_class.eligible_methods(
          tenant_a,
          password_enabled: true,
          webauthn_credentials: [],
        )
        expect(result).to eq(%w[password])
      end

      it 'omits password when the install disables it' do
        result = described_class.eligible_methods(
          canonical,
          password_enabled: false,
          webauthn_credentials: [platform_credential],
        )
        expect(result).to eq(%w[webauthn])
      end

      it 'orders webauthn before password when both are eligible' do
        result = described_class.eligible_methods(
          canonical,
          password_enabled: true,
          webauthn_credentials: [platform_credential],
        )
        expect(result).to eq(%w[webauthn password])
      end

      it 'returns a frozen array so callers cannot mutate the offered set' do
        result = described_class.eligible_methods(
          canonical,
          password_enabled: true,
          webauthn_credentials: [],
        )
        expect(result).to be_frozen
      end
    end

    context 'platform-only credential on a tenant host' do
      it 'refuses to offer WebAuthn on a :custom surface for a platform-only credential' do
        result = described_class.eligible_methods(
          tenant_a,
          password_enabled: true,
          webauthn_credentials: [platform_credential],
        )
        expect(result).not_to include('webauthn')
      end

      it 'refuses to offer WebAuthn on a :subdomain surface for a platform-only credential' do
        result = described_class.eligible_methods(
          subdomain,
          password_enabled: true,
          webauthn_credentials: [platform_credential],
        )
        expect(result).not_to include('webauthn')
      end

      it 'still offers password so the user has a supported path' do
        result = described_class.eligible_methods(
          tenant_a,
          password_enabled: true,
          webauthn_credentials: [platform_credential],
        )
        expect(result).to eq(%w[password])
      end

      it 'treats a credential with no :scope as :platform (legacy default)' do
        legacy = { id: 'legacy-credential' }
        result = described_class.eligible_methods(
          tenant_a,
          password_enabled: false,
          webauthn_credentials: [legacy],
        )
        expect(result).to eq([])
      end

      it 'treats an unknown scope symbol as :platform (unknown reads as canonical-only)' do
        result = described_class.eligible_methods(
          tenant_a,
          password_enabled: false,
          webauthn_credentials: [{ scope: :something_new }],
        )
        expect(result).to eq([])
      end
    end

    context 'exact registration RP matching' do
      it 'offers a credential registered on a canonical subdomain on that subdomain' do
        result = described_class.eligible_methods(
          subdomain,
          password_enabled: false,
          webauthn_credentials: [{ scope: :subdomain, host: 'eu.example.com', rp_id: 'eu.example.com' }],
          current_origin: 'https://eu.example.com',
        )
        expect(result).to eq(%w[webauthn])
      end

      it 'does not reclassify a subdomain credential as platform-wide' do
        result = described_class.eligible_methods(
          canonical,
          password_enabled: false,
          webauthn_credentials: [{ scope: :subdomain, host: 'eu.example.com', rp_id: 'eu.example.com' }],
          current_origin: 'https://example.com',
        )
        expect(result).to eq([])
      end

      it 'refuses a scoped credential when its stored RP ID differs from the current host' do
        result = described_class.eligible_methods(
          tenant_a,
          password_enabled: false,
          webauthn_credentials: [tenant_a_credential.merge(rp_id: 'old.example')],
          current_origin: 'https://tenant-a.example',
        )
        expect(result).to eq([])
      end
    end

    context 'tenant-registered credential on its own tenant host' do
      it 'offers WebAuthn on the :custom surface a tenant credential is scoped to' do
        result = described_class.eligible_methods(
          tenant_a,
          password_enabled: false,
          webauthn_credentials: [tenant_a_credential],
          current_origin: 'https://tenant-a.example',
        )
        expect(result).to eq(%w[webauthn])
      end

      it 'refuses to offer a tenant credential on a DIFFERENT tenant host' do
        result = described_class.eligible_methods(
          tenant_b,
          password_enabled: false,
          webauthn_credentials: [tenant_a_credential],
        )
        expect(result).to eq([])
      end

      it 'refuses to offer a tenant credential on the canonical host' do
        result = described_class.eligible_methods(
          canonical,
          password_enabled: false,
          webauthn_credentials: [tenant_a_credential],
        )
        expect(result).to eq([])
      end

      it 'accepts a stringified scope on a tenant credential (Hash serialization tolerance)' do
        credential = { 'scope' => :tenant, 'id' => 'tenant-a', 'rp_id' => 'tenant-a.example' }
        result     = described_class.eligible_methods(
          tenant_a,
          password_enabled: false,
          webauthn_credentials: [credential],
          current_origin: 'https://tenant-a.example',
        )
        expect(result).to eq(%w[webauthn])
      end

      it 'refuses to offer a tenant credential with a blank id' do
        credential = { scope: :tenant, id: '' }
        result     = described_class.eligible_methods(
          tenant_a,
          password_enabled: false,
          webauthn_credentials: [credential],
        )
        expect(result).to eq([])
      end

      it 'refuses to offer a tenant credential on a :subdomain surface' do
        result = described_class.eligible_methods(
          subdomain,
          password_enabled: false,
          webauthn_credentials: [tenant_a_credential],
        )
        expect(result).to eq([])
      end

      it 'combines platform and tenant credentials — canonical still gets the platform credential' do
        result = described_class.eligible_methods(
          canonical,
          password_enabled: false,
          webauthn_credentials: [platform_credential, tenant_a_credential],
        )
        expect(result).to eq(%w[webauthn])
      end

      it 'combines platform and tenant credentials — tenant surface uses only its own tenant credential' do
        result = described_class.eligible_methods(
          tenant_a,
          password_enabled: false,
          webauthn_credentials: [platform_credential, tenant_a_credential],
          current_origin: 'https://tenant-a.example',
        )
        expect(result).to eq(%w[webauthn])
      end
    end

    context 'related origins configured' do
      it 'offers a platform-registered credential on a tenant host when canonical is a declared related origin' do
        result = described_class.eligible_methods(
          tenant_a,
          password_enabled: false,
          webauthn_credentials: [platform_credential.merge(rp_id: 'example.com')],
          related_origins: [canonical_member, tenant_a_member],
          current_origin: 'https://tenant-a.example',
        )
        expect(result).to eq(%w[webauthn])
      end

      it 'offers a tenant-registered credential on canonical when the tenant is a declared related origin' do
        result = described_class.eligible_methods(
          canonical,
          password_enabled: false,
          webauthn_credentials: [tenant_a_credential],
          related_origins: [canonical_member, tenant_a_member],
          current_origin: 'https://example.com',
        )
        expect(result).to eq(%w[webauthn])
      end

      it 'refuses related-origin widening without stored RP provenance' do
        result = described_class.eligible_methods(
          tenant_a,
          password_enabled: false,
          webauthn_credentials: [platform_credential],
          related_origins: [canonical_member, tenant_a_member],
          current_origin: 'https://tenant-a.example',
        )
        expect(result).to eq([])
      end

      it 'refuses a related-origins acceptance when the current surface is not in the declared set' do
        result = described_class.eligible_methods(
          tenant_b,
          password_enabled: false,
          webauthn_credentials: [platform_credential.merge(rp_id: 'example.com')],
          related_origins: [canonical_member, tenant_a_member],
          current_origin: 'https://tenant-b.example',
        )
        expect(result).to eq([])
      end

      it 'refuses when no credential matches any DECLARED origin, even with related origins configured' do
        result = described_class.eligible_methods(
          tenant_a,
          password_enabled: false,
          webauthn_credentials: [tenant_b_credential],
          related_origins: [canonical_member, tenant_a_member],
          current_origin: 'https://tenant-a.example',
        )
        expect(result).to eq([])
      end

      it 'refuses a credential whose stored RP ID does not identify its registration member' do
        result = described_class.eligible_methods(
          tenant_a,
          password_enabled: false,
          webauthn_credentials: [platform_credential.merge(rp_id: 'wrong.example')],
          related_origins: [canonical_member, tenant_a_member],
          current_origin: 'https://tenant-a.example',
        )
        expect(result).to eq([])
      end

      it 'does not discard scheme or port when matching the current origin' do
        result = described_class.eligible_methods(
          tenant_a,
          password_enabled: false,
          webauthn_credentials: [platform_credential.merge(rp_id: 'example.com')],
          related_origins: [canonical_member, tenant_a_member.merge(origin: 'https://tenant-a.example:8443')],
          current_origin: 'https://tenant-a.example',
        )
        expect(result).to eq([])
      end
    end

    context 'related origins NOT configured (empty or nil)' do
      it 'refuses a platform credential on a tenant host without related-origins' do
        result = described_class.eligible_methods(
          tenant_a,
          password_enabled: false,
          webauthn_credentials: [platform_credential],
          related_origins: [],
        )
        expect(result).to eq([])
      end

      it 'treats nil related_origins as no related-origins deployment' do
        result = described_class.eligible_methods(
          tenant_a,
          password_enabled: false,
          webauthn_credentials: [platform_credential],
          related_origins: nil,
        )
        expect(result).to eq([])
      end

      it 'defaults related_origins to empty when omitted' do
        result = described_class.eligible_methods(
          tenant_a,
          password_enabled: false,
          webauthn_credentials: [platform_credential],
        )
        expect(result).to eq([])
      end
    end

    context 'fail-closed on unresolved surface' do
      it 'returns [] when surface is nil (:invalid or unresolved :custom)' do
        result = described_class.eligible_methods(
          nil,
          password_enabled: true,
          webauthn_credentials: [platform_credential],
        )
        expect(result).to eq([])
      end

      it 'does NOT offer password fallback when the surface is unresolved' do
        result = described_class.eligible_methods(
          nil,
          password_enabled: true,
          webauthn_credentials: [],
        )
        expect(result).to eq([])
      end
    end

    context 'no credentials registered' do
      it 'returns [] when no credentials and no password' do
        result = described_class.eligible_methods(
          canonical,
          password_enabled: false,
          webauthn_credentials: [],
        )
        expect(result).to eq([])
      end

      it 'returns [password] when no credentials but password is enabled' do
        result = described_class.eligible_methods(
          canonical,
          password_enabled: true,
          webauthn_credentials: [],
        )
        expect(result).to eq(%w[password])
      end
    end
  end

  describe '.webauthn_offerable?' do
    it 'is true on canonical for a platform credential' do
      expect(described_class.webauthn_offerable?(canonical, [platform_credential], [])).to be true
    end

    it 'is false on tenant for a platform credential without related-origins' do
      expect(described_class.webauthn_offerable?(tenant_a, [platform_credential], [])).to be false
    end

    it 'is true on the matching tenant for a tenant credential with the current RP' do
      expect(
        described_class.webauthn_offerable?(
          tenant_a,
          [tenant_a_credential],
          [],
          current_origin: 'https://tenant-a.example',
        ),
      ).to be true
    end

    it 'is false when the credential array is empty' do
      expect(described_class.webauthn_offerable?(canonical, [], [canonical, tenant_a])).to be false
    end
  end

  describe '.credential_matches_surface?' do
    it 'matches a platform credential to the canonical surface' do
      expect(described_class.credential_matches_surface?(platform_credential, canonical)).to be true
    end

    it 'does not match a platform credential to a :subdomain surface' do
      expect(described_class.credential_matches_surface?(platform_credential, subdomain)).to be false
    end

    it 'does not match a platform credential to a :custom surface' do
      expect(described_class.credential_matches_surface?(platform_credential, tenant_a)).to be false
    end

    it 'matches a tenant credential only to the :custom surface with the same id' do
      expect(described_class.credential_matches_surface?(tenant_a_credential, tenant_a)).to be true
      expect(described_class.credential_matches_surface?(tenant_a_credential, tenant_b)).to be false
    end

    it 'does not match on a non-hash credential or surface' do
      expect(described_class.credential_matches_surface?(nil, canonical)).to be false
      expect(described_class.credential_matches_surface?(platform_credential, nil)).to be false
    end
  end

  describe 'METHODS constant' do
    it 'lists webauthn before password (renderer places password last)' do
      expect(described_class::METHODS).to eq(%w[webauthn password])
    end

    it 'is frozen' do
      expect(described_class::METHODS).to be_frozen
    end
  end
end
