# Rodauth 2.41 Patterns & Architecture Cheatsheet

**Version**: Rodauth 2.41.0
**Primary Usage**: JSON API mode for headless authentication
**Documentation**: http://rodauth.jeremyevans.net
**Context7**: `/jeremyevans/rodauth`

## Core Architecture

### Feature-Based System

Rodauth operates as a modular authentication framework where all capabilities require explicit enablement. Nothing is available until explicitly enabled.

**Configuration Hierarchy**:
```
Base Feature (shared configuration)
├── Email Base (email-sending features)
├── Login/Password Requirements Base
├── Two Factor Base
└── Individual Features (login, logout, create_account, etc.)
```

**Enablement Pattern**:
```ruby
plugin :rodauth do
  enable :base, :login, :logout, :create_account, :verify_account
  # Configuration methods become available AFTER features are enabled
end
```

### Request/Response Lifecycle

1. **Request Processing**: Rodauth routes handle authentication endpoints
2. **Hook Execution**: before_rodauth → CSRF check → feature-specific before hooks
3. **Feature Logic**: Authentication, validation, database operations
4. **Session Management**: update_session or clear_session
5. **Hook Execution**: after hooks execute
6. **Response**: redirect (HTML) or JSON response body

### Integration Modes

**Three Primary Patterns**:

1. **HTML Forms** (default): Traditional web form-based flows with redirects
2. **JSON API**: RESTful endpoints with JSON request/response (our primary usage)
3. **JWT Support**: Token-based authentication with separate access/refresh tokens

**Internal Request Pattern**: Call Rodauth methods programmatically without HTTP layer

## JSON API Mode Configuration

### Essential JSON Settings

```ruby
plugin :rodauth do
  enable :json  # Must be enabled for JSON mode

  # Request validation
  json_check_accept? true                          # Validate Accept header (default: true)
  json_accept_regexp /(?:^|[,\s])*application\/json(?:$|[,\s]*)*/  # Accept header pattern
  json_request_content_type_regexp /application\/json/  # Content-Type validation

  # Response configuration
  json_response_content_type 'application/json'    # Response MIME type
  json_response_success_key 'success'              # Success message key
  json_response_error_key 'error'                  # Error message key
  json_response_field_error_key 'field-error'      # Field error array key

  # HTTP status codes
  json_response_custom_error_status? true          # Enable custom error statuses
  json_response_error_status 400                   # Default error status

  # Mode restrictions
  only_json? false                                 # Restrict to JSON-only requests
end
```

### JSON Request Format

**ALL requests use POST method**. Non-POST requests return `405 Method Not Allowed`.

```ruby
# Login request example
POST /login
Content-Type: application/json

{
  "login": "user@example.com",
  "password": "secure_password"
}
```

### JSON Response Patterns

**Success Response**:
```json
{
  "success": "You have been logged in"
}
```

**Error Response**:
```json
{
  "error": "There was an error logging in",
  "field-error": ["login", "invalid login"]
}
```

**Custom Response Modification**:
```ruby
# Modify json_response hash during request processing
json_response['reason'] = 'account_locked'
json_response['unlock_url'] = unlock_account_url
```

### CSRF Handling in JSON Mode

**Default Behavior**: CSRF protection disabled for JSON requests by default

**HTML Mode**: CSRF remains active when using HTML rendering alongside JSON

```ruby
check_csrf? true                    # Enable CSRF checking
check_csrf_opts {}                  # Options passed to Roda's check_csrf!
```

## Base Configuration Methods

### Account Management

```ruby
# Account retrieval
account_from_id(id, status_id=nil)  # Fetch account by ID and optional status
account_from_login(login)            # Fetch account by login credential
account_from_session                 # Get current session's account

# Account validation
open_account?                        # Check if account is open (not closed/unverified)
skip_status_checks?                  # Bypass status validation (default: true unless verify/close enabled)

# Database configuration
accounts_table :accounts             # Account table name
account_id_column :id                # Primary key column
account_status_column :status_id     # Status identifier column
```

### Session Management

```ruby
# Session configuration
session_key 'account_id'                           # Key storing logged-in account ID
authenticated_by_session_key 'authenticated_by'    # Key storing auth method array

# Session operations
update_session                       # Clear session, set session_key to account ID
clear_session                        # Remove all session data
account_session_value                # Value to store in session (defaults to account_id)

# Authentication checks
authenticated?                       # True only if MFA requirements met
logged_in?                          # True if session contains account_id
require_login                       # Enforce authentication gate
login_required                      # Action when login required but not authenticated
```

