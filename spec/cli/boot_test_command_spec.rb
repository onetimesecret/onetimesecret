# spec/cli/boot_test_command_spec.rb
#
# frozen_string_literal: true

require_relative 'cli_spec_helper'

RSpec.describe 'Boot Test Command', type: :cli do
  let(:registry) { double('Registry') }
  let(:health_status) { { healthy: true, applications: {} } }

  before do
    allow(Onetime).to receive(:boot!)
    allow(Onetime).to receive(:ready?).and_return(true)
    allow(Onetime::Application::Registry).to receive(:prepare_application_registry)
    allow(Onetime::Application::Registry).to receive(:generate_rack_url_map)
    allow(Onetime::Application::Registry).to receive(:health_check).and_return(health_status)
    allow(Onetime::Application::Registry).to receive(:mount_mappings).and_return({
      '/' => 'Onetime::Web::Core',
      '/api/v1' => 'Onetime::API::V1'
    })
  end

  describe 'successful boot' do
    it 'boots the application' do
      expect(Onetime).to receive(:boot!).with(:app)

      expect {
        run_cli_command('boot-test')
      }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(0)
      end
    end

    it 'prepares application registry' do
      expect(Onetime::Application::Registry).to receive(:prepare_application_registry)

      expect {
        run_cli_command('boot-test')
      }.to raise_error(SystemExit)
    end

    it 'performs health check' do
      expect(Onetime::Application::Registry).to receive(:health_check)

      expect {
        run_cli_command('boot-test')
      }.to raise_error(SystemExit)
    end

    it 'displays success message' do
      output = nil
      expect {
        output = run_cli_command('boot-test')
      }.to raise_error(SystemExit)

      expect(output[:stderr]).to include('Boot test successful!')
      expect(output[:stderr]).to include('Loaded applications')
    end

    it 'exits with status 0 on success' do
      expect {
        run_cli_command('boot-test')
      }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(0)
      end
    end
  end

  describe 'boot failure' do
    it 'exits with status 1 when boot incomplete' do
      allow(Onetime).to receive(:ready?).and_return(false)

      expect {
        run_cli_command('boot-test')
      }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(1)
      end
    end

    it 'displays error message on boot failure' do
      allow(Onetime).to receive(:ready?).and_return(false)

      output = nil
      expect {
        output = run_cli_command('boot-test')
      }.to raise_error(SystemExit)

      expect(output[:stderr]).to include('Boot test failed')
    end
  end

  describe 'registry failure' do
    it 'exits with status 1 when registry preparation fails' do
      allow(Onetime::Application::Registry).to receive(:prepare_application_registry)
      allow(Onetime).to receive(:ready?).and_return(true, false)

      expect {
        run_cli_command('boot-test')
      }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(1)
      end
    end

    it 'displays registry error message' do
      allow(Onetime::Application::Registry).to receive(:prepare_application_registry)
      allow(Onetime).to receive(:ready?).and_return(true, false)

      output = nil
      expect {
        output = run_cli_command('boot-test')
      }.to raise_error(SystemExit)

      expect(output[:stderr]).to include('Application registry preparation failed')
    end
  end

  describe 'health check failure' do
    let(:unhealthy_status) do
      {
        healthy: false,
        applications: {
          'TestApp' => {
            healthy: false,
            router_present: false,
            rack_app_present: true
          }
        }
      }
    end

    it 'exits with status 1 when health check fails' do
      allow(Onetime::Application::Registry).to receive(:health_check).and_return(unhealthy_status)

      expect {
        run_cli_command('boot-test')
      }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(1)
      end
    end

    it 'displays unhealthy applications' do
      allow(Onetime::Application::Registry).to receive(:health_check).and_return(unhealthy_status)

      output = nil
      expect {
        output = run_cli_command('boot-test')
      }.to raise_error(SystemExit)

      expect(output[:stderr]).to include('One or more applications unhealthy')
    end
  end

  describe 'exception handling' do
    it 'catches and reports exceptions' do
      allow(Onetime).to receive(:boot!).and_raise(StandardError.new('Test error'))

      output = nil
      expect {
        output = run_cli_command('boot-test')
      }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(1)
      end

      expect(output[:stderr]).to include('Boot test failed')
      expect(output[:stderr]).to include('Test error')
    end

    it 'shows backtrace with --verbose flag' do
      allow(Onetime).to receive(:boot!).and_raise(StandardError.new('Test error'))
      allow(ARGV).to receive(:any?).and_return(true)

      output = nil
      expect {
        output = run_cli_command('boot-test', '--verbose')
      }.to raise_error(SystemExit)

      expect(output[:stderr]).to include('Backtrace')
    end
  end
end
