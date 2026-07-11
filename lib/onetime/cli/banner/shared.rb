# lib/onetime/cli/banner/shared.rb
#
# frozen_string_literal: true

# Shared utilities for banner CLI commands.
# Provides duration formatting used by set and show subcommands.

module Onetime
  module CLI
    module Banner
      module Shared
        BANNER_KEY = 'global_banner'

        # Public identity recorded as the audit actor for banner mutations made
        # from the shell. Mirrors Customers::Shared::CLI_ACTOR — a sentinel PUBLIC
        # id, never an internal objid (AdminAuditEvent requires a public actor).
        CLI_ACTOR = 'cli'

        def humanize_seconds(seconds)
          if seconds >= 86_400
            format('%dd %dh', seconds / 86_400, (seconds % 86_400) / 3600)
          elsif seconds >= 3600
            format('%dh %dm', seconds / 3600, (seconds % 3600) / 60)
          elsif seconds >= 60
            format('%dm %ds', seconds / 60, seconds % 60)
          else
            format('%ds', seconds)
          end
        end
      end
    end
  end
end
