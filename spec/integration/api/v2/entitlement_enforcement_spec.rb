# spec/integration/api/v2/entitlement_enforcement_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Integration tests for API V2 Entitlement Enforcement
#
# These tests verify that the require_entitlement! call is present in each
# protected logic class's raise_concerns method by reading the source files.
#
RSpec.describe 'API V2 Entitlement Enforcement', type: :integration do
  # Read a file and check if raise_concerns contains the entitlement check
  def file_has_entitlement_check?(relative_path)
    # Use the spec file location to find project root
    project_root = File.expand_path('../../../..', __dir__)
    full_path = File.join(project_root, relative_path)
    content = File.read(full_path)

    # Check that raise_concerns method contains require_entitlement!
    # Pattern: def raise_concerns followed by require_entitlement! before the next def or end
    raise_concerns_match = content.match(/def raise_concerns.*?(?=\n\s+def |\nend)/m)
    return false unless raise_concerns_match

    raise_concerns_match[0].include?("require_entitlement!('api_access')")
  end

  describe 'V2 Logic classes have entitlement checks' do
    it 'ListMetadata includes require_entitlement!' do
      expect(file_has_entitlement_check?('apps/api/v2/logic/secrets/list_metadata.rb')).to be true
    end

    it 'ShowMetadata includes require_entitlement!' do
      expect(file_has_entitlement_check?('apps/api/v2/logic/secrets/show_metadata.rb')).to be true
    end

    it 'BurnSecret includes require_entitlement!' do
      expect(file_has_entitlement_check?('apps/api/v2/logic/secrets/burn_secret.rb')).to be true
    end

    it 'RevealSecret includes require_entitlement!' do
      expect(file_has_entitlement_check?('apps/api/v2/logic/secrets/reveal_secret.rb')).to be true
    end

    it 'ShowSecret includes require_entitlement!' do
      expect(file_has_entitlement_check?('apps/api/v2/logic/secrets/show_secret.rb')).to be true
    end

    it 'ShowSecretStatus includes require_entitlement!' do
      expect(file_has_entitlement_check?('apps/api/v2/logic/secrets/show_secret_status.rb')).to be true
    end

    it 'ListSecretStatus includes require_entitlement!' do
      expect(file_has_entitlement_check?('apps/api/v2/logic/secrets/list_secret_status.rb')).to be true
    end

    it 'BaseSecretAction includes require_entitlement!' do
      expect(file_has_entitlement_check?('apps/api/v2/logic/secrets/base_secret_action.rb')).to be true
    end
  end

  describe 'V3 inherits from V2' do
    it 'V3::Logic::Secrets classes inherit entitlement enforcement from V2' do
      require 'v3/logic/secrets'

      # V3 classes inherit from V2, so they get entitlement checks automatically
      expect(V3::Logic::Secrets::ListMetadata.ancestors).to include(V2::Logic::Secrets::ListMetadata)
      expect(V3::Logic::Secrets::BurnSecret.ancestors).to include(V2::Logic::Secrets::BurnSecret)
      expect(V3::Logic::Secrets::ShowMetadata.ancestors).to include(V2::Logic::Secrets::ShowMetadata)
    end
  end

  describe 'BaseSecretAction subclass inheritance' do
    it 'ConcealSecret inherits from BaseSecretAction (gets entitlement check via super)' do
      require 'v2/logic/secrets/conceal_secret'
      expect(V2::Logic::Secrets::ConcealSecret.ancestors).to include(V2::Logic::Secrets::BaseSecretAction)
    end

    it 'GenerateSecret inherits from BaseSecretAction' do
      require 'v2/logic/secrets/generate_secret'
      expect(V2::Logic::Secrets::GenerateSecret.ancestors).to include(V2::Logic::Secrets::BaseSecretAction)
    end
  end
end
