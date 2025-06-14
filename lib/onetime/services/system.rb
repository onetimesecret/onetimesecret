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

__END__
require_relative 'system/boot'
require_relative 'system/set_global_secret'   # TODO: Combine into
require_relative 'system/set_rotated_secrets' # set_secrets
require_relative 'system/load_locales'
require_relative 'system/connect_databases'
require_relative 'system/prepare_emailers'
require_relative 'system/load_fortunes'
require_relative 'system/check_global_banner'
require_relative 'system/load_plans'
require_relative 'system/configure_truemail'
require_relative 'system/configure_domains'
require_relative 'system/setup_authentication'
require_relative 'system/setup_diagnostics'
require_relative 'system/setup_system_settings'
require_relative 'system/print_log_banner'