### Security Configuration

```ruby
# HMAC secrets (CRITICAL - always set these)
hmac_secret 'your-secret-key-min-32-chars'       # Current HMAC secret
hmac_old_secret 'previous-secret-for-rotation'   # Old secret for rotation

# CSRF protection
check_csrf? true                    # Enable CSRF validation (default: true for HTML)
check_csrf_opts {}                  # Options for Roda's check_csrf!
check_csrf                          # Execute CSRF validation

# Database authentication functions
use_database_authentication_functions? true  # Use DB functions for auth (PostgreSQL/MySQL/MSSQL)
```

### Routing & URL Configuration

```ruby
# Route prefixes
prefix '/auth'                      # Routing prefix (include leading slash, no trailing)

# URL configuration (RECOMMENDED for arbitrary Host headers)
base_url 'https://example.com'      # Base URL for absolute links
domain 'example.com'                # Domain for features requiring it

# Redirects
default_redirect '/'                # Default post-authentication destination
require_login_redirect              # Redirect destination to login page
redirect(path)                      # Redirect to specified path
```

### Hook Patterns

```ruby
# Global hooks
before_rodauth                      # Before any route, after CSRF checks
around_rodauth(&block)              # Wrap any Rodauth route handling
hook_action(hook_type, action)      # Process actions during hook lifecycle

# Authentication hooks
before_login                        # After password check, before session update
after_login                         # After successful authentication
after_login_failure                 # After failed authentication

# Account lifecycle hooks
before_create_account               # Before account insertion
after_create_account                # After successful creation
before_close_account                # Before account closure
after_close_account                 # After account closed
```

### Flash Messages

```ruby
# Flash configuration
flash_error_key :error              # Error message key (symbol or string)
flash_notice_key :notice            # Notice message key (symbol or string)

# Flash operations
set_error_flash(message)            # Set current error notification
set_notice_flash(message)           # Set next success notification
set_redirect_error_flash(message)   # Set error for post-redirect display
```

## Feature Configuration Patterns

### Login Feature

```ruby
enable :login

# Route configuration
login_route 'login'                               # Login endpoint path
login_redirect '/'                                # Post-login destination
login_return_to_requested_location? false         # Return to original request
login_return_to_requested_location_max_path_size 2048  # Max redirect path bytes

# Multi-phase login (separate login/password prompts)
use_multi_phase_login? false                      # Enable multi-phase flow
multi_phase_login_forms [:password]               # Auth method options
multi_phase_login_page_title 'Enter Password'     # Password phase title

# Generated methods
login()                             # Wrap login_session, run hooks, redirect
authenticated?                      # Verify current user status
require_login                       # Enforce authentication gate

# Hooks
before_login_route                  # Before processing login request
login_response                      # Handle post-authentication response

# Expected parameters
# { "login": "user@example.com", "password": "password123" }
```

### Create Account Feature

```ruby
enable :create_account

# Route configuration
create_account_route 'create-account'             # Registration endpoint
create_account_redirect '/'                       # Post-registration destination
create_account_set_password? true                 # Show password field (false if verify_account)

# Auto-login behavior
create_account_autologin? true                    # Auto-login after registration (false if verify_account)

# Generated methods
new_account(login)                  # Instantiate new account hash (not saved)
save_account                        # Persist account, return false on failure
set_new_account_password            # Assign password credentials

# Hooks
before_create_account               # Before account insertion
after_create_account                # After successful creation
before_create_account_route         # Intercept route handling
create_account_response             # Customize post-registration response

# Integration with verify_account
# When verify_account enabled:
# - create_account_set_password? defaults to false
# - create_account_autologin? defaults to false
# - User receives verification email
```

### Verify Account Feature

```ruby
enable :verify_account

# Verification flow
# 1. Account created with unverified status
# 2. Verification email sent with token
# 3. User clicks link or submits token
# 4. Account status updated to verified

# Database schema requirements
# - account_verification_keys table with token/deadline columns

# Configuration methods
verify_account_email_subject 'Verify Your Account'
verify_account_redirect '/'                       # Post-verification destination
verify_account_skip_resend_email_within 300       # Rate limiting (5 minutes)

# Generated methods
verify_account_email_sent?          # Check if verification email was sent
send_verify_account_email           # Dispatch verification email

# Hooks
before_verify_account               # Before verification processing
after_verify_account                # After successful verification
```

