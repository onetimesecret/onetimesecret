# etc/init.d/site.rb

log_info "Initializing site configuration"
log_debug "Script path: #{__FILE__}"
log_debug "Instance: #{instance}, Mode: #{mode}, Connect to DB: #{connect_to_db?}"

puts "We are inside of #{__FILE__}"
# require 'pry-byebug'; binding.pry;
p @config
p config if defined?(config)
p self.config
