# lib/onetime/initializers.rb

module Onetime
  module Initializers

    # Load initializers dynamically
    Dir[File.join(File.dirname(__FILE__), 'initializers', '*.rb')].each do |file|
      OT.ld "[Initializers] Loading #{file}"
      require_relative file
    end

  end

  extend Initializers
end