### Logout Feature

```ruby
enable :logout

# Route configuration
logout_route 'logout'                             # Logout endpoint
logout_redirect '/'                               # Post-logout destination

# Generated methods
logout                              # Clear session, run hooks, redirect

# Hooks
before_logout_route                 # Before processing logout
after_logout                        # After session cleared
logout_response                     # Customize post-logout response
```

### Reset Password Feature

```ruby
enable :reset_password

# Flow
# 1. User requests reset via email/login
# 2. Reset email sent with token
# 3. User submits new password with token
# 4. Password updated, token invalidated

# Route configuration
reset_password_route 'reset-password'             # Reset submission endpoint
reset_password_request_route 'reset-password-request'  # Request initiation

# Database schema
# - account_password_reset_keys table with token/deadline columns

# Configuration
reset_password_deadline_interval 86400            # Token validity (1 day)
reset_password_skip_resend_email_within 300       # Rate limiting

# Hooks
before_reset_password               # Before password update
after_reset_password                # After successful reset
reset_password_email_sent           # After email dispatched
```

### Change Password Feature

```ruby
enable :change_password

# Requires current password verification before allowing change

# Route configuration
change_password_route 'change-password'           # Password change endpoint
change_password_redirect '/'                      # Post-change destination

# Validation
require_password_confirmation? true               # Confirm new password
same_as_existing_password_message 'same as existing'  # Error for identical password

# Generated methods
change_password(password)           # Update password for current account

# Hooks
before_change_password              # Before password update
after_change_password               # After successful change
```

### Lockout Feature

```ruby
enable :lockout

# Brute force protection via login attempt tracking

# Threshold configuration
max_invalid_logins 100                            # Lockout trigger (default: 100)
account_lockouts_deadline_interval 86400          # Lockout duration (1 day)

# Database schema
# - account_lockouts table: id, key, deadline, email_last_sent
# - account_login_failures table: id, number (failure count)

# Generated methods
locked_out?                         # Check current account lockout status
invalid_login_attempted             # Increment failure counter, potentially lock
unlock_account(account_id)          # Remove lockout, optionally auto-login

# Auto-login on unlock
unlock_account_autologin? true      # Prevent attacker-initiated re-locking

# Email throttling
unlock_account_skip_resend_email_within 300       # Rate limiting (5 minutes)

# Hooks
after_account_lockout               # After lockout triggered
after_unlock_account                # After account unlocked

# Error messages
login_lockout_error_flash 'Account locked out'    # User notification
```

### Active Sessions Feature

```ruby
enable :active_sessions

# Tracks all concurrent login sessions in database

# Database schema
# - account_active_session_keys table: account_id, session_id, created_at, last_use

# Session lifecycle
add_active_session                  # Create and record new session
remove_current_session              # Logout current session
remove_all_active_sessions_except_current  # "Logout other sessions"
currently_active_session?           # Validate session existence

# Session validation
check_active_session                # Verify session_id in database

# Expiration configuration
session_inactivity_deadline 86400   # Expire after inactivity (1 day, nil to disable)
session_lifetime_deadline 2592000   # Expire by creation time (30 days, nil to disable)

# Usage pattern
# 1. On login: session_id stored in database
# 2. On request: check_active_session validates
# 3. On logout: session_id removed
# 4. Expired sessions auto-removed during validation
```

### Remember Feature

```ruby
enable :remember

# Cookie-based persistent login via tokens

# Database schema
# - account_remember_keys table: account_id, key, deadline

# Core configuration
remember_cookie_key '_remember'                   # Cookie name
remember_table :account_remember_keys             # Token storage table
remember_deadline_interval 1209600                # Token validity (14 days)
extend_remember_deadline? false                   # Auto-extend on use

# Cookie settings
remember_cookie_options {
  httponly: true,
  secure: true,
  path: '/'
}

# Generated methods
remember_login                      # Create token, set cookie
forget_login                        # Remove cookie (DB tokens remain)
disable_remember_login              # Invalidate DB tokens
load_memory                         # Check cookie, auto-login if valid
require_password_authentication     # Force password re-entry for sensitive ops

# Usage pattern
# Auto-remember on login:
after_login do
  remember_login
end

# Check remember token in routing:
rodauth.load_memory

# Security consideration
# Sessions logged in via remember token should require password for sensitive operations
```

