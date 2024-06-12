require 'drydock'
require 'onetime'
require 'familia/tools'

# ::SCRIPT_LINES__ = {} unless defined? ::SCRIPT_LINES__

class OT::CLI < Drydock::Command
  def init
    OT.boot! :cli
  end

  def register_build
    Onetime::VERSION.increment! argv.first
    puts Onetime::VERSION.inspect
  rescue StandardError => e
    puts e.message
    exit 1
  end

  def entropy
    puts OT::Entropy.count
  end

  def clear_entropy
    require_sudo
    OT::Entropy.values.clear
    entropy
  end

  def generate_entropy
    # require_sudo
    option.count = 100_000 if option.count.to_i > 100_000
    OT::Entropy.generate option.count
    entropy
  end

  def move_keys
    sourcedb, targetdb, filter = *argv
    raise 'No target database supplied' unless sourcedb && targetdb
    raise 'No filter supplied' unless filter

    source_uri = URI.parse Familia.uri.to_s
    target_uri = URI.parse Familia.uri.to_s
    source_uri.db = sourcedb
    target_uri.db = targetdb
    Familia::Tools.move_keys filter, source_uri, target_uri do |idx, type, key, ttl|
      if global.verbose > 0
        puts format('%4d (%6s, %4d): %s', idx + 1, type, ttl, key)
      else
        print "\rMoved #{idx + 1} keys"
      end
    end
    puts
  end

  def customers
    puts '%d customers' % OT::Customer.values.size
  end

  def require_sudo
    return if Process.uid.zero?

    raise 'Must run as root or with sudo'
  end
end
