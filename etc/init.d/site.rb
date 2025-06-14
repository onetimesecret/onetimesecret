# etc/init.d/site.rb

info 'Initializing site configuration'
debug "Script path: #{__FILE__}"
debug "Instance: #{instance}, Mode: #{mode}, Connect to DB: #{connect_to_db?}"

# Access the full config hash
debug "Full config keys: #{global.keys.join(', ')}"
debug "Full config is frozen: #{global.frozen?}"
debug "Section config is not frozen: #{config.frozen?}"

# Access the section-specific config (site section)
if config
  info "Site config loaded with #{config.keys.size} keys"
  debug "Site keys: #{config.keys.join(', ')}"

  # Example: Access specific site configuration
  if config['host']
    info "Site host: #{config['host']}"
  end

  if config['ssl']
    info "SSL enabled: #{config['ssl']}"
  end
else
  error 'No site configuration found'
end

# You can modify the configuration here if needed
# config['middleware'] = Time.now.to_i if config['site']
