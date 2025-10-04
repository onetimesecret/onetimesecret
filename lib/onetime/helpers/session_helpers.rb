# lib/onetime/helpers/session_helpers.rb

module Onetime
  module Helpers
    module SessionHelpers

      def authenticated?
        session['authenticated'] == true &&
        session['identity_id'].to_s.length > 0 &&
        authentication_enabled?
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
        session['identity_id'] = customer.custid
        session['email'] = customer.email
        session['authenticated'] = true
        session['authenticated_at'] = Time.now.to_i
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

        customer = Onetime::Customer.load(session['identity_id'])
        return Onetime::Customer.anonymous unless customer

        # Update last seen timestamp
        session['last_seen'] = Time.now.to_i

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
