# lib/onetime/services/auth/disabled_auth_adapter.rb

module Auth
  class DisabledAuthAdapter
    attr_reader :env

    def initialize(env)
      @env = env
    end

    def authenticate(*)
      false
    end

    def logout
      session = env['rack.session']
      session.clear
      { success: true }
    end

    def current_identity
      nil
    end

    def authenticated?
      false
    end

    private

    def dummy_customer(*)
      Onetime::Customer.dummy
    end

    def authentication_failure
      {
        success: false,
        error: 'Not available',
      }
    end
  end
end
