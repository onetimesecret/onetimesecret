# lib/onetime/services.rb

module Onetime
  # System services should not be started until after config freeze (OT.conf).
  #
  # System services are designed to start with frozen configuration.
  module Services
    # Load initializers dynamically
    Dir[File.join(File.dirname(__FILE__), 'services', '*.rb')].each do |file|
      OT.ld "[services] Loading #{file}"
      require_relative file
    end
  end

  extend Services
end
