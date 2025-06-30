# etc/init.d/site.rb

# INIT SCRIPT CONFIGURATION GUIDE
# ================================
#
# This init script corresponds to the top-level `site` key in the static config.
#
# Two key variables are available:
#
# `global` - The complete, frozen configuration hash (read-only)
#            Use: global.dig('other_section', 'setting')
#            Access any configuration value across all sections
#
# `config` - The mutable configuration hash for THIS section only
#            Use: config['setting'] = value
#            Modify settings within this section's scope
#
# Example:
#   global.dig('experimental', 'allow_nil')   # read from other sections
#   config['host'] = 'http://127.0.0.1:9000'  # set values in current section
#   config.dig('authentication', 'enabled')   # read from current section
#
# @see InitScriptContext.

# Running without a global secret is only permitted vi opt-in
allow_nil     = global.dig('experimental', 'allow_nil_global_secret') || false

global_secret = config.fetch('secret', nil)
global_secret = nil if global_secret.to_s.strip == 'CHANGEME'

if global_secret.nil?
  unless allow_nil || OT.mode?(:cli)
    # Fast fail when global secret is nil and not explicitly allowed
    # This is a critical security check that prevents running without encryption
    abort 'Global secret cannot be nil - set SECRET env var or site.secret in config'
  end

  # SAFETY MEASURE: Security Warnings for Dangerous Configurations
  # Security warning when proceeding with nil global secret
  # These warnings are prominently displayed to ensure administrators
  # understand the security implications of their configuration
  warn <<~MSG

    #{'!' * 50}
    SECURITY WARNING: Running with nil global secret!
    This configuration presents serious security risks:
    - Secret encryption will be compromised
    - Data cannot be properly protected
    - Only use during recovery or transition periods
    Set valid SECRET env var or site.secret in config ASAP
    #{'!' * 50}

  MSG
end

# Set the state key for global secret, even if nil.
OT.state['global_secret'] = global_secret

# Disable all authentication sub-features when main feature is off for
# consistency, security, and to prevent unexpected behavior. Ensures clean
# config state.
# NOTE: Needs to run after other site.authentication logic
if config.dig('authentication', 'enabled') != true
  config['authentication'].each_key do |key|
    config['authentication'][key] = false
  end
end

# Combine colonels from root level and authentication section
# This handles the legacy config where colonels were at the root level
# while ensuring we don't lose any colonels from either location
legacy_colonels = config.fetch('colonels', [])
modern_colonels = config.dig('authentication', 'colonels') || []

config['authentication']['colonels'] = (modern_colonels + legacy_colonels).compact.uniq

unless config.dig('authentication', 'enabled')
  # Clear colonels and set to false if authentication is disabled
  config['authentication']['colonels'] = false

  # Also force autoverify to false.
  config['authentication']['autoverify'] = false
end
