# spec/cli/session_command_spec.rb
#
# frozen_string_literal: true

require_relative 'cli_spec_helper'

RSpec.describe 'Session Command', type: :cli do
  let(:redis) { mock_redis_client }
  let(:session_id) { '40b536f31d425980' }
  let(:session_data) do
    {
      'authenticated' => true,
      'email' => 'test@example.com',
      'external_id' => 'test123',
      'authenticated_at' => Time.now.to_i
    }
  end

  before do
    allow(Marshal).to receive(:load).and_return(session_data)
  end

  describe 'without subcommand' do
    it 'displays usage information' do
      output = run_cli_command_quietly('session')
      expect(output[:stdout]).to include('Session Inspector')
      expect(output[:stdout]).to include('Usage: ots session <subcommand>')
      expect(output[:stdout]).to include('inspect')
      expect(output[:stdout]).to include('list')
      expect(output[:stdout]).to include('search')
      expect(output[:stdout]).to include('delete')
      expect(output[:stdout]).to include('clean')
    end
  end

  describe 'inspect subcommand' do
    it 'requires a session ID' do
      output = run_cli_command_quietly('session', 'inspect')
      expect(output[:stdout]).to include('Error: Session ID required')
    end

    it 'displays session not found for non-existent session' do
      allow(redis).to receive(:exists).and_return(0)
      allow(redis).to receive(:scan_each).and_return([].each)

      output = run_cli_command_quietly('session', 'inspect', session_id)
      expect(output[:stdout]).to include('Session not found in Redis')
    end

    it 'displays session information when found' do
      allow(redis).to receive(:exists).with("session:#{session_id}").and_return(1)
      allow(redis).to receive(:get).and_return(Marshal.dump(session_data))
      allow(redis).to receive(:ttl).and_return(3600)

      output = run_cli_command_quietly('session', 'inspect', session_id)
      expect(output[:stdout]).to include('Session Inspector')
      expect(output[:stdout]).to include(session_id)
    end

    it 'uses SCAN instead of KEYS for listing available sessions' do
      allow(redis).to receive(:exists).and_return(0)

      # Expect scan_each, not keys
      expect(redis).to receive(:scan_each).with(match: '*session*').and_return([].each)

      run_cli_command_quietly('session', 'inspect', session_id)
    end
  end

  describe 'list subcommand' do
    it 'lists sessions with default limit' do
      session_keys = (1..5).map { |i| "session:#{i}" }
      allow(redis).to receive(:scan_each).and_return(session_keys.each)
      allow(redis).to receive(:get).and_return(Marshal.dump(session_data))

      output = run_cli_command_quietly('session', 'list')
      expect(output[:stdout]).to include('Active Sessions')
    end

    it 'respects --limit option' do
      session_keys = (1..30).map { |i| "session:#{i}" }
      allow(redis).to receive(:scan_each).and_return(session_keys.each)
      allow(redis).to receive(:get).and_return(Marshal.dump(session_data))

      output = run_cli_command_quietly('session', 'list', '--limit', '5')
      expect(output[:stdout]).to include('Active Sessions (limit: 5)')
    end
  end

  describe 'search subcommand' do
    it 'requires a search term' do
      output = run_cli_command_quietly('session', 'search')
      expect(output[:stdout]).to include('Error: Email or customer ID required')
    end

    it 'searches for sessions matching email' do
      allow(redis).to receive(:scan_each).and_return(["session:#{session_id}"].each)
      allow(redis).to receive(:get).and_return(Marshal.dump(session_data))

      output = run_cli_command_quietly('session', 'search', 'test@example.com')
      expect(output[:stdout]).to include('Searching for sessions')
      expect(output[:stdout]).to include('test@example.com')
    end

    it 'handles no results found' do
      allow(redis).to receive(:scan_each).and_return([].each)

      output = run_cli_command_quietly('session', 'search', 'notfound@example.com')
      expect(output[:stdout]).to include('No sessions found')
    end
  end

  describe 'delete subcommand' do
    it 'requires a session ID' do
      output = run_cli_command_quietly('session', 'delete')
      expect(output[:stdout]).to include('Error: Session ID required')
    end

    it 'prompts for confirmation without --force' do
      allow(redis).to receive(:exists).and_return(1)
      allow(redis).to receive(:get).and_return(Marshal.dump(session_data))
      allow($stdin).to receive(:gets).and_return("n\n")

      output = run_cli_command_quietly('session', 'delete', session_id)
      expect(output[:stdout]).to include('Delete this session?')
      expect(output[:stdout]).to include('Cancelled')
    end

    it 'deletes session with --force flag' do
      allow(redis).to receive(:exists).and_return(1)
      allow(redis).to receive(:get).and_return(Marshal.dump(session_data))
      expect(redis).to receive(:del).with("session:#{session_id}")

      output = run_cli_command_quietly('session', 'delete', session_id, '--force')
      expect(output[:stdout]).to include('Session deleted')
    end
  end

  describe 'clean subcommand' do
    it 'removes expired sessions' do
      allow(redis).to receive(:scan_each).and_return(['session:1', 'session:2'].each)
      allow(redis).to receive(:ttl).and_return(3600, -1)

      output = run_cli_command_quietly('session', 'clean')
      expect(output[:stdout]).to include('Cleaning expired sessions')
      expect(output[:stdout]).to include('Summary')
    end
  end
end
