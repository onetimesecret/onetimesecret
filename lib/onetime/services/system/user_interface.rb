# lib/onetime/services/system/user_interface.rb

require_relative '../service_provider'

module Onetime
  module Services
    module System

      # TODO: I'm confused by what I was planning here. We _may_ need code that
      # makes sure the authentication UI settings make sense (can't enable
      # sign up or sign in if authentication in general is disabled).
      # I'm pretty sure we don't need a user_interface provider though. Actually
      # when you throw the word provider in there it's starting to sound useful.
      # When RuntimeConfigService loads the config from the db, do we include the
      # described UI logic there? Or does it just make the dynamic config
      # available and then ping's the interested provider(s)? Concurrent
      # has an Observable class.


      class UserInterface < ServiceProvider
        # Process the authentication config to make
        # sure the settings make sense. For example,
        # the signup and signin flags should explicitly
        # be set to false if authentication is disabled.

        def initialize
          super(:boot_receipt, type: TYPE_CONFIG, priority: 20)
        end

        def start(*)
          # Need to grab from MutableConfig
          ServiceRegistry.set_state(:ui, {})
        end

      end
    end
  end
end
