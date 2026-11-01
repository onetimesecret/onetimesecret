# spec/support/helpers/legacy_custom_domain_records.rb
#
# frozen_string_literal: true

require 'securerandom'

# CustomDomain records as they sit in the datastore when they were registered
# before ascii_display_domain_index existed: the JSON-encoded hash
# (including extid), the extid_lookup entry, the exact display_domain_index
# entry, an instances member, and no ASCII entry. Written with raw
# commands so no model hook (create!, IdentityGuard) adds the ASCII entry.
#
# extid and extid_lookup are written the way Familia 2.12.0's save writes
# them: the extid derived from the objid, stored as a JSON-encoded field, and
# extid_lookup[extid] holding the JSON-encoded identifier (extid_lookup is a
# plain class_hashkey, not a reference index). find_by_extid, which the
# operator commands resolve an extid with, reads that entry.
#
# Include in a spec that talks to the real datastore. Each writer returns the
# record's identifier; remove what you wrote with remove_legacy_custom_domain.
module LegacyCustomDomainRecords
  # @param display_domain [String] stored exactly as given
  # @param org_id [String, nil] nil writes an orphan (no org_id field)
  # @param fields [Hash{String => Object}] extra fields, JSON-encoded like
  #   Familia writes them
  # @return [String] the record's identifier
  def write_legacy_custom_domain(display_domain, org_id:, fields: {})
    model          = Onetime::CustomDomain
    id             = SecureRandom.uuid_v7
    extid          = legacy_custom_domain_extid(id)
    now            = Familia.now.to_i
    hash           = {
      'objid' => id, 'extid' => extid, 'display_domain' => display_domain, 'created' => now, 'updated' => now
    }
    hash['org_id'] = org_id unless org_id.to_s.empty?
    hash.merge!(fields)

    client = model.dbclient
    client.hset(model.dbkey(id), hash.transform_values { |value| Familia::JsonSerializer.dump(value) })
    client.hset(model.extid_lookup.dbkey, extid, Familia::JsonSerializer.dump(id))
    client.hset(model.display_domain_index.dbkey, display_domain, id)
    client.zadd(model.instances.dbkey, now, id)
    id
  end

  # The extid Familia derives for a record with this objid.
  def legacy_custom_domain_extid(id)
    Onetime::CustomDomain.new(objid: id).extid
  end

  # Removes the hash, the extid_lookup entry, the exact index entry and the
  # instances member, and the ASCII entry when it names this record.
  def remove_legacy_custom_domain(id, display_domain)
    model     = Onetime::CustomDomain
    model.dbclient.del(model.dbkey(id))
    model.extid_lookup.remove_field(legacy_custom_domain_extid(id))
    model.display_domain_index.release_field(display_domain, id)
    model.dbclient.zrem(model.instances.dbkey, id)
    ascii_name = begin
      model.ascii_display_domain(display_domain)
    rescue Onetime::DomainValidation::AsciiHostname::ConversionError
      nil
    end
    model.ascii_display_domain_index.release_field(ascii_name, id) if ascii_name
  end
end
