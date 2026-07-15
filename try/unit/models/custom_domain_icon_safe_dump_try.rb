# try/unit/models/custom_domain_icon_safe_dump_try.rb
#
# frozen_string_literal: true

# Tests for the :icon safe_dump projection on CustomDomain (#3780).
#
# The icon hashkey holds the stored favicon image + metadata. safe_dump must
# expose ONLY the string metadata (filename, content_type, favicon_source) so
# the workspace can gate the "Refresh favicon" button on provenance — a
# user_upload icon can't be re-fetched (FetchDomainFavicon#overwrite_guard).
# It must NEVER leak the base64 `encoded` bytes (huge) nor the numeric
# dimensions (stored as strings; would break the frontend's numeric schema).
#
# Scenarios:
#   1. Domain with no icon: safe_dump[:icon] is nil
#   2. Domain with an auto_fetch icon: metadata present, encoded dropped
#   3. Domain with a user_upload icon: favicon_source preserved (gate signal)
#   4. Legacy icon (filename only, no favicon_source): still projected

require_relative '../../support/test_models'

OT.boot! :test

Familia.dbclient.flushdb
OT.info "Cleaned Redis for icon safe_dump test run"

@ts = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@owner = Onetime::Customer.create!(email: "icon_owner_#{@ts}_#{@entropy}@test.com")
@org = Onetime::Organization.create!("Icon Test Org #{@ts}", @owner, "icon_#{@ts}@test.com")

@domain_no_icon = Onetime::CustomDomain.create!("no-icon-#{@ts}.example.com", @org.objid)
@domain_auto = Onetime::CustomDomain.create!("auto-icon-#{@ts}.example.com", @org.objid)
@domain_upload = Onetime::CustomDomain.create!("upload-icon-#{@ts}.example.com", @org.objid)
@domain_legacy = Onetime::CustomDomain.create!("legacy-icon-#{@ts}.example.com", @org.objid)

## Setup: four domains created
@org.domain_count
#=> 4

# --- Scenario 1: no icon stored ---

## Domain with no icon: safe_dump[:icon] is nil
@domain_no_icon.safe_dump[:icon]
#=> nil

## safe_dump still declares the :icon key (nil value, not absent)
@domain_no_icon.safe_dump.key?(:icon)
#=> true

# --- Scenario 2: auto_fetch icon (encoded must be dropped) ---

## Write an auto-fetched icon incl. the large encoded blob and numeric dims
@domain_auto.icon['filename']       = 'favicon.ico'
@domain_auto.icon['content_type']   = 'image/x-icon'
@domain_auto.icon['favicon_source'] = 'auto_fetch'
@domain_auto.icon['encoded']        = 'A' * 5000
@domain_auto.icon['width']          = '32'
@domain_auto.icon['height']         = '32'
@domain_auto.icon['bytes']          = '1234'
@dump_auto = Onetime::CustomDomain.find_by_identifier(@domain_auto.identifier).safe_dump
@dump_auto[:icon]['favicon_source']
#=> 'auto_fetch'

## Projection carries filename
@dump_auto[:icon]['filename']
#=> 'favicon.ico'

## Projection carries content_type
@dump_auto[:icon]['content_type']
#=> 'image/x-icon'

## Projection NEVER includes the encoded bytes
@dump_auto[:icon].key?('encoded')
#=> false

## Projection is exactly the three string metadata keys (no numeric dims)
@dump_auto[:icon].keys.sort
#=> ['content_type', 'favicon_source', 'filename']

# --- Scenario 3: user_upload icon (the gate signal) ---

## user_upload provenance survives to the record (button disables on this)
@domain_upload.icon['filename']       = 'logo.png'
@domain_upload.icon['content_type']   = 'image/png'
@domain_upload.icon['favicon_source'] = 'user_upload'
@domain_upload.icon['encoded']        = 'B' * 5000
@dump_upload = Onetime::CustomDomain.find_by_identifier(@domain_upload.identifier).safe_dump
@dump_upload[:icon]['favicon_source']
#=> 'user_upload'

## user_upload projection also drops encoded
@dump_upload[:icon].key?('encoded')
#=> false

# --- Scenario 4: legacy icon (filename only, untagged) ---

## A legacy icon with no favicon_source still projects (favicon_source nil)
@domain_legacy.icon['filename']     = 'old.ico'
@domain_legacy.icon['content_type'] = 'image/x-icon'
@dump_legacy = Onetime::CustomDomain.find_by_identifier(@domain_legacy.identifier).safe_dump
[@dump_legacy[:icon]['filename'], @dump_legacy[:icon]['favicon_source']]
#=> ['old.ico', nil]

# Teardown
Familia.dbclient.flushdb