### Close Account Feature

```ruby
enable :close_account

# Allows users to delete their own accounts

# Route configuration
close_account_route 'close-account'               # Account closure endpoint
close_account_redirect '/'                        # Post-closure destination

# Validation
close_account_requires_password? true             # Require password confirmation

# Generated methods
close_account                       # Mark account closed, clear session

# Hooks
before_close_account                # Before account closure
after_close_account                 # After account closed

# Account status
# Sets account status to closed, preventing future login
```

## Email Configuration

### Email Base Feature

Auto-enabled when using features requiring email delivery (verify_account, reset_password, etc.)

```ruby
# Addressing
email_from 'noreply@example.com'                  # Sender address
email_to                                          # Recipient (defaults to account login)

# Subject configuration
email_subject_prefix '[YourApp] '                 # Prepend to all subjects

# Delivery customization
require_mail? true                                # Require Mail gem (default: true)

# Override delivery method
def send_email(email)
  # Replace Mail gem with custom service
  YourMailService.deliver(
    to: email.to.first,
    from: email.from.first,
    subject: email.subject,
    body: email.body.to_s
  )
end

# Email generation
create_email(subject, body)         # Generate Mail::Message instance

# Token security
allow_raw_email_token? false        # Permit unencrypted tokens (use during HMAC migration only)

# Redirect behavior
default_post_email_redirect         # Landing page after email sent or rate limited
```

## Password Requirements

### Login Password Requirements Base

```ruby
enable :login_password_requirements_base

# Length constraints
password_minimum_length 6                         # Minimum characters (default: 6)
password_maximum_length nil                       # Maximum characters (nil = no limit)
password_maximum_bytes nil                        # Byte limit (consider 72 for bcrypt)

# Validation method (override for complexity rules)
def password_meets_requirements?(password)
  super && password.match?(/[A-Z]/) && password.match?(/[0-9]/)
end

# Hash configuration
password_hash_cost                  # Bcrypt cost factor
password_hash(password)             # Generate password hash
set_password(password)              # Update account password

# Confirmation
require_password_confirmation? true               # Require password confirmation field

# Error messages
password_too_short_message 'is too short'
password_too_long_message 'is too long'
password_too_many_bytes_message 'is too long'
password_does_not_meet_requirements_message 'does not meet requirements'
passwords_do_not_match_message 'do not match'
same_as_existing_password_message 'is the same as existing password'
```

## WebAuthn Configuration

### WebAuthn Feature (Multifactor)

```ruby
enable :webauthn

# Required configuration
webauthn_origin 'https://example.com'             # Origin for verification
webauthn_rp_id 'example.com'                      # Relying party identifier
webauthn_rp_name 'Your App Name'                  # Display name during registration

# Database schema
# - webauthn_keys table: account_id, webauthn_id, public_key, sign_count, last_use
# - webauthn_user_ids table: account_id, webauthn_id

# Authentication flow
# Setup:
# 1. Client requests options via webauthn_setup_js_route
# 2. Credential validated via valid_new_webauthn_credential?
# 3. Credential stored, user redirected per webauthn_setup_redirect

# Authentication:
# 1. Challenge via webauthn_auth_js_route
# 2. Credential validated via valid_webauthn_credential_auth?
# 3. Sign count verified (replay attack prevention)
# 4. Session updated via webauthn_update_session

# Generated methods
valid_new_webauthn_credential?      # Validate registration credential
valid_webauthn_credential_auth?     # Validate authentication credential
webauthn_update_session             # Update session after WebAuthn auth

# JavaScript integration required
# Browser-authenticator communication via Web Authentication API
```

### WebAuthn Login Feature (Passwordless)

```ruby
enable :webauthn_login

# Passwordless authentication via WebAuthn only

# Configuration
webauthn_login_route 'webauthn-login'             # Passwordless login endpoint

# Flow
# 1. User initiates login without password
# 2. WebAuthn challenge presented
# 3. Credential validated
# 4. Session established

# Requires same webauthn_origin, webauthn_rp_id, webauthn_rp_name settings
```

## Official Plugin Ecosystem

### Rodauth OAuth (rodauth-oauth gem)

OAuth 2.0 provider implementation

