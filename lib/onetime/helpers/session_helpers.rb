# lib/onetime/helpers/session_helpers.rb
#
# Session-based authentication helpers that minimize database/Redis lookups.
#
# Performance Pattern:
# - Authentication checks use session data only (no DB/Redis hit)
# - Customer object is lazy-loaded only when actually needed
# - Role checks use session data for common permission checks
#
# Session Data Stored:
# - external_id: Links to Customer.extid (Redis primary key)
# - email: User's email address
# - role: User's role (customer, colonel, etc.) for quick permission checks
# - authenticated: Boolean flag
# - authenticated_at: Unix timestamp
#
# Usage:
#   authenticated?      # Fast - checks session only
#   has_role?(:colonel) # Fast - checks session only
#   current_customer    # Slow - loads from Redis (use sparingly)

module Onetime
  module Helpers
    module SessionHelpers

      def authenticated?
        session['authenticated'] == true &&
        session['external_id'].to_s.length > 0 &&
        authentication_enabled?
      end

      # Check user role without loading Customer (uses session data)
      def has_role?(role_name)
        return false unless authenticated?
        session['role'].to_s == role_name.to_s
      end

      def colonel?
        has_role?(:colonel)
      end

      def current_customer
        @current_customer ||= load_current_customer
      end

      def authenticate!(customer)
        # Clear any existing session data
        session.clear

        # Regenerate session ID to prevent fixation (Rack::Session pattern)
        request.session_options[:renew] = true if request.respond_to?(:session_options)

        # Set authentication data
        session['external_id'] = customer.extid
        session['email'] = customer.email
        session['role'] = customer.role  # Store role for permission checks
        session['authenticated'] = true
        session['authenticated_at'] = Familia.now.to_i
        session['ip_address'] = request.ip
        session['user_agent'] = request.user_agent

        # Initialize CSRF protection
        regenerate_shrimp! if respond_to?(:regenerate_shrimp!)
      end

      def logout!
        session_id = session.id&.private_id if session.respond_to?(:id)
        session.clear
        OT.info "[logout] Session #{session_id} destroyed" if session_id
      end

      private

      def load_current_customer
        return Onetime::Customer.anonymous unless authenticated?

        customer = Onetime::Customer.find_by_extid(session['external_id'])
        return Onetime::Customer.anonymous unless customer

        # Update cached session data if it changed
        session['role'] = customer.role if session['role'] != customer.role
        session['last_seen'] = Familia.now.to_i

        customer
      end

      def authentication_enabled?
        # Check global authentication toggle
        return true unless defined?(OT) && OT.respond_to?(:conf)

        auth_conf = OT.conf&.dig('site', 'authentication')
        return true unless auth_conf

        auth_conf['enabled'] != false
      end
    end
  end
end
