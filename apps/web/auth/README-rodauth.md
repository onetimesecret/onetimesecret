# How to Hook Up Modular Configuration

## Pattern 1: Module Methods (Recommended)

The most clear approach for organizing configuration is by explicitly passing the Rodauth::Auth instance (`self` inside `configure do` block) to module methods that perform configuration. When everything is in a single `plugin :rodauth do` block, there's no ambiguity about what context the code is running in so calling a config method like `otp_issuer` directly is easy to follow. But once code is split into multiple files, it's less clear. By passing in self like `Auth::Config::Features.configure(self)`, we can give it a name like `def self.configure(auth)` and then call methods directly on `auth`, like `auth.otp_issuer 'Acme Inc.'`.

```ruby
# apps/web/auth/config.rb
require_relative 'config/features'
require_relative 'config/hooks'
require_relative 'config/email'

module Auth
  class Config < Rodauth::Auth
    configure do
      # 1. Enable features FIRST
      enable :login, :logout, :otp, :webauthn, ...

      # 2. Base configuration (database, HMAC, JSON, session)
      db Auth::Database.connection
      hmac_secret ENV['HMAC_SECRET']
      # ... base config

      # 3. Call modular configuration methods
      Auth::Config::Features.configure(self)
      Auth::Config::Hooks.configure(self)
      Auth::Config::Email.configure(self)
    end
  end
end
```

```ruby
# apps/web/auth/config/features.rb
module Auth::Config::Features
  def self.configure(auth)
    # auth is the Rodauth::Auth instance inside configure block
    # Call configuration methods directly on it
    auth.otp_issuer 'OneTimeSecret'
    auth.password_minimum_length 8
    # ... all feature configs
  end
end
```

```ruby
# apps/web/auth/config/hooks.rb
module Auth::Config::Hooks
  def self.configure(auth)
    # Define hooks by calling the hook methods on auth
    auth.after_login do
      OT.info "[auth] User logged in: #{account[:email]}"
      # ... hook logic
    end

    auth.after_two_factor_authentication do
      # ... MFA hook logic
    end
  end
end
```

Why this works:
- `self` inside `configure do` block is the Rodauth::Auth instance
- Passing `self` to modules gives them direct access to call config methods
- No `instance_eval` - just normal method calls
- Clean separation by domain (features, hooks, email)



## Recommended File Structure

Here's the complete idiomatic organization:

```
apps/web/auth/
├── router.rb                   # 150 lines - Roda routing
├── config.rb                   # 150 lines - Core config + orchestration
└── config/
    ├── base.rb                 # 100 lines - Database, HMAC, session, JSON
    ├── features/
    ├── hooks/
    ├── email.rb
    └── database.rb
```

## Updated config.rb (Orchestrator)

```ruby
# apps/web/auth/config.rb
require 'rodauth'
require_relative 'config/database'
require_relative 'config/base'
require_relative 'config/features'
require_relative 'config/hooks'
require_relative 'config/custom_methods'
require_relative 'config/email'

module Auth
  class Config < Rodauth::Auth
    configure do
      # 1. Enable all features (order matters!)
      enable :json, :login, :logout
      enable :create_account, :close_account, :change_password, :reset_password
      enable :verify_account unless ENV['RACK_ENV'] == 'test'
      enable :otp, :recovery_codes
      enable :lockout, :active_sessions, :remember if ENV['ENABLE_SECURITY_FEATURES'] != 'false'
      enable :email_auth if ENV['ENABLE_MAGIC_LINKS'] == 'true'
      enable :webauthn if ENV['ENABLE_WEBAUTHN'] == 'true'

      # 2. Configure subsystems (order: base → features → hooks)
      Auth::Config::Base.configure(self)
      Auth::Config::Features.configure(self)
      Auth::Config::CustomMethods.configure(self)
      Auth::Config::Email.configure(self)
      Auth::Config::Hooks.configure(self)  # Hooks last (may reference features)
    end
  end
end
```

## config/base.rb (Core Settings)

