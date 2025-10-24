# lib/onetime/initializers/configure_rhales.rb

require 'rhales'

# Session wrapper that adapts Rack session to Rhales expectations
#
# Rhales expects sessions to respond to #authenticated?, but Rack sessions don't have this method.
# This wrapper delegates everything to the underlying session while providing the authentication
# interface that Rhales needs.
class OnetimeSessionAdapter < SimpleDelegator
  def authenticated?
    # Otto authentication logic: requires session['authenticated'] == true AND external_id present
    self['authenticated'] == true && self['external_id'].to_s.length > 0
  end
end

# Configure Rhales framework for Onetime Secret
#
# This initializer sets up Rhales to:
# - Use existing CSP nonce from request environment
# - Inject hydration scripts in <head> for Vue.js SPA compatibility
# - Set template paths to match existing structure
#
Rhales.configure do |config|
  # Use existing nonce from Onetime Secret middleware
  # This ensures all script tags use the same CSP nonce
  config.nonce_header_name = 'onetime.nonce'

  # Inject hydration scripts in <head> before Vue.js initialization
  # :earliest ensures window.__ONETIME_STATE__ is available when Vue mounts
  config.hydration.injection_strategy = :earliest

  # Vue.js mounts to #app, ensure hydration happens before mount
  config.hydration.mount_point_selectors = ['#app']

  # Set template paths to match existing structure
  templates_dir = File.join(__dir__, '..', '..', '..', 'apps', 'web', 'core', 'templates')
  config.template_paths = [templates_dir]
end

OT.ld "[Rhales] Configured with nonce_header: onetime.nonce, injection: :earliest" if defined?(OT)
