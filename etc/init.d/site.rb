# etc/init.d/site.rb


puts "We are inside of #{__FILE__}"
# require 'pry-byebug'; binding.pry;
p @config
p config if defined?(config)
p self.config
