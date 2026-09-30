# lib/onetime/sso_provider/ruby_saml_log_bridge.rb
#
# frozen_string_literal: true

module Onetime
  module SsoProvider
    # ruby-saml's default logger is `::Logger.new(STDOUT)` outside Rails
    # (ruby-saml logging.rb:7-12) and it logs the full AuthnRequest XML at
    # DEBUG (authrequest.rb:70). Route it through the application's Auth
    # logger instead, so it obeys the configured level, format and sinks.
    #
    # A bridge rather than the logger object itself: Onetime.get_logger
    # returns the boot-time cached logger once boot has finished, and this
    # file can be required before that — resolving per call always reaches
    # the configured one. ruby-saml only ever calls #debug and #info.
    module RubySamlLogBridge
      extend self

      [:debug, :info, :warn, :error].each do |level|
        define_method(level) do |message = nil, &block|
          message = block.call if message.nil? && block
          Onetime.get_logger('Auth').public_send(level, "[ruby-saml] #{message}")
        end
      end
    end
  end
end
