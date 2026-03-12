# apps/web/auth/try/database_extensions_try.rb
#
# frozen_string_literal: true

# Database Extensions Test
#
# Verifies that Sequel date_arithmetic extension is loaded on database
# connections. Without this extension, Rodauth OTP lockout features fail
# with NoMethodError on date_add_sql_append. See #2643.

require 'sequel'

# Simulate the pattern used in Auth::Database.create_lazy_connection
# and create_connection: connect then load extension.
@db = Sequel.sqlite
@db.extension :date_arithmetic

## Database connection can generate date_add SQL
sql = @db.literal(Sequel.date_add(Sequel::CURRENT_TIMESTAMP, days: 1))
sql.include?('CURRENT_TIMESTAMP')
#=> true

## Sequel.date_add returns a DateAdd expression
Sequel.date_add(Sequel::CURRENT_TIMESTAMP, days: 1).is_a?(Sequel::SQL::DateAdd)
#=> true

## Sequel.date_sub also works with the extension
Sequel.date_sub(Sequel::CURRENT_TIMESTAMP, hours: 2).is_a?(Sequel::SQL::DateAdd)
#=> true

## Connection without date_arithmetic cannot generate date_add SQL
@db_bare = Sequel.sqlite
begin
  @db_bare.literal(Sequel.date_add(Sequel::CURRENT_TIMESTAMP, days: 1))
  false
rescue NoMethodError
  true
end
#=> true
