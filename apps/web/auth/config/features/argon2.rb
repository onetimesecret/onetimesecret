# apps/web/auth/config/features/argon2.rb
#
# frozen_string_literal: true

module Auth::Config::Features
  # Argon2 password hashing configuration for Rodauth (full auth mode).
  #
  # Argon2id is a memory-hard password hashing algorithm that provides
  # improved resistance against GPU-based and ASIC-based attacks compared
  # to bcrypt. This is configured for full mode only - simple mode
  # handles argon2 directly in the Customer model.
  #
  # Configuration:
  #   Set ARGON2_SECRET environment variable for additional security.
  #   This secret is folded into the hash and provides defense-in-depth
  #   if the password hash database is compromised.
  #
  module Argon2
    def self.configure(auth)
      # Use argon2id for password hashing (more secure than bcrypt)
      auth.enable :argon2

      # Optional secret key for additional security.
      # If set, this is folded into the password hash.
      if (secret = ENV['ARGON2_SECRET'])
        auth.argon2_secret secret
      end

      # Hash cost parameters.
      # Production defaults: t_cost=2, m_cost=16 (64 MiB), p_cost=1
      # Test defaults are lower for faster test execution.
      if ENV['RACK_ENV'] == 'test'
        auth.password_hash_cost({ t_cost: 1, m_cost: 5, p_cost: 1 })
      else
        auth.password_hash_cost({ t_cost: 2, m_cost: 16, p_cost: 1 })
      end

      # Since full mode is new, we don't need bcrypt support.
      # This saves memory by not loading the bcrypt library.
      auth.require_bcrypt? false
    end
  end
end
