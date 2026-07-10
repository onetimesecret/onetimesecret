# lib/onetime/cli/session_command.rb
#
# frozen_string_literal: true

#
# CLI commands for session inspection and debugging
#
# Usage:
#   ots session inspect <session-id>
#   ots session list [--limit N]
#   ots session search <email-or-custid>
#   ots session delete <session-id> [--force]
#

require 'json'

# The session capability now lives in central operations (epic #40 / D3): the
# single implementation of the list / inspect / delete verbs. These CLI commands
# are thin adapters over the ops, and SessionHelpers delegates its Redis/session
# primitives to Onetime::Operations::Sessions::Store so there is one source of
# truth. Loaded explicitly because CLI runs don't go through an app autoloader.
require 'onetime/operations/sessions/store'
require 'onetime/operations/sessions/list_sessions'
require 'onetime/operations/sessions/inspect_session'
require 'onetime/operations/sessions/delete_session'

module Onetime
  module CLI
    # Shared helpers for session commands.
    #
    # The Redis/session primitives here are thin delegations to
    # {Onetime::Operations::Sessions::Store} — the single extracted implementation
    # (epic #40). Behaviour is preserved byte-for-byte, in particular
    # {#load_session_data}'s JSON-not-Marshal safety guarantee locked in by
    # spec/cli/session_command_security_spec.rb.
    module SessionHelpers
      Store = Onetime::Operations::Sessions::Store

      def session_key_patterns(session_id)
        Store.key_patterns(session_id)
      end

      def find_session_in_redis(dbclient, session_id)
        session_key_patterns(session_id).each do |pattern|
          if dbclient.exists(pattern) > 0
            return load_session_data(dbclient, pattern)
          end
        end
        nil
      end

      def find_session_key(dbclient, session_id)
        Store.find_key(dbclient, session_id)
      end

      def load_session_data(dbclient, key)
        # Inject the shared codec so `bin/ots session inspect/search` decrypt the
        # value like the colonel console does; without it every field reads nil
        # and search-by-email never matches (session values are encrypted).
        Store.load_data(dbclient, key, codec: Onetime::SessionCodec.from_config)
      end

      def extract_session_id_from_key(key)
        Store.extract_id(key)
      end

      def display_session_info(data, session_id)
        puts 'Session Data:'
        puts '-' * 80

        # Core session info
        puts "Session ID: #{session_id}"
        puts

        # Authentication status
        puts 'Authentication:'
        if data['authenticated']
          puts '  ✓ Authenticated'
          puts "  Email: #{data['email']}"
          puts "  External ID: #{data['external_id'] || data['account_external_id']}"
          puts "  Role: #{data['role']}" if data['role']
          puts "  Authenticated at: #{format_timestamp(data['authenticated_at'])}"
          puts "  Authenticated by: #{data['authenticated_by']}" if data['authenticated_by']
        else
          puts '  ✗ Not authenticated'
        end
        puts

        # Advanced auth info (if using Rodauth)
        if data['account_id']
          puts 'Advanced Auth (Rodauth):'
          puts "  Account ID: #{data['account_id']}"
          puts "  Active Session ID: #{data['active_session_id']}" if data['active_session_id']
          puts
        end

        # Locale and user agent
        puts 'Session Details:'
        puts "  Locale: #{data['locale']}" if data['locale']
        puts "  IP Address: #{data['ip_address']}" if data['ip_address']
        puts "  User Agent: #{data['user_agent'][0..60]}..." if data['user_agent']
        puts

        # Redis info
        dbclient    = Familia.dbclient
        session_key = find_session_key(dbclient, session_id)
        if session_key
          ttl = dbclient.ttl(session_key)
          puts 'Redis Info:'
          puts "  Key: #{session_key}"
          if ttl > 0
            hours   = ttl / 3600
            minutes = (ttl % 3600) / 60
            puts "  TTL: #{ttl}s (#{hours}h #{minutes}m remaining)"
          elsif ttl == -1
            puts '  TTL: No expiration'
          else
            puts '  TTL: Expired'
          end
          puts
        end

        # All session keys
        puts "All Session Keys (#{data.keys.size}):"
        data.keys.sort.each do |key|
          value         = data[key]
          display_value = value.is_a?(String) && value.length > 50 ? "#{value[0..47]}..." : value.inspect
          puts "  #{key.ljust(30)}: #{display_value}"
        end
      end

      def matches_search?(session_data, search_term)
        Store.matches_search?(session_data, search_term)
      end

      def format_timestamp(timestamp)
        return 'unknown' unless timestamp

        Time.at(timestamp).strftime('%Y-%m-%d %H:%M:%S')
      rescue StandardError
        'invalid timestamp'
      end
    end

    # Default session command (shows usage)
    class SessionCommand < Dry::CLI::Command
      desc 'Session management and inspection'

      def call(**)
        puts '=' * 80
        puts 'Session Inspector'
        puts '=' * 80
        puts
        puts 'Usage: ots session <subcommand> [options]'
        puts
        puts 'Available subcommands:'
        puts '  inspect <session-id>              Show detailed session information'
        puts '  list [--limit N]                  List active sessions'
        puts '  search <email-or-custid>          Find sessions for a user'
        puts '  delete <session-id> [--force]     Delete a session'
        puts '  clean                              Remove expired sessions'
        puts
      end
    end

    # Inspect session command
    class SessionInspectCommand < Command
      include SessionHelpers

      desc 'Show detailed session information'

      argument :session_id, type: :string, required: false, desc: 'Session ID'

      def call(session_id: nil, **)
        unless session_id
          puts 'Error: Session ID required'
          puts 'Usage: ots session inspect <session-id>'
          return
        end

        boot_application!

        puts '=' * 80
        puts "Session Inspector: #{session_id}"
        puts '=' * 80
        puts

        # Route through the extracted inspect op (the single implementation).
        result = Onetime::Operations::Sessions::Inspect.new(session_id: session_id).call

        unless result.found
          puts '❌ Session not found in Redis'
          puts
          puts 'Searched patterns:'
          session_key_patterns(session_id).each do |pattern|
            puts "  - #{pattern}"
          end
          puts
          puts 'Available session keys (first 10):'
          keys = []
          begin
            Familia.dbclient.scan_each(match: '*session*').take(10).each { |k| keys << k }
          rescue StandardError
            keys = []
          end
          keys.each { |key| puts "  - #{key}" }
          return
        end

        # Display session information
        display_session_info(result.data, session_id)
      end
    end

    # List sessions command
    class SessionListCommand < Command
      include SessionHelpers

      desc 'List active sessions'

      option :limit,
        type: :string,
        default: '20',
        desc: 'Number of sessions to show (default: 20)'

      def call(limit: '20', **)
        boot_application!

        puts "Active Sessions (limit: #{limit})"
        puts '-' * 80

        # Route through the extracted list op (single implementation, bounded
        # scan). `--limit` maps to one page; the op caps a page at its MAX_PER_PAGE.
        result = Onetime::Operations::Sessions::List.new(page: 1, per_page: limit.to_i).call

        if result.sessions.empty?
          puts 'No sessions found'
          return
        end

        puts format('%-40s %-25s %-15s', 'Session ID', 'Authenticated As', 'Created')
        puts '-' * 80

        result.sessions.each do |session|
          session_id  = session[:session_id]
          email       = session[:email] || 'anonymous'
          external_id = session[:external_id] || '<n/a>'
          auth        = session[:authenticated] ? '✓' : '✗'
          created_at  = session[:created_at]

          time_str = if created_at
            Time.at(created_at).strftime('%Y-%m-%d %H:%M')
          else
            'unknown'
          end

          display_email = OT::Utils.obscure_email(email)
          puts format('%-40s %-25s %s', session_id[0..39], "#{auth} #{display_email} #{external_id}", time_str)
        end
      end
    end

    # Search sessions command
    class SessionSearchCommand < Command
      include SessionHelpers

      desc 'Find sessions for a user'

      argument :search_term, type: :string, required: false, desc: 'Email or customer ID to search'

      def call(search_term: nil, **)
        unless search_term
          puts 'Error: Email or customer ID required'
          puts 'Usage: ots session search <email-or-custid>'
          return
        end
        boot_application!

        puts "Searching for sessions matching: #{search_term}"
        puts '-' * 80

        # Route through the extracted list op with a search filter (single
        # implementation, bounded scan).
        result = Onetime::Operations::Sessions::List.new(
          search: search_term,
          per_page: Onetime::Operations::Sessions::List::MAX_PER_PAGE,
        ).call

        if result.sessions.empty?
          puts "No sessions found matching '#{search_term}'"
          return
        end

        puts "Found #{result.total_count} session(s):"
        puts

        result.sessions.each do |session|
          puts "Session: #{session[:session_id]}"
          puts "  Email: #{session[:email]}"
          puts "  External ID: #{session[:external_id]}"
          puts "  Authenticated: #{session[:authenticated]}"
          puts "  Created: #{format_timestamp(session[:created_at])}"
          puts
        end
      end
    end

    # Delete session command
    class SessionDeleteCommand < Command
      include SessionHelpers

      desc 'Delete a session'

      # Audit actor recorded for CLI-initiated revokes. The shell carries no
      # authenticated colonel identity; a plain, non-secret public sentinel is
      # used — never an internal objid. Mirrors BannedIpsBanCommand::CLI_ACTOR.
      CLI_ACTOR = 'cli'

      argument :session_id, type: :string, required: false, desc: 'Session ID'

      option :force,
        type: :boolean,
        default: false,
        desc: 'Skip confirmation prompt'

      def call(session_id: nil, force: false, **)
        unless session_id
          puts 'Error: Session ID required'
          puts 'Usage: ots session delete <session-id> [--force]'
          return
        end
        boot_application!

        # Resolve + display the target before mutating (EXISTS + GET only, no
        # TTL) so the confirmation shows the exact session being revoked.
        dbclient    = Familia.dbclient
        session_key = find_session_key(dbclient, session_id)

        unless session_key
          puts "❌ Session not found: #{session_id}"
          return
        end

        # Show session info before deleting
        session_data = load_session_data(dbclient, session_key)
        puts 'Session to delete:'
        puts "  ID: #{session_id}"
        puts "  Email: #{session_data['email']}" if session_data
        puts "  Authenticated: #{session_data['authenticated']}" if session_data
        puts

        unless force
          print 'Delete this session? (y/N): '
          response = $stdin.gets.chomp
          unless response.downcase == 'y'
            puts 'Cancelled'
            return
          end
        end

        # Route the actual deletion through the extracted, audited op (the single
        # implementation). It re-resolves the key and records one AdminAuditEvent.
        Onetime::Operations::Sessions::Delete.new(
          session_id: session_id,
          actor: CLI_ACTOR,
        ).call
        puts '✓ Session deleted'
      end
    end

    # Clean expired sessions command
    class SessionCleanCommand < Command
      desc 'Remove expired sessions'

      def call(**)
        boot_application!

        puts 'Cleaning expired sessions...'
        dbclient     = Familia.dbclient
        session_keys = dbclient.scan_each(match: '*session*').to_a
        expired      = 0
        active       = 0

        session_keys.each do |key|
          ttl = dbclient.ttl(key)
          if ttl == -2 # Key doesn't exist
            next
          elsif ttl == -1 # Key exists but has no expiry
            active += 1
          elsif ttl > 0 # Key has TTL
            active += 1
          else
            # Shouldn't happen, but clean it anyway
            dbclient.del(key)
            expired += 1
          end
        end

        puts 'Summary:'
        puts "  Active sessions: #{active}"
        puts "  Expired sessions removed: #{expired}"
      end
    end

    # Register session commands
    register 'session', SessionCommand
    register 'session inspect', SessionInspectCommand
    register 'session list', SessionListCommand
    register 'session search', SessionSearchCommand
    register 'session delete', SessionDeleteCommand
    register 'session clean', SessionCleanCommand
  end
end
