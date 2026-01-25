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

module Onetime
  module CLI
    # Shared helpers for session commands
    module SessionHelpers
      def session_key_patterns(session_id)
        [
          "session:#{session_id}",
          "rack:session:#{session_id}",
          session_id,
          "session:rack:session:#{session_id}",
        ]
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
        session_key_patterns(session_id).each do |pattern|
          return pattern if dbclient.exists(pattern) > 0
        end
        nil
      end

      def load_session_data(dbclient, key)
        raw_data = dbclient.get(key)
        return nil unless raw_data

        # Try different deserializations
        begin
          Marshal.load(raw_data)
        rescue StandardError
          begin
            JSON.parse(raw_data)
          rescue StandardError
            { '_raw' => raw_data[0..200] }
          end
        end
      end

      def extract_session_id_from_key(key)
        # Remove common prefixes
        key.gsub(/^(session:|rack:session:)/, '')
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
        search_term_lower = search_term.downcase
        [
          session_data['email'],
          session_data['external_id'],
          session_data['account_external_id'],
        ].compact.any? { |field| field.downcase.include?(search_term_lower) }
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

        # Try to find session in Redis using common patterns
        dbclient     = Familia.dbclient
        session_data = find_session_in_redis(dbclient, session_id)

        unless session_data
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
            dbclient.scan_each(match: '*session*').take(10).each { |k| keys << k }
          rescue StandardError
            keys = []
          end
          keys.each { |key| puts "  - #{key}" }
          return
        end

        # Display session information
        display_session_info(session_data, session_id)
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

        dbclient     = Familia.dbclient
        session_keys = dbclient.scan_each(match: '*session*').first(limit.to_i)

        if session_keys.empty?
          puts 'No sessions found'
          return
        end

        puts format('%-40s %-25s %-15s', 'Session ID', 'Authenticated As', 'Created')
        puts '-' * 80

        session_keys.each do |key|
          session_data = load_session_data(dbclient, key)
          next unless session_data

          session_id = extract_session_id_from_key(key)
          email      = session_data['email'] || 'anonymous'
          external_id= session_data['external_id'] || '<n/a>'
          auth       = session_data['authenticated'] ? '✓' : '✗'
          created_at = session_data['authenticated_at']

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

        dbclient     = Familia.dbclient
        session_keys = dbclient.scan_each(match: '*session*').to_a
        found        = []

        session_keys.each do |key|
          session_data = load_session_data(dbclient, key)
          next unless session_data

          if matches_search?(session_data, search_term)
            found << [key, session_data]
          end
        end

        if found.empty?
          puts "No sessions found matching '#{search_term}'"
          return
        end

        puts "Found #{found.size} session(s):"
        puts

        found.each do |key, data|
          session_id = extract_session_id_from_key(key)
          puts "Session: #{session_id}"
          puts "  Email: #{data['email']}"
          puts "  External ID: #{data['external_id'] || data['account_external_id']}"
          puts "  Authenticated: #{data['authenticated']}"
          puts "  Created: #{format_timestamp(data['authenticated_at'])}"
          puts
        end
      end
    end

    # Delete session command
    class SessionDeleteCommand < Command
      include SessionHelpers

      desc 'Delete a session'

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

        dbclient.del(session_key)
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
