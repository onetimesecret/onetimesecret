# spec/unit/onetime/version_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Onetime::VERSION do
  let(:commit_hash_path) { File.join(Onetime::HOME, '.commit_hash.txt') }

  describe '.get_build_info' do
    # Reset cached @version between tests to ensure get_build_info is called fresh
    before do
      Onetime::VERSION.instance_variable_set(:@version, nil)
    end

    context 'when .commit_hash.txt exists with valid commit hash' do
      it 'returns the commit hash from file' do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(commit_hash_path).and_return(true)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(commit_hash_path).and_return("abc1234\n")

        expect(described_class.get_build_info).to eq('abc1234')
      end

      it 'strips whitespace from file content' do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(commit_hash_path).and_return(true)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(commit_hash_path).and_return("  def5678  \n")

        expect(described_class.get_build_info).to eq('def5678')
      end
    end

    context 'when .commit_hash.txt contains placeholder values' do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(commit_hash_path).and_return(true)
        allow(File).to receive(:read).and_call_original
      end

      it 'filters out "dev" and falls back to dev (no git in test)' do
        allow(File).to receive(:read).with(commit_hash_path).and_return("dev\n")
        # Git command returns empty in test environment, triggering 'dev' fallback
        allow(described_class).to receive(:`).and_return("")

        expect(described_class.get_build_info).to eq('dev')
      end

      it 'filters out "pristine" and falls back to dev (no git in test)' do
        allow(File).to receive(:read).with(commit_hash_path).and_return("pristine\n")
        allow(described_class).to receive(:`).and_return("")

        expect(described_class.get_build_info).to eq('dev')
      end
    end

    context 'when .commit_hash.txt is empty' do
      it 'falls back to dev when git unavailable' do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(commit_hash_path).and_return(true)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(commit_hash_path).and_return("")
        allow(described_class).to receive(:`).and_return("")

        expect(described_class.get_build_info).to eq('dev')
      end
    end

    context 'when .commit_hash.txt does not exist' do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(commit_hash_path).and_return(false)
      end

      it 'returns "dev" when git returns empty output' do
        allow(described_class).to receive(:`).and_return("")

        expect(described_class.get_build_info).to eq('dev')
      end

      it 'returns "dev" when git returns only whitespace' do
        allow(described_class).to receive(:`).and_return("   \n")

        expect(described_class.get_build_info).to eq('dev')
      end
    end

    context 'when both file and git are unavailable' do
      it 'returns "dev" as final fallback' do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(commit_hash_path).and_return(false)
        allow(described_class).to receive(:`).and_return("")

        expect(described_class.get_build_info).to eq('dev')
      end
    end

    # Integration-style test using actual git (if available)
    context 'with real git repository' do
      it 'returns a 7-character hash when in a git repo' do
        # Skip stubbing - let actual git run
        # This tests the real behavior in development
        result = described_class.get_build_info
        # Result should be either a 7-char hash or 'dev'
        expect(result).to match(/\A([a-f0-9]{7}|dev)\z/)
      end
    end
  end

  describe '.user_agent' do
    it 'returns formatted user agent string' do
      # VERSION.to_s depends on package.json, so we stub it
      allow(described_class).to receive(:to_s).and_return('1.2.3')

      expect(described_class.user_agent).to eq("OnetimeWorker/1.2.3 (Ruby/#{RUBY_VERSION})")
    end
  end
end
