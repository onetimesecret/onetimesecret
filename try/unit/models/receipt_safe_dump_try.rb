# try/unit/models/receipt_safe_dump_try.rb
#
# frozen_string_literal: true

# These tryouts test the Receipt safe_dump functionality, specifically
# verifying that the secret_identifier field is properly included in
# the safe dump output. This field is critical for frontend data
# minimization where we need the full secret identifier for URL construction
# but want to avoid storing unnecessary sensitive data.

require_relative '../../support/test_models'

OT.boot! :test, true

@test_secret_identifier = 'veri:test-secret-abc123def456'
@test_secret_shortid = 'test-abc'

## Receipt includes secret_identifier in safe_dump_fields
fields = Receipt.safe_dump_fields
fields.include?(:secret_identifier)
#=> true

## Receipt includes secret_shortid in safe_dump_fields
fields = Receipt.safe_dump_fields
fields.include?(:secret_shortid)
#=> true

## Receipt safe_dump returns secret_identifier when set
receipt = Receipt.new
receipt.secret_identifier = @test_secret_identifier
dumped = receipt.safe_dump
dumped[:secret_identifier]
#=> @test_secret_identifier

## Receipt safe_dump returns secret_shortid when set
receipt = Receipt.new
receipt.secret_shortid = @test_secret_shortid
dumped = receipt.safe_dump
dumped[:secret_shortid]
#=> @test_secret_shortid

## Receipt safe_dump returns nil for secret_identifier when not set
receipt = Receipt.new
dumped = receipt.safe_dump
dumped[:secret_identifier]
#=> nil

## secret_shortid fallback: when empty, falls back to secret_identifier.slice(0,8)
receipt = Receipt.new
receipt.secret_identifier = @test_secret_identifier
receipt.secret_shortid = nil
dumped = receipt.safe_dump
dumped[:secret_shortid]
#=> @test_secret_identifier.slice(0, 8)

## secret_shortid fallback: empty string also triggers fallback
receipt = Receipt.new
receipt.secret_identifier = @test_secret_identifier
receipt.secret_shortid = ''
dumped = receipt.safe_dump
dumped[:secret_shortid]
#=> @test_secret_identifier.slice(0, 8)

## secret_shortid: when set, uses actual value (no fallback)
receipt = Receipt.new
receipt.secret_identifier = @test_secret_identifier
receipt.secret_shortid = @test_secret_shortid
dumped = receipt.safe_dump
dumped[:secret_shortid]
#=> @test_secret_shortid

## Receipt safe_dump includes both identifier and secret_identifier
receipt = Receipt.new
receipt.secret_identifier = @test_secret_identifier
dumped = receipt.safe_dump
[dumped.key?(:identifier), dumped.key?(:secret_identifier)]
#=> [true, true]

## Receipt safe_dump includes share_domain field
fields = Receipt.safe_dump_fields
fields.include?(:share_domain)
#=> true

## Receipt safe_dump returns share_domain when set
receipt = Receipt.new
receipt.share_domain = 'custom.example.com'
dumped = receipt.safe_dump
dumped[:share_domain]
#=> 'custom.example.com'

## Receipt safe_dump includes has_passphrase field
fields = Receipt.safe_dump_fields
fields.include?(:has_passphrase)
#=> true

## Receipt safe_dump returns has_passphrase correctly when no passphrase
receipt = Receipt.new
dumped = receipt.safe_dump
dumped[:has_passphrase]
#=> false

## Receipt safe_dump returns has_passphrase correctly when has_passphrase is set
receipt = Receipt.new
receipt.has_passphrase = true
dumped = receipt.safe_dump
dumped[:has_passphrase]
#=> true

## Receipt safe_dump includes secret_ttl field
fields = Receipt.safe_dump_fields
fields.include?(:secret_ttl)
#=> true

## Receipt safe_dump returns secret_ttl value when set
receipt = Receipt.new
receipt.secret_ttl = 3600
dumped = receipt.safe_dump
dumped[:secret_ttl]
#=> 3600

## Receipt safe_dump returns -1 for secret_ttl when not set (via lambda)
receipt = Receipt.new
dumped = receipt.safe_dump
dumped[:secret_ttl]
#=> -1

## Receipt safe_dump does NOT include passphrase field (security)
fields = Receipt.safe_dump_fields
fields.include?(:passphrase)
#=> false

## Receipt safe_dump output does NOT expose raw passphrase value
receipt = Receipt.new
receipt.has_passphrase = true
dumped = receipt.safe_dump
dumped.key?(:passphrase)
#=> false

## Receipt includes all minimal fields needed for frontend data minimization
required_fields = [:identifier, :secret_identifier, :secret_shortid, :share_domain, :has_passphrase, :secret_ttl, :created]
fields = Receipt.safe_dump_fields
required_fields.all? { |f| fields.include?(f) }
#=> true

## Receipt safe_dump includes shortid (for display)
fields = Receipt.safe_dump_fields
fields.include?(:shortid)
#=> true

## Receipt shortid is 8 characters from identifier
receipt = Receipt.new
dumped = receipt.safe_dump
receipt.identifier.slice(0, 8) == dumped[:shortid]
#=> true

## Created receipt can be destroyed (cleanup)
@receipt = Receipt.new :receipt
@receipt.secret_identifier = @test_secret_identifier
@receipt.save
exists_before = @receipt.exists?
@receipt.destroy!
exists_after = @receipt.exists?
[exists_before, exists_after]
#=> [true, false]
