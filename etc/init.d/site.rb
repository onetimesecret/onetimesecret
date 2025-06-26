# etc/init.d/site.rb

# Handle potential nil global secret
# The global secret is critical for encrypting/decrypting secrets
# Running without a global secret is only permitted in exceptional cases
allow_nil     = global.dig('experimental', 'allow_nil_global_secret') || false # NOTE: 'global'

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
root_colonels                        = config.fetch('colonels', [])
auth_colonels                        = config.dig('authentication', 'colonels') || []
config['authentication']['colonels'] = (auth_colonels + root_colonels).compact.uniq

# Clear colonels and set to false if authentication is disabled
unless config.dig('authentication', 'enabled')
  config['authentication']['colonels'] = false
end

ttl_options = config.dig('secret_options', 'ttl_options')
default_ttl = config.dig('secret_options', 'default_ttl')

# if the ttl_options setting is a string, we want to split it into an
# array of integers.
if ttl_options.is_a?(String)
  config['secret_options']['ttl_options'] = ttl_options.split(/\s+/)
end
ttl_options = config.dig('secret_options', 'ttl_options')
if ttl_options.is_a?(Array)
  config['secret_options']['ttl_options'] = ttl_options.map(&:to_i)
end

if default_ttl.is_a?(String)
  config['secret_options']['default_ttl'] = default_ttl.to_i
end
