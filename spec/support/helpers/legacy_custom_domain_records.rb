# spec/support/helpers/legacy_custom_domain_records.rb
#
# frozen_string_literal: true

require 'securerandom'

# CustomDomain records as they sit in the datastore when they were registered
# before canonical_display_domain_index existed: the JSON-encoded hash, the
# exact display_domain_index entry, an instances member, and no canonical
# entry. Written with raw commands so no model hook (create!, IdentityGuard)
# adds the canonical entry.
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
    now            = Familia.now.to_i
    hash           = { 'objid' => id, 'display_domain' => display_domain, 'created' => now, 'updated' => now }
    hash['org_id'] = org_id unless org_id.to_s.empty?
    hash.merge!(fields)

    client = model.dbclient
    client.hset(model.dbkey(id), hash.transform_values { |value| Familia::JsonSerializer.dump(value) })
    client.hset(model.display_domain_index.dbkey, display_domain, id)
    client.zadd(model.instances.dbkey, now, id)
    id
  end

  # Removes the hash, the exact index entry and the instances member, and the
  # canonical entry when it names this record.
  def remove_legacy_custom_domain(id, display_domain)
    model     = Onetime::CustomDomain
    model.dbclient.del(model.dbkey(id))
    model.display_domain_index.release_field(display_domain, id)
    model.dbclient.zrem(model.instances.dbkey, id)
    canonical = begin
      model.canonical_display_domain(display_domain)
    rescue Onetime::DomainValidation::AsciiHostname::ConversionError
      nil
    end
    model.canonical_display_domain_index.release_field(canonical, id) if canonical
  end
end
