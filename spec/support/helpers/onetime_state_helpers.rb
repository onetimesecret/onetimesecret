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

  # Snapshot of the Familia + infrastructure globals that SetupConnectionPool
  # (and the ConfigureFamilia initializer that runs before it) mutate. Returned
  # as a plain Hash so the caller can pass it to restore_familia_pool_config.
  #
  # Captures:
  # - Familia.connection_provider — the lambda pointing at the process-local pool
  # - Familia.uri — the default URI used when no provider is installed
  # - Familia.transaction_mode / pipelined_mode — the :warn/:raise flags
  # - Onetime::Runtime.infrastructure.database_pool — the live ConnectionPool
  #
  # Raw ivar access is used for values whose public setters reject nil
  # (transaction_mode, pipelined_mode) or normalize the input in ways that
  # make a clean-slate round-trip impossible (uri).
  #
  # @return [Hash]
  def snapshot_familia_pool_config
    {
      connection_provider: Familia.connection_provider,
      uri:                 Familia.instance_variable_get(:@uri),
      transaction_mode:    Familia.instance_variable_get(:@transaction_mode),
      pipelined_mode:      Familia.instance_variable_get(:@pipelined_mode),
      database_pool:       Onetime::Runtime.infrastructure.database_pool,
    }
  end

  # Restore Familia + infrastructure globals from a snapshot. Uses public
  # setters where they exist. Notes:
  # - Familia.transaction_mode= and pipelined_mode= validate their input and
  #   reject nil, so nil round-trips via the raw ivar.
  # - Familia.uri= calls normalize_uri which substitutes the current default
  #   when given nil; the raw ivar is the only way to put a previous value
  #   (including URI objects or nil) back verbatim.
  # - Runtime.update_infrastructure is the canonical path for mutating the
  #   frozen infrastructure Data object; passing database_pool: nil clears
  #   the pool so a subsequent Onetime.boot! re-installs a fresh one.
  #
  # @param snapshot [Hash] from snapshot_familia_pool_config
  # @return [void]
  def restore_familia_pool_config(snapshot)
    Familia.connection_provider = snapshot[:connection_provider]
    Familia.instance_variable_set(:@uri, snapshot[:uri])
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
    Onetime::Runtime.update_infrastructure(database_pool: snapshot[:database_pool])
  end
end
