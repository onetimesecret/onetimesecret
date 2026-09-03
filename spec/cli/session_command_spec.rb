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

  # Session data is stored as JSON; load_session_data parses it with
  # JSON.parse (not Marshal.load) so crafted Redis bytes cannot trigger a
  # deserialization gadget chain.
  let(:serialized_session) { JSON.generate(session_data) }

  describe 'without subcommand' do
    it 'displays usage information' do
      output = run_cli_command_quietly('session')
      expect(output[:stdout]).to include('Session Inspector')
      expect(output[:stdout]).to include('Usage: ots session <subcommand>')
      expect(output[:stdout]).to include('inspect')
      expect(output[:stdout]).to include('list')
      expect(output[:stdout]).to include('search')
      expect(output[:stdout]).to include('delete')
      expect(output[:stdout]).to include('revoke-all')
      expect(output[:stdout]).not_to include('clean')
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
      allow(redis).to receive(:get).and_return(serialized_session)
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
      allow(redis).to receive(:get).and_return(serialized_session)

      output = run_cli_command_quietly('session', 'list')
      expect(output[:stdout]).to include('Active Sessions')
    end

    it 'respects --limit option' do
      session_keys = (1..30).map { |i| "session:#{i}" }
      allow(redis).to receive(:scan_each).and_return(session_keys.each)
      allow(redis).to receive(:get).and_return(serialized_session)

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
      allow(redis).to receive(:get).and_return(serialized_session)

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
      allow(redis).to receive(:get).and_return(serialized_session)
      allow($stdin).to receive(:gets).and_return("n\n")

      output = run_cli_command_quietly('session', 'delete', session_id)
      expect(output[:stdout]).to include('Delete this session?')
      expect(output[:stdout]).to include('Cancelled')
    end

    it 'deletes session with --force flag' do
      allow(redis).to receive(:exists).and_return(1)
      allow(redis).to receive(:get).and_return(serialized_session)
      expect(redis).to receive(:del).with("session:#{session_id}")

      output = run_cli_command_quietly('session', 'delete', session_id, '--force')
      expect(output[:stdout]).to include('Session deleted')
    end
  end

  describe 'revoke-all subcommand' do
    let(:customer) do
      instance_double(
        Onetime::Customer,
        exists?: true,
        extid: 'ur_target',
        obscure_email: 't***@e***.com',
      )
    end
    let(:result) do
      Onetime::Operations::Sessions::RevokeAllForCustomer::Result.new(
        revoked: true,
        blobs_deleted: 3,
        untracked_deleted: 1,
        rodauth_rows_deleted: 1,
        scan_capped: false,
      )
    end
    let(:operation) do
      instance_double(Onetime::Operations::Sessions::RevokeAllForCustomer, call: result)
    end

    before do
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(customer)
      allow(Onetime::Customer).to receive(:load).and_return(nil)
      allow(Onetime::Operations::Sessions::RevokeAllForCustomer).to receive(:new).and_return(operation)
    end

    it 'requires a customer identifier' do
      output = run_cli_command_quietly('sessions', 'revoke-all')

      expect(output[:stdout]).to include('Error: Customer required')
      expect(Onetime::Operations::Sessions::RevokeAllForCustomer).not_to have_received(:new)
    end

    it 'refuses an unknown customer instead of reporting a zero-count success' do
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(nil)

      output = run_cli_command_quietly('sessions', 'revoke-all', 'missing', '--force')

      expect(output[:stdout]).to include('Error: Customer not found: missing')
      expect(Onetime::Operations::Sessions::RevokeAllForCustomer).not_to have_received(:new)
    end

    it 'invokes the audited operation through the plural break-glass path' do
      output = run_cli_command_quietly(
        'sessions', 'revoke-all', 'target@example.com', '--reason', 'takeover', '--force'
      )

      expect(Onetime::Operations::Sessions::RevokeAllForCustomer).to have_received(:new).with(
        custid: 'ur_target', actor: 'cli', reason: 'takeover',
      )
      expect(output[:stdout]).to include('Revoked 3 session(s) for ur_target')
    end

    it 'keeps the established singular namespace available' do
      output = run_cli_command_quietly('session', 'revoke-all', 'ur_target', '--force')

      expect(output[:stdout]).to include('Revoked 3 session(s) for ur_target')
    end

    it 'prompts before revoking unless forced' do
      allow($stdin).to receive(:gets).and_return("n\n")

      output = run_cli_command_quietly('sessions', 'revoke-all', 'ur_target')

      expect(output[:stdout]).to include('Revoke every session')
      expect(output[:stdout]).to include('Cancelled')
      expect(Onetime::Operations::Sessions::RevokeAllForCustomer).not_to have_received(:new)
    end
  end
end
