# lib/rsfc/adapters/base_session.rb

module RSFC
  module Adapters
    # Base session adapter interface
    #
    # Defines the contract that session adapters must implement
    # to work with RSFC. This allows the library to work with any
    # session management system.
    class BaseSession
      # Check if session is authenticated
      def authenticated?
        raise NotImplementedError, "Subclasses must implement #authenticated?"
      end

      # Get session identifier
      def session_id
        nil
      end

      # Get session data
      def data
        {}
      end

      # Check if session is valid/active
      def valid?
        true
      end

      # Get session creation time
      def created_at
        nil
      end

      # Get last access time
      def last_accessed_at
        nil
      end
    end

    # Default implementation for anonymous sessions
    class AnonymousSession < BaseSession
      def authenticated?
        false
      end

      def session_id
        'anonymous'
      end

      def valid?
        true
      end
    end

    # Example authenticated session implementation
    class AuthenticatedSession < BaseSession
      attr_reader :session_data

      def initialize(session_data = {})
        @session_data = session_data
      end

      def authenticated?
        !@session_data.empty? && valid?
      end

      def session_id
        @session_data[:id] || @session_data['id']
      end

      def data
        @session_data
      end

      def valid?
        return false unless @session_data[:created_at] || @session_data['created_at']

        # Add session validation logic here (expiry, etc.)
        true
      end

      def created_at
        @session_data[:created_at] || @session_data['created_at']
      end

      def last_accessed_at
        @session_data[:last_accessed_at] || @session_data['last_accessed_at']
      end
    end
  end
end
