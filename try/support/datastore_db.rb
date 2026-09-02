# try/support/datastore_db.rb
#
# frozen_string_literal: true

# Single source of the valkey DB index a raw (non-lane-runner) tryout run
# uses. test_helpers.rb consults it to pick the database a run connects to,
# and `pnpm run test:database:clean` shells out to it so the documented
# cleanup reaches the same database the runs actually wrote — the two MUST
# derive identically or cleanup silently targets the wrong index.
#
# Resolution order mirrors tests/lanes/run: a valid LANES_DATASTORE_DB in
# the env wins (runner-launched, or a human pinning one — e.g.
# `LANES_DATASTORE_DB=0 pnpm run test:database:clean` to sweep the legacy
# shared DB); CI keeps 0 (its services are job-exclusive); otherwise derive
# from this checkout's own path into the same 1..65535 space the runner
# uses, 0 staying "the shared legacy DB".
#
# Runnable directly: prints the resolved index on stdout.
module TryoutsDatastoreDB
  module_function

  def checkout
    File.expand_path(File.join(__dir__, '..', '..'))
  end

  # The runner's <lane>|<overlays>|<root> shape (empty overlays), so its
  # `_lanes:owner` preflight and ours can read each other's claims.
  def isolation_key
    "try||#{checkout}"
  end

  def provided
    db = ENV['LANES_DATASTORE_DB'].to_s
    db if db.match?(/\A\d+\z/) && db.to_i <= 65_535
  end

  def index
    provided || (ENV['CI'] ? '0' : derived)
  end

  def derived
    require 'zlib'
    (1 + (Zlib.crc32(isolation_key) % 65_535)).to_s
  end
end

puts TryoutsDatastoreDB.index if $PROGRAM_NAME == __FILE__
