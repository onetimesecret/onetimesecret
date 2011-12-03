require 'annoy'
require 'drydock'
require 'onetime'

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
  
end
