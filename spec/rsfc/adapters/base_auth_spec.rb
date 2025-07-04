# spec/rsfc/adapters/base_auth_spec.rb

require 'spec_helper'

# rubocop:disable RSpec/MultipleExpectations
# rubocop:disable RSpec/MultipleDescribes
RSpec.describe RSFC::Adapters::BaseAuth do
  describe '#anonymous?' do
    it 'raises NotImplementedError' do
      expect { subject.anonymous? }.to raise_error(NotImplementedError)
    end
  end

  describe '#theme_preference' do
    it 'raises NotImplementedError' do
      expect { subject.theme_preference }.to raise_error(NotImplementedError)
    end
  end

  describe '#user_id' do
    it 'returns nil by default' do
      expect(subject.user_id).to be_nil
    end
  end

  describe '#has_role?' do
    it 'returns false by default' do
      expect(subject.has_role?('admin')).to be(false)
    end
  end
end

RSpec.describe RSFC::Adapters::AnonymousAuth do
  describe '#anonymous?' do
    it 'returns true' do
      expect(subject.anonymous?).to be(true)
    end
  end

  describe '#theme_preference' do
    it 'returns light theme' do
      expect(subject.theme_preference).to eq('light')
    end
  end

  describe '#user_id' do
    it 'returns nil' do
      expect(subject.user_id).to be_nil
    end
  end

  describe '#display_name' do
    it 'returns Anonymous' do
      expect(subject.display_name).to eq('Anonymous')
    end
  end
end

RSpec.describe RSFC::Adapters::AuthenticatedAuth do
  let(:user_data) { { id: 123, name: 'John Doe', theme: 'dark', roles: ['user', 'editor'] } }
  subject { described_class.new(user_data) }

  describe '#anonymous?' do
    it 'returns false' do
      expect(subject.anonymous?).to be(false)
    end
  end

  describe '#theme_preference' do
    it 'returns user theme' do
      expect(subject.theme_preference).to eq('dark')
    end

    context 'when no theme is set' do
      let(:user_data) { { id: 123 } }

      it 'returns default light theme' do
        expect(subject.theme_preference).to eq('light')
      end
    end
  end

  describe '#user_id' do
    it 'returns user ID' do
      expect(subject.user_id).to eq(123)
    end
  end

  describe '#display_name' do
    it 'returns user name' do
      expect(subject.display_name).to eq('John Doe')
    end
  end

  describe '#has_role?' do
    it 'returns true for user roles' do
      expect(subject.has_role?('user')).to be(true)
      expect(subject.has_role?('editor')).to be(true)
    end

    it 'returns false for roles user does not have' do
      expect(subject.has_role?('admin')).to be(false)
    end

    it 'handles string and symbol role names' do
      expect(subject.has_role?(:user)).to be(true)
      expect(subject.has_role?(:admin)).to be(false)
    end
  end

  describe '#attributes' do
    it 'returns user data' do
      expect(subject.attributes).to eq(user_data)
    end
  end
end
