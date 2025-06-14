# lib/onetime/services.rb

module Onetime
  module Services
    # Load initializers dynamically
    Dir[File.join(File.dirname(__FILE__), 'services', '*.rb')].each do |file|
      OT.ld "[services] Loading #{file}"
      require_relative file
    end
  end

  extend Services
end
