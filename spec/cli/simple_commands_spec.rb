# spec/cli/simple_commands_spec.rb
#
# frozen_string_literal: true

require_relative 'cli_spec_helper'

RSpec.describe 'Simple CLI Commands', type: :cli do
  describe 'version command' do
    it 'displays the Onetime version' do
      output = run_cli_command_quietly('version')
      expect(output[:stdout]).to include(OT::VERSION.to_s)
    end

    it 'displays version for build alias' do
      output = run_cli_command_quietly('build')
      expect(output[:stdout]).to include(OT::VERSION.to_s)
    end
  end

  describe 'load-path command' do
    it 'displays the first 5 load paths' do
      output = run_cli_command_quietly('load-path')
      paths = output[:stdout].lines.map(&:chomp)
      expect(paths.length).to be <= 5
      expect(paths.first).to eq($LOAD_PATH[0])
    end
  end

  describe 'help command' do
    it 'displays general help without topic' do
      output = run_cli_command_quietly('help')
      expect(output[:stdout]).to include('Usage: ots help [topic]')
      expect(output[:stdout]).to include('Available topics')
    end

    it 'displays logging help for logging topic' do
      output = run_cli_command_quietly('help', 'logging')
      expect(output[:stdout]).to include('Logging Configuration')
      expect(output[:stdout]).to include('LOGGING CATEGORIES')
      expect(output[:stdout]).to include('ENVIRONMENT VARIABLES')
    end

    it 'displays logging help for logs topic' do
      output = run_cli_command_quietly('help', 'logs')
      expect(output[:stdout]).to include('Logging Configuration')
    end
  end

  describe 'console command' do
    it 'executes irb with correct path' do
      expect(Kernel).to receive(:exec) do |cmd|
        expect(cmd).to include('irb')
        expect(cmd).to include('-ronetime/console')
        expect(cmd).to include(File.join(Onetime::HOME, 'lib'))
      end

      run_cli_command_quietly('console')
    end

    it 'sets DELAY_BOOT env var with --delay-boot option' do
      expect(Kernel).to receive(:exec) do
        expect(ENV['DELAY_BOOT']).to eq('true')
      end

      run_cli_command_quietly('console', '--delay-boot')
    end

    it 'does not set DELAY_BOOT without option' do
      expect(Kernel).to receive(:exec) do
        expect(ENV['DELAY_BOOT']).to eq('false')
      end

      run_cli_command_quietly('console')
    end
  end
end
