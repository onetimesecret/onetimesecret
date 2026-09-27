# spec/cli/sentry_doctor_command_spec.rb
#
# frozen_string_literal: true

require_relative 'cli_spec_helper'

# The doctor answers "will this shell's boot report to Sentry?". Under
# RACK_ENV=test that needs DIAGNOSTICS_ENABLED_IN_TEST=true on top of
# DIAGNOSTICS_ENABLED=true (Onetime::Config.diagnostics_enabled?), so the
# doctor must not call such a shell HEALTHY.
RSpec.describe 'Sentry doctor command', type: :cli do
  let(:env_keys) do
    %w[RACK_ENV DIAGNOSTICS_ENABLED DIAGNOSTICS_ENABLED_IN_TEST SENTRY_DSN
       SENTRY_DSN_BACKEND SENTRY_DSN_FRONTEND SENTRY_DSN_WORKERS]
  end

  around do |example|
    saved = env_keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    ENV.update(
      'DIAGNOSTICS_ENABLED' => 'true',
      'SENTRY_DSN_BACKEND' => 'https://key@sentry.example.com/1',
      'SENTRY_DSN_FRONTEND' => 'https://key@sentry.example.com/1',
      'SENTRY_DSN_WORKERS' => 'https://key@sentry.example.com/1',
    )
    example.run
  ensure
    saved.each { |key, value| ENV[key] = value }
  end

  before do
    # No DSN probes: the network half of the doctor is out of scope here.
    allow(Onetime::CLI::Diagnostics).to receive_messages(backend_dsn: nil, frontend_dsn: nil)
  end

  it 'fails a RACK_ENV=test shell that lacks DIAGNOSTICS_ENABLED_IN_TEST', :aggregate_failures do
    ENV['RACK_ENV'] = 'test'
    ENV.delete('DIAGNOSTICS_ENABLED_IN_TEST')

    output = run_cli_command_quietly('diagnostics', 'sentry', 'doctor')

    expect(output[:stdout]).to match(/DIAGNOSTICS_ENABLED_IN_TEST\s+\[FAIL\]/)
    expect(output[:stdout]).not_to include('Overall: HEALTHY')
    expect(last_exit_code).to eq(1)
  end

  it 'passes a RACK_ENV=test shell that opts in', :aggregate_failures do
    ENV['RACK_ENV']                    = 'test'
    ENV['DIAGNOSTICS_ENABLED_IN_TEST'] = 'true'

    output = run_cli_command_quietly('diagnostics', 'sentry', 'doctor')

    expect(output[:stdout]).to include('Overall: HEALTHY')
    expect(last_exit_code).to eq(0)
  end

  it 'does not check the test opt-in outside RACK_ENV=test', :aggregate_failures do
    ENV['RACK_ENV'] = 'production'
    ENV.delete('DIAGNOSTICS_ENABLED_IN_TEST')

    output = run_cli_command_quietly('diagnostics', 'sentry', 'doctor')

    expect(output[:stdout]).not_to include('DIAGNOSTICS_ENABLED_IN_TEST')
    expect(output[:stdout]).to include('Overall: HEALTHY')
  end

  it 'does not print OK for DIAGNOSTICS_ENABLED when it fails', :aggregate_failures do
    ENV['RACK_ENV']            = 'production'
    ENV['DIAGNOSTICS_ENABLED'] = 'false'

    output = run_cli_command_quietly('diagnostics', 'sentry', 'doctor')

    expect(output[:stdout]).to match(/DIAGNOSTICS_ENABLED\s+\[FAIL\]/)
    expect(output[:stdout]).not_to match(/DIAGNOSTICS_ENABLED\s+\[OK\]/)
  end
end
