# apps/web/auth/operations/sync_session.rb

#
# Syncs the Rodauth session with the application's session format after
# successful authentication. This operation handles:
# - Clearing rate limiting
# - Creating or loading customer records
# - Populating session with user data
# - Linking Rodauth account to Customer model
#

module Auth
  module Operations
    class SyncSession
      # @param account [Hash] The Rodauth account hash
      # @param account_id [Integer] The ID of the Rodauth account
      # @param session [Hash] The Rack session
      # @param request [Rack::Request] The request object
      # @param db [Sequel::Database] The database connection (optional, uses Auth::Database if not provided)
      def initialize(account:, account_id:, session:, request:, db: nil)
        @account = account
        @account_id = account_id
        @session = session
        @request = request
        @db = db || Auth::Database.connection
      end

      # Executes the session sync operation
      # @return [Onetime::Customer] The customer associated with this session
      def call
        OT.info "[sync-session] Syncing session for account ID: #{@account_id}"

        clear_rate_limiting
        customer = ensure_customer_exists
        populate_session(customer)
        track_request_metadata

        OT.info "[sync-session] Session synced successfully for #{@session['email']}"
        customer
      end

      private

      # Clears rate limiting keys for this account
      def clear_rate_limiting
        rate_limit_key = "login_attempts:#{@account[:email]}"
        Familia.dbclient.del(rate_limit_key)
      end

      # Ensures a Customer record exists and is linked to the Rodauth account
      # @return [Onetime::Customer]
      def ensure_customer_exists
        customer = find_existing_customer || create_customer
        link_customer_to_account(customer) unless customer_linked?(customer)
        customer
      end

      # Finds existing customer by external_id or email
      # @return [Onetime::Customer, nil]
      def find_existing_customer
        customer = Onetime::Customer.find_by_extid(@account[:external_id]) if @account[:external_id]
        customer ||= Onetime::Customer.find_by_email(@account[:email])
        customer
      end

      # Creates a new customer from Rodauth account data
      # @return [Onetime::Customer]
      def create_customer
        OT.info '[sync-session] Customer not found, creating from Rodauth account'

        customer = Onetime::Customer.create!(
          email: @account[:email],
          role: 'customer',
          verified: rodauth_status_verified? ? '1' : '0'
        )

        OT.info "[sync-session] Created Customer: #{customer.custid} with extid: #{customer.extid}"
        customer
      end

      # Checks if the Rodauth account status is verified (status_id == 2)
      # @return [Boolean]
      def rodauth_status_verified?
        @account[:status_id] == 2
      end

      # Checks if customer is already linked to the Rodauth account
      # @return [Boolean]
      def customer_linked?(customer)
        @account[:external_id] == customer.extid
      end

      # Links the customer record to the Rodauth account via external_id
      # @param customer [Onetime::Customer]
      def link_customer_to_account(customer)
        @db[:accounts]
          .where(id: @account_id)
          .update(external_id: customer.extid)

        OT.info "[sync-session] Linked Customer #{customer.custid} to account #{@account_id}"
      end

      # Populates the application session with user data
      # @param customer [Onetime::Customer]
      def populate_session(customer)
        @session['authenticated'] = true
        @session['authenticated_at'] = Familia.now.to_i
        @session['account_id'] = @account_id
        @session['external_id'] = customer.extid
        @session['email'] = customer.email
        @session['role'] = customer.role
        @session['locale'] = customer.locale || 'en'
      end

      # Tracks request metadata in the session
      def track_request_metadata
        @session['ip_address'] = @request.ip
        @session['user_agent'] = @request.user_agent
      end
    end
  end
end
