# apps/api/v2/spec/support/actor_attribution_helpers.rb
#
# frozen_string_literal: true

# Shared helpers for the secret lifecycle actor-attribution specs (#3639).
#
# `link_receipt_to_org!` and `owner_double` were copy-pasted identically across
# the burn/reveal/show logic specs; extracted here so sibling actor-attribution
# specs (#3640) reuse them and they cannot silently diverge if spawn_pair's
# field names ever change (PR #3696 review).
#
# `build_logic` is intentionally NOT shared: its signature differs per logic
# class (BurnSecret takes a positional customer to avoid swallowing bare-hash
# call sites; Reveal/ShowSecret take a keyword `customer:`).
#
# Methods run in the example instance, so RSpec's `double` and the Onetime
# models resolve exactly as they did inline. Include per example group:
#
#   RSpec.describe ... do
#     include ActorAttributionSpecHelpers
module ActorAttributionSpecHelpers
  # Persist an org on the receipt so the reveal/burn cascade fans its lifecycle
  # event (with actor attribution) out to a real, inspectable trail. The cascade
  # reloads the receipt from Redis, so org_id must be saved, not just set.
  def link_receipt_to_org!(receipt)
    org = Onetime::Organization.new(
      display_name: 'Actor Attribution Org',
      contact_email: "actor-#{SecureRandom.hex(6)}@example.com",
    ).tap(&:save)
    receipt.org_id = org.objid
    receipt.save_fields(:org_id)
    org
  end

  # An authenticated caller who owns `owner_objid`'s secret.
  def owner_double(owner_objid)
    double('Customer', custid: owner_objid, objid: owner_objid, anonymous?: false)
  end
end