```ruby
# apps/web/auth/config/base.rb
module Auth::Config::Base
  def self.configure(auth)
    # Database
    auth.db Auth::Database.connection

    # HMAC secret
    hmac_value = ENV['HMAC_SECRET'] || ENV['AUTH_SECRET']
    if hmac_value.nil? || hmac_value.empty?
      if Onetime.production?
        raise 'HMAC_SECRET required in production'
      else
        hmac_value = 'dev-hmac-secret-change-in-prod'
      end
    end
    auth.hmac_secret hmac_value

    # JSON mode
    auth.json_response_success_key :success
    auth.json_response_error_key :error
    auth.json_response_field_error_key :'field-error'
    auth.only_json? true

    # Account configuration
    auth.account_id_column :id
    auth.login_column :email
    auth.login_label 'Email'
    auth.account_select [:id, :email, :status_id, :external_id]

    # Session
    auth.session_key 'account_id'
  end
end
```

## config/hooks.rb (All Hooks)

```ruby
# apps/web/auth/config/hooks.rb
module Auth::Config::Hooks
  def self.configure(auth)
    # Login lifecycle
    auth.after_login do
      OT.info "[auth] User logged in: #{account[:email]}"

      rate_limit_key = "login_attempts:#{account[:email]}"
      Familia.dbclient.del(rate_limit_key)

      # two_factor_partially_authenticated?
      # (two_factor_base feature) Returns true if the session is logged in, the
      # account has setup two factor authentication, but has not yet
      # authenticated with a second factor.
      #
      # uses_two_factor_authentication?
      # (two_factor_base feature) Whether the account for the current session has setup two factor authentication.
      #
      # @see https://github.com/jeremyevans/rodauth/blob/2.41.0/README.rdoc
      if two_factor_partially_authenticated?
        # MFA required - defer session sync
        session['account_id'] = account_id
        session['email'] = account[:email]
        session['mfa_pending'] = true
      else
        # Full session sync
        sync_customer_session
      end
    end

    auth.after_two_factor_authentication do
      OT.info "[auth] MFA complete for: #{account[:email]}"
      session.delete(:awaiting_mfa)

      sync_customer_session if session['mfa_pending']
    end

    # OTP hooks
    auth.before_otp_setup_route do
      # ... OTP setup logic
    end

    auth.after_otp_setup do
      session.delete(:otp_setup_raw)
      session.delete(:otp_setup_hmac)
    end

    # Password hooks
    auth.after_change_password do
      update_customer_password_metadata
    end

    # WebAuthn hooks (if enabled)
    if ENV['ENABLE_WEBAUTHN'] == 'true'
      auth.after_webauthn_setup do
        # ... webauthn logic
      end
    end
  end

  private

  def self.sync_customer_session
    # Helper method - can define here or in custom_methods.rb
  end
end
```

## config/custom_methods.rb (Method Overrides)

```ruby
# apps/web/auth/config/custom_methods.rb
module Auth::Config::CustomMethods
  def self.configure(auth)
    auth.auth_class_eval do
      # Redis session validation
      def redis_session_valid?
        return false unless session['authenticated_at']
        max_age = Onetime.auth_config.session['expire_after'] || 86400
        age = Familia.now - session['authenticated_at'].to_i
        age < max_age
      end

      def authenticated?
        super && redis_session_valid?
      end

      # OTP validation override
      alias_method :_original_otp_valid_code?, :otp_valid_code?

      def otp_valid_code?(oacode)
        # ... custom OTP validation
        _original_otp_valid_code?(oacode)
      end
    end

    # Override class-level methods
    auth.define_singleton_method(:login_response) do
      if json_request? && two_factor_partially_authenticated?
        json_response[:mfa_required] = true
      end
      super()
    end
  end
end
```

## Key Points

1. Don't subclass Config - you already have the subclass, just organize within it
2. Use module methods - `Auth::Config::Features.configure(self)` pattern
3. Pass `self` from configure block - it's the Rodauth::Auth instance
4. Call methods directly - `auth.otp_issuer 'Foo'` not `instance_eval`
5. Order matters: Enable features → base config → features → custom methods → hooks
6. Keep Config thin - just feature enablement + module calls (~150 lines)

## Anti-Patterns to Avoid

❌ Don't nest `instance_eval`:
```ruby
module Features
  def self.configure(auth)
    auth.instance_eval do  # NO!
      otp_issuer 'Foo'
    end
  end
end
```

❌ Don't create multiple Config subclasses:
```ruby
class RodauthFeatures < Config  # NO!
  configure do
    # ...
  end
end
```

✅ Do use direct method calls:
```ruby
module Features
  def self.configure(auth)
    auth.otp_issuer 'Foo'  # YES!
    auth.password_minimum_length 8
  end
end
```
