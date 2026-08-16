# try/unit/safe_dumpable_try.rb
#
# frozen_string_literal: true

# Unit tryouts for the value-object serialization boundary (ADR-040):
#   Onetime::SafeDumpable
#
# The Data/value-object counterpart of the Familia::Horreum safe_dump boundary.
# The load-bearing contract:
#   * #to_h      FULL, internal (Data's default); may carry internal members.
#   * #safe_dump POSITIVE allow-list; the ONLY shape that may cross a boundary.
# So "serialize safe_dump, never to_h" holds uniformly for models AND value rows.
#
# Run: try --agent try/unit/safe_dumpable_try.rb

require_relative '../support/test_helpers'

require 'onetime/safe_dumpable'

# A representative value object: one public member, one internal join key.
Row = Data.define(:public_id, :internal_token) do
  include Onetime::SafeDumpable
  safe_dump_fields :public_id
end

@row = Row.new(public_id: 'pub_1', internal_token: 'tok_secret')

## safe_dump exposes ONLY the declared allow-list
@row.safe_dump
#=> { public_id: 'pub_1' }

## the internal member is absent from safe_dump
@row.safe_dump.key?(:internal_token)
#=> false

## to_h is the full internal dump: the internal member IS present
@row.to_h
#=> { public_id: 'pub_1', internal_token: 'tok_secret' }

## an undeclared allow-list yields an empty safe_dump (fail-closed, not fail-open)
Bare = Data.define(:a, :b) do
  include Onetime::SafeDumpable
end
Bare.new(a: 1, b: 2).safe_dump
#=> {}

## safe_dump_fields with no args reads the current allow-list
Row.safe_dump_fields
#=> [:public_id]

## a class may override #safe_dump when its projection is a single already-safe member
Wrapper = Data.define(:body, :join_key) do
  include Onetime::SafeDumpable
  def safe_dump
    body
  end
end
w = Wrapper.new(body: { name: 'x' }, join_key: 'k')
[w.safe_dump, w.to_h.key?(:join_key)]
#=> [{ name: 'x' }, true]
