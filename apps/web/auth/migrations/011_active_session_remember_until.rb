# apps/web/auth/migrations/011_active_session_remember_until.rb
#
# frozen_string_literal: true

# "Remember me" deadline per active-session row.
#
# A login with the remember-me box ticked stays signed in for a fixed 14 days
# from sign-in (lib/onetime/session/remember_me.rb). The row carries that
# deadline so the two readers of the inactivity deadline,
# Onetime::ActiveSessionGate on every request and Rodauth's sweep on the
# sessions page, can exempt the row from it until then and end it after.
#
#   NULL       the session was not remembered (every row before this ships):
#              the 72-hour inactivity deadline applies, as today
#   timestamp  remembered until then, in the database's clock like
#              created_at and last_use; no inactivity deadline before it,
#              refused after it
#
# The 30-day lifetime deadline applies to both.
#
# NULLABLE with no backfill: no existing session was remembered (the
# checkbox had no effect before this). No index: the column is only read on
# rows already selected by the primary key or by account_id.

Sequel.migration do
  up do
    alter_table(:account_active_session_keys) do
      add_column :remember_until, Time, null: true, default: nil
    end
  end

  down do
    alter_table(:account_active_session_keys) do
      drop_column :remember_until
    end
  end
end
