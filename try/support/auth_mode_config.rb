# try/support/auth_mode_config.rb
#
# Centralized authentication mode detection and test helpers
#
# Authentication Modes:
#   - disabled: No authentication required (simplest deployment)
#   - basic: Simple Redis-based auth via Core app (default)
#   - advanced: Full Rodauth with PostgreSQL database
#
# Usage in tests:
#   require_relative '../../support/auth_mode_config'
#   include AuthModeConfig
#   skip_unless_mode :basic
#
module AuthModeConfig
  # Get current authentication mode from environment
  def auth_mode
    ENV['AUTHENTICATION_MODE'] || 'basic'
  end

  # Check if authentication is completely disabled
  def auth_disabled?
    auth_mode == 'disabled'
  end

  # Check if running in basic mode (Core app auth)
  def basic_mode?
    auth_mode == 'basic'
  end

  # Check if running in advanced mode (Rodauth)
  def advanced_mode?
    auth_mode == 'advanced'
  end

  # Skip test file unless in required mode
  def skip_unless_mode(required_mode, message = nil)
    unless auth_mode == required_mode.to_s
      msg = message || "Test requires #{required_mode} mode (current: #{auth_mode})"
      OT.ld "SKIPPING: #{msg}"
      # Exit cleanly to avoid test failures
      exit 0
    end
  end

  # Skip test file if in specified mode
  def skip_if_mode(excluded_mode, message = nil)
    if auth_mode == excluded_mode.to_s
      msg = message || "Test skipped in #{excluded_mode} mode"
      OT.ld "SKIPPING: #{msg}"
      exit 0
    end
  end

  # Run block only in specified mode
  def with_mode(required_mode)
    yield if auth_mode == required_mode.to_s
  end

  # Check if Auth app should be mounted
  def auth_app_mounted?
    advanced_mode?
  end

  # Check if Core app handles auth routes
  def core_handles_auth?
    basic_mode? || auth_disabled?
  end

  # Get expected status for auth endpoints
  def expected_auth_status(endpoint_type = :login)
    case auth_mode
    when 'disabled'
      # Auth disabled - endpoints don't exist or return success without auth
      case endpoint_type
      when :login, :logout then 404
      when :protected then 200  # No protection
      else 404
      end
    when 'basic'
      # Core app handles auth
      case endpoint_type
      when :login then [200, 302, 400, 401]
      when :logout then [200, 302]
      when :protected then [200, 302, 401]
      else [200, 400]
      end
    when 'advanced'
      # Rodauth handles auth
      case endpoint_type
      when :login then [200, 401, 422]
      when :logout then [200, 204]
      when :protected then [200, 302, 401]
      else [200, 400, 422]
      end
    else
      500  # Unknown mode
    end
  end

  # Log which mode is active (for debugging)
  def log_auth_mode
    OT.ld "=" * 60
    OT.ld "AUTH MODE: #{auth_mode}"
    OT.ld "Auth App Mounted: #{auth_app_mounted?}"
    OT.ld "Core Handles Auth: #{core_handles_auth?}"
    OT.ld "=" * 60
  end
end
