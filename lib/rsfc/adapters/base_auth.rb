# lib/rsfc/adapters/base_auth.rb

module RSFC
  module Adapters
    # Base authentication adapter interface
    #
    # Defines the contract that authentication adapters must implement
    # to work with RSFC. This allows the library to work with any
    # authentication system by implementing this interface.
    class BaseAuth
      # Check if user is anonymous
      def anonymous?
        raise NotImplementedError, "Subclasses must implement #anonymous?"
      end

      # Get user's theme preference
      def theme_preference
        raise NotImplementedError, "Subclasses must implement #theme_preference"
      end

      # Get user identifier (optional)
      def user_id
        nil
      end

      # Get user display name (optional)  
      def display_name
        nil
      end

      # Check if user has specific role/permission (optional)
      def has_role?(role)
        false
      end

      # Get user attributes as hash (optional)
      def attributes
        {}
      end

      class << self
        # Create anonymous user instance
        def anonymous
          new
        end
      end
    end

    # Default implementation for anonymous users
    class AnonymousAuth < BaseAuth
      def anonymous?
        true
      end

      def theme_preference
        'light'
      end

      def user_id
        nil
      end

      def display_name
        'Anonymous'
      end
    end

    # Example authenticated user implementation
    class AuthenticatedAuth < BaseAuth
      attr_reader :user_data

      def initialize(user_data = {})
        @user_data = user_data
      end

      def anonymous?
        false
      end

      def theme_preference
        @user_data[:theme] || @user_data['theme'] || 'light'
      end

      def user_id
        @user_data[:id] || @user_data['id']
      end

      def display_name
        @user_data[:name] || @user_data['name'] || 'User'
      end

      def has_role?(role)
        roles = @user_data[:roles] || @user_data['roles'] || []
        roles.include?(role) || roles.include?(role.to_s)
      end

      def attributes
        @user_data
      end
    end
  end
end