```ruby
gem 'rodauth-oauth'

plugin :rodauth do
  enable :oauth_authorization_code_grant
  enable :oauth_implicit_grant
  enable :oauth_client_credentials_grant
  enable :oauth_token_revocation

  # OAuth-specific configuration
  oauth_application_scopes ['read', 'write']
  oauth_token_type 'bearer'
end

# Provides OAuth 2.0 server capabilities:
# - Client registration
# - Authorization code flow
# - Token management
# - Scope-based authorization
```

### Rodauth OmniAuth (rodauth-omniauth gem)

Third-party authentication provider integration

```ruby
gem 'rodauth-omniauth'

plugin :rodauth do
  enable :omniauth_base
  enable :omniauth_login

  # Provider configuration
  omniauth_provider :google_oauth2, ENV['GOOGLE_KEY'], ENV['GOOGLE_SECRET']
  omniauth_provider :github, ENV['GITHUB_KEY'], ENV['GITHUB_SECRET']
end

# Enables authentication via:
# - Social providers (Google, Facebook, GitHub)
# - Enterprise providers (SAML, LDAP)
# - Custom OmniAuth strategies
```

### Rodauth Rails (rodauth-rails gem)

Rails framework integration

```ruby
gem 'rodauth-rails'

# Provides:
# - Rails-style configuration
# - Migration generators
# - Mailer integration
# - Controller concerns
# - View helpers

# Generator usage
rails generate rodauth:install
rails generate rodauth:migration create_account
```

### Rodauth i18n (rodauth-i18n gem)

Internationalization support

```ruby
gem 'rodauth-i18n'

plugin :rodauth do
  enable :i18n

  i18n_fallbacks [:es, :en]
  translate(key, default: nil)  # Lookup i18n translations
end

# Uses I18n gem for all user-facing strings
```

## Advanced Patterns

### Multi-Tenancy Support

```ruby
# Scope authentication to specific accounts table or tenant identifier

plugin :rodauth do
  enable :login

  # Tenant-specific accounts table
  accounts_table { "tenant_#{current_tenant_id}_accounts".to_sym }

  # Or add tenant_id to queries
  def account_from_login(login)
    ds = super
    ds.where(tenant_id: current_tenant_id)
  end
end
```

### Custom Features

```ruby
# Create custom authentication feature

module Rodauth
  Feature.define(:custom_2fa, :Custom2FA) do
    depends :two_factor_base

    # Define routes
    route 'custom-2fa-auth'

    # Add configuration methods
    auth_value_method :custom_2fa_table, :account_custom_2fa_keys

    # Implement authentication logic
    auth_methods(
      :custom_2fa_auth_valid?
    )

    def custom_2fa_auth_valid?(code)
      # Validation logic
    end

    # Add hooks
    def after_login
      require_custom_2fa_setup unless custom_2fa_configured?
      super
    end
  end
end

# Usage
plugin :rodauth do
  enable :custom_2fa
end
```

### Method Overriding Patterns

```ruby
plugin :rodauth do
  enable :login, :create_account

  # Override generated methods
  def account_from_login(login)
    # Add case-insensitive lookup
    ds = db[accounts_table]
    ds.where(Sequel.ilike(:email, login)).first
  end

  # Override validation
  def login_valid?
    super && account[:email_verified]
  end

  # Override response handling
  def login_response
    if json_request?
      json_response[:user] = account_json
    end
    super
  end

  # Add custom account data to JSON
  def account_json
    {
      id: account[:id],
      email: account[:email],
      name: account[:name]
    }
  end
end
```

### Rails vs Rack Integration Differences

**Rack (Roda) Integration**:
```ruby
class App < Roda
  plugin :rodauth do
    enable :login, :logout
  end

  route do |r|
    r.rodauth  # Mount Rodauth routes

    rodauth.require_authentication  # Enforce login

    r.root do
      view 'index'
    end
  end
end
```

**Rails Integration** (via rodauth-rails):
```ruby
# config/initializers/rodauth.rb
class RodauthApp < Rodauth::Rails::App
  configure do
    enable :login, :logout
  end
end

# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  include Rodauth::Rails::Auth

  before_action :require_authentication
end
```

Key differences:
- **Routing**: Roda uses block syntax, Rails uses generators
- **Controllers**: Roda inline, Rails controller concerns
- **Mailers**: Roda manual, Rails ActionMailer integration
- **Views**: Roda templates, Rails view helpers

## Security Features

### CSRF Protection

