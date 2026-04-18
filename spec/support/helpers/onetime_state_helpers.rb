# spec/support/helpers/onetime_state_helpers.rb
#
# frozen_string_literal: true

# Helpers for resetting and restoring Onetime / Familia global state between
# examples. Several integration specs (boot_part1_spec, boot_part2_spec,
# setup_connection_pool_spec) repeat the same instance_variable_set ladder;
# consolidating here keeps those specs from drifting as new module state is
# added.
module OnetimeStateHelpers
  # Module-level ivars that the boot process populates. No public reset API
  # exists on Onetime for these; instance_variable_set is the only lever.
  # Restricted to ivars the boot path actually touches to avoid clobbering
  # test-framework state.
  ONETIME_RESETTABLE_IVARS = %i[
    @conf
    @d9s_enabled
    @debug
    @i18n_enabled
    @supported_locales
    @default_locale
    @fallback_locale
    @locale
    @locales
    @instance
    @global_banner
  ].freeze

  # Reset the Onetime module to a pre-boot shape. Mirrors the block in
  # boot_part2_spec.rb and setup_connection_pool_spec.rb. Leaves @mode and
  # @env as :test / 'test' since most integration specs run in test mode.
  #
  # @return [void]
  def reset_onetime_module_state!
    ONETIME_RESETTABLE_IVARS.each { |ivar| Onetime.instance_variable_set(ivar, nil) }
    Onetime.instance_variable_set(:@mode, :test)
    Onetime.instance_variable_set(:@env, 'test')
    OT::Utils.instance_variable_set(:@fortunes, nil)
    Onetime.not_ready
  end

  # Snapshot of the three Familia pool-related globals that SetupConnectionPool
  # mutates. Returned as a plain Hash so the caller can pass it to
  # restore_familia_pool_config. Uses public readers; raw ivar access is only
  # needed for the writers (see below).
  #
  # @return [Hash]
  def snapshot_familia_pool_config
    {
      connection_provider: Familia.connection_provider,
      transaction_mode:    Familia.instance_variable_get(:@transaction_mode),
      pipelined_mode:      Familia.instance_variable_get(:@pipelined_mode),
    }
  end

  # Restore Familia pool-related globals from a snapshot. Uses public setters
  # where they exist. Note: Familia.transaction_mode= and pipelined_mode=
  # validate their input and reject nil, so we round-trip nil via the raw ivar
  # rather than let the setter raise ArgumentError on a clean-slate snapshot.
  #
  # @param snapshot [Hash] from snapshot_familia_pool_config
  # @return [void]
  def restore_familia_pool_config(snapshot)
    Familia.connection_provider = snapshot[:connection_provider]
    if snapshot[:transaction_mode].nil?
      Familia.instance_variable_set(:@transaction_mode, nil)
    else
      Familia.transaction_mode = snapshot[:transaction_mode]
    end
    if snapshot[:pipelined_mode].nil?
      Familia.instance_variable_set(:@pipelined_mode, nil)
    else
      Familia.pipelined_mode = snapshot[:pipelined_mode]
    end
  end
end
