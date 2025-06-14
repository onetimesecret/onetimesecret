# lib/onetime/services/system.rb

module Onetime
  module Services

    module System
      # Load system services dynamically
      Dir[File.join(File.dirname(__FILE__), 'system', '*.rb')].each do |file|
        OT.ld "[system] Loading #{file}"
        require_relative file
      end
    end

  end
end
