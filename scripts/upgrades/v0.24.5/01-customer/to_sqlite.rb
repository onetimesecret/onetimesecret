#!/usr/bin/env ruby
# frozen_string_literal: true

# Loads a customer JSONL dump into a SQLite3 database for analysis.
#
# Each line is expected to be {"custid": "...", "object": {...}}, where the
# inner object carries fields like created/updated as string Unix timestamps.
# Those are promoted to TIMESTAMP columns (ISO 8601 UTC); the full object is
# preserved as JSON.
#
# Usage:
#   ruby scripts/upgrades/v0.24.5/01-customer/to_sqlite.rb INPUT.jsonl [OUTPUT.db]
#
# Defaults: OUTPUT.db is INPUT with the .jsonl suffix replaced by .db.

require 'json'
require 'sqlite3'

BATCH_SIZE = 5_000

def epoch_to_iso8601(value)
  return nil if value.nil?
  epoch = Integer(value.to_s, 10) rescue nil
  return nil if epoch.nil?
  Time.at(epoch).utc.strftime('%Y-%m-%dT%H:%M:%SZ')
end

input_path  = ARGV[0] or abort 'usage: to_sqlite.rb INPUT.jsonl [OUTPUT.db]'
output_path = ARGV[1] || input_path.sub(/\.jsonl\z/, '') + '.db'

abort "input not found: #{input_path}" unless File.file?(input_path)

db = SQLite3::Database.new(output_path)
db.execute_batch(<<~SQL)
  PRAGMA journal_mode = WAL;
  PRAGMA synchronous  = NORMAL;
  PRAGMA temp_store   = MEMORY;

  CREATE TABLE IF NOT EXISTS customers (
    custid  TEXT PRIMARY KEY,
    created TIMESTAMP,
    updated TIMESTAMP,
    object  TEXT NOT NULL
  );

  CREATE INDEX IF NOT EXISTS idx_customers_created ON customers(created);
  CREATE INDEX IF NOT EXISTS idx_customers_updated ON customers(updated);
SQL

upsert = db.prepare(<<~SQL)
  INSERT INTO customers (custid, created, updated, object)
  VALUES (?, ?, ?, ?)
  ON CONFLICT(custid) DO UPDATE SET
    created = excluded.created,
    updated = excluded.updated,
    object  = excluded.object
SQL

count    = 0
skipped  = 0
started  = Time.now

db.transaction
File.foreach(input_path) do |line|
  line.strip!
  next if line.empty?

  record = begin
    JSON.parse(line)
  rescue JSON::ParserError => e
    warn "skip (invalid JSON line #{count + skipped + 1}): #{e.message}"
    skipped += 1
    next
  end

  custid = record['custid']
  obj    = record['object'] || {}
  unless custid.is_a?(String) && !custid.empty?
    warn "skip (missing custid at line #{count + skipped + 1})"
    skipped += 1
    next
  end

  created = epoch_to_iso8601(obj['created'])
  updated = epoch_to_iso8601(obj['updated'])
  upsert.execute(custid, created, updated, JSON.generate(obj))

  count += 1
  if (count % BATCH_SIZE).zero?
    db.commit
    db.transaction
    warn format('  %d loaded (%.1f rec/s)', count, count / (Time.now - started))
  end
end
db.commit

upsert.close
db.close

elapsed = Time.now - started
puts format('Loaded %d records (skipped %d) into %s in %.1fs',
            count, skipped, output_path, elapsed)