```ruby
# HTML mode (default)
check_csrf? true                    # Enable CSRF validation
check_csrf_opts {                   # Roda check_csrf! options
  only: ['POST', 'PUT', 'DELETE'],
  skip: []
}

# JSON mode
# CSRF disabled by default for JSON requests
# Session-based authentication still secure via SameSite cookies
```

### Session Security

```ruby
# Session configuration
session_key 'account_id'            # Session identifier key
authenticated_by_session_key 'authenticated_by'  # Auth method tracking

# Session timeout (requires active_sessions)
enable :active_sessions
session_inactivity_deadline 1800    # 30 minutes
session_lifetime_deadline 86400     # 24 hours

# Single session enforcement
enable :single_session
single_session_error_flash 'Already logged in elsewhere'
```

### Password Security

```ruby
# Hash algorithm
password_hash_algorithm :bcrypt     # Default
enable :argon2                      # Or use argon2 (recommended)

# Pepper (additional secret key)
password_pepper 'your-pepper-secret'  # Added to password before hashing

# Complexity requirements
def password_meets_requirements?(password)
  return false unless super
  password.match?(/[A-Z]/) &&       # Uppercase
  password.match?(/[a-z]/) &&       # Lowercase
  password.match?(/[0-9]/) &&       # Number
  password.match?(/[^A-Za-z0-9]/)   # Special character
end

# Password expiration
enable :password_expiration
password_expiration_default 7776000  # 90 days
```

### Audit Logging

```ruby
enable :audit_logging

# Database schema
# - account_authentication_audit_logs table
# Columns: id, account_id, at, message

# Logged events
audit_log_metadata_default { {ip: request.ip} }

# Generated methods
audit_log_message(message)          # Log authentication event

# Hook integration
after_login { audit_log_message('login') }
after_login_failure { audit_log_message('login_failure') }
```

### Account Security

```ruby
# Lockout (brute force protection)
enable :lockout
max_invalid_logins 5                # Stricter than default 100

# Email verification required
enable :verify_account
skip_status_checks? false           # Enforce status checks

# Account expiration
enable :account_expiration
account_expiration_default 31536000  # 1 year

# Password expiration
enable :password_expiration
require_password_change_after_account_creation? true
```

## Common Patterns for OneTimeSecret

### JSON API Configuration

```ruby
plugin :rodauth do
  enable :json, :login, :logout, :create_account, :verify_account,
         :reset_password, :change_password, :close_account,
         :lockout, :active_sessions, :remember

  # JSON mode
  only_json? true
  json_response_success_key 'success'
  json_response_error_key 'error'

  # Security
  hmac_secret ENV['RODAUTH_HMAC_SECRET']
  require_login_confirmation? false

  # Email
  email_from 'noreply@onetimesecret.com'
  def send_email(email)
    OTS::Email.deliver(email)
  end

  # Hooks for logging
  after_login { OTS.ld "[rodauth] login: #{account[:email]}" }
  after_create_account { OTS.ld "[rodauth] create: #{account[:email]}" }
end
```

### WebAuthn Passwordless Configuration

```ruby
plugin :rodauth do
  enable :webauthn_login, :webauthn_verify_account

  # WebAuthn settings
  webauthn_origin 'https://onetimesecret.com'
  webauthn_rp_id 'onetimesecret.com'
  webauthn_rp_name 'OneTimeSecret'

  # Allow passwordless only
  require_password? false

  # Auto-register WebAuthn on account creation
  after_create_account do
    set_redirect_error_flash verify_account_email_recently_sent_error_flash
    request.redirect(webauthn_setup_path)
  end
end
```

### Custom JSON Response

```ruby
plugin :rodauth do
  enable :json, :login

  # Add user data to login response
  def login_response
    if json_request?
      json_response[:user] = {
        id: account[:id],
        email: account[:email],
        verified: account[:verified],
        created_at: account[:created_at]
      }
    end
    super
  end

  # Include reason codes for errors
  def set_error_reason(reason)
    json_response[:reason] = reason if json_request?
  end

  # Override login failure to add reason
  def after_login_failure
    set_error_reason('invalid_credentials')
    super
  end
end
```

---

**Key Takeaways**:
1. All features require explicit enablement
2. JSON mode uses POST-only requests with structured responses
3. Configuration methods become available only after features are enabled
4. Override methods for customization, use hooks for side effects
5. Security settings (hmac_secret, session config) are critical
6. Email delivery requires custom send_email implementation
7. Feature interdependencies handled automatically (e.g., verify_account modifies create_account behavior)
