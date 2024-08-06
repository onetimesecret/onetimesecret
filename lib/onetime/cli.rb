require 'drydock'
require 'onetime'
require 'familia/tools'

class OT::CLI < Drydock::Command
  def init
    OT.boot! :cli
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
        puts "#{idx + 1.to_s.rjust(4)} (#{type.to_s.rjust(6)}, #{ttl.to_s.rjust(4)}): #{key}"
      else
        print "\rMoved #{idx + 1} keys"
      end
    end
    puts
  end

  def register_build
    puts update_version_file
  end

  def customers
    puts '%d customers' % OT::Customer.values.size
  end

  def require_sudo
    return if Process.uid.zero?
    raise 'Must run as root or with sudo'
  end

  def get_git_hash
    `git rev-parse --short HEAD`.strip
  end
  private :get_git_hash

  def update_version_file
    data = YAML.load_file('VERSION.yml')
    data[:build] = get_git_hash
    File.write('VERSION.yml', data.to_yaml)
    data[:build]
  end
  private :update_version_file

end
