require 'annoy'
require 'drydock'
require 'onetime'
require 'familia/tools'

#::SCRIPT_LINES__ = {} unless defined? ::SCRIPT_LINES__

class OT::CLI < Drydock::Command

  def register_build
    begin
      Onetime::VERSION.increment! argv.first
      puts Onetime::VERSION.inspect
    rescue => ex
      puts ex.message
      exit 1
    end
  end
  
  def entropy
    puts OT::Entropy.count
  end
  
  def clear_entropy
    OT::Entropy.values.clear
    entropy
  end
  
  def generate_entropy
    option.count = 100_000 if option.count.to_i > 100_000
    OT::Entropy.generate option.count
    entropy
  end
  
  def move_keys
    sourcedb, targetdb, filter = *argv
    raise "No target database supplied" unless sourcedb && targetdb
    raise "No filter supplied" unless filter
    source_uri = URI.parse Familia.uri.to_s
    target_uri = URI.parse Familia.uri.to_s
    source_uri.db, target_uri.db = sourcedb, targetdb
    Familia::Tools.move_keys filter, source_uri, target_uri do |idx, type, key, ttl|
      if global.verbose > 0
        puts '%4d (%6s, %4d): %s' % [idx+1, type, ttl, key] 
      else
        print "\rMoved #{idx+1} keys"
      end
    end
    puts
  end
end
