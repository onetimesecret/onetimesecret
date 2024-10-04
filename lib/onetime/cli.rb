require 'drydock'
require 'onetime'
require 'familia/tools'

class OT::CLI < Drydock::Command
  def init
    OT.boot! :cli
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
        puts "#{idx + 1.to_s.rjust(4)} (#{type.to_s.rjust(6)}, #{ttl.to_s.rjust(4)}): #{key}"
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
