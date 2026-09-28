# try/unit/models/custom_domain_destroy_canonical_release_try.rb
#
# frozen_string_literal: true

# CustomDomain.destroy! releases the canonical display-domain claim from
# inside Familia's destroy transaction.
#
# The canonical gate (canonical_display_domain_index) folds the Unicode and
# A-label spellings of a name onto one field. It is app-managed, not a declared
# Familia index, so destroy! has to release it itself. Releasing after the
# MULTI would let a Redis failure in between leave a claim naming a record
# that no longer exists; create! reads such a claim as another organization's
# in-flight registration and refuses both spellings. The release is queued in
# the same MULTI as the record delete (CustomDomain#remove_from_class_indexes!),
# and it stays ownership-checked: a claim held by a different identifier is
# left alone.

require_relative '../../support/test_helpers'
require 'securerandom'

OT.boot! :test

@suffix = "#{Familia.now.to_i}#{SecureRandom.hex(3)}"
@owner  = Onetime::Customer.create!(email: "canon_release_#{@suffix}@test.com")
@org    = Onetime::Organization.create!('CanonRelease Corp', @owner, "canon_release_#{@suffix}@corp.com")
@org.define_singleton_method(:billing_enabled?) { false }

@index = Onetime::CustomDomain.canonical_display_domain_index

# Record every release on the canonical index with whether a Familia
# transaction was open at the time. The index object is frozen, so the
# recorder is prepended to HashKey and gated on this index's key.
@release_calls = []
module CanonicalReleaseRecorder
  class << self
    attr_accessor :dbkey, :calls
  end

  def release_field(field, val)
    ret = super
    if CanonicalReleaseRecorder.calls && dbkey == CanonicalReleaseRecorder.dbkey
      CanonicalReleaseRecorder.calls << { field: field, val: val, in_transaction: !Fiber[:familia_transaction].nil?, queued: ret }
    end
    ret
  end
end

CanonicalReleaseRecorder.dbkey = @index.dbkey
CanonicalReleaseRecorder.calls = @release_calls
Familia::HashKey.prepend(CanonicalReleaseRecorder)

@unicode_name = "bücher-#{@suffix}.com"
@canonical    = Onetime::CustomDomain.canonical_display_domain(@unicode_name)
@domain       = Onetime::CustomDomain.create!(@unicode_name, @org.objid)

## The class-level index is one shared object, so the recorder sees destroy!'s release
Onetime::CustomDomain.canonical_display_domain_index.equal?(@index)
#=> true

## create! claimed the canonical (A-label) form for this record
[@canonical.start_with?('xn--'), @index.get(@canonical)]
#=> [true, @domain.identifier]

## destroy! releases the claim and the record is gone
@release_calls.clear
@domain.destroy!
[@index.get(@canonical), Onetime::CustomDomain.find_by_identifier(@domain.identifier)]
#=> [nil, nil]

## The release ran once, for this record's canonical form, inside the destroy transaction
@release_calls.map { |c| [c[:field], c[:val], c[:in_transaction]] }
#=> [[@canonical, @domain.identifier, true]]

## Inside the MULTI the release is queued, so it returns a future rather than a count
@release_calls.first[:queued].class.name
#=> 'Redis::Future'

## Both spellings can be registered again after the release
@again = Onetime::CustomDomain.create!(@unicode_name, @org.objid)
@index.get(@canonical)
#=> @again.identifier

## A claim held by a different identifier survives the holder-less record's destroy!
@index[@canonical] = "other-#{@suffix}"
@again.destroy!
[@index.get(@canonical), Onetime::CustomDomain.find_by_identifier(@again.identifier)]
#=> ["other-#{@suffix}", nil]

# Teardown
CanonicalReleaseRecorder.calls = nil
@index.remove_field(@canonical)
[@domain, @again].each { |d| d.destroy! if d&.exists? }
@org.destroy! if @org&.exists?
@owner.destroy! if @owner&.exists?
