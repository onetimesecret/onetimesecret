# lib/onetime/cli/move_keys_command.rb

module Onetime
  class MoveKeysCommand < Drydock::Command
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
  end
end
