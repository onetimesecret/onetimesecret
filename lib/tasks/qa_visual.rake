# lib/tasks/qa_visual.rake
#
# frozen_string_literal: true

# Fixture seeding for the visual-regression suite (e2e/visual).
#
# Seeds three Host-classified fixtures — canonical (canonical.example.org),
# branded-full (secrets.acme.example.com) and branded-edge
# (secrets.edge.example.com) — plus the receipt/secret records every
# screenshot cell needs, then writes a manifest the Playwright specs read:
# e2e/visual/.artifacts/seed-manifest.json.
#
# Seeds at the model layer via Onetime::Receipt.spawn_pair — the same
# chokepoint every production path funnels through — deliberately SKIPPING
# logic-layer authorization (entitlements, guest-route gating, TTL clamps).
# That is fine for fixtures and precedented by dev:seed; do not "fix" it by
# writing raw Redis instead (state transitions are Lua-CAS'd and terminal
# secrets must not exist as keys).
#
# Idempotent: durable records (customer, org, domains, brand/logo config)
# are load-or-create; receipt/secret pairs are spawned fresh each run and
# age out via TTL (7d secrets, 14d receipts). revealed!/burned! are only
# ever called on freshly spawned records, so a re-run over a previously
# claimed batch cannot crash.
#
#   QA_VISUAL_SEED=1 bundle exec rake qa:visual:seed

namespace :qa do
  namespace :visual do
    desc 'Seed visual-regression fixtures + manifest (requires QA_VISUAL_SEED=1)'
    task :seed do
      # dev:seed guards on RACK_ENV=development, but the visual suite boots
      # the server with RACK_ENV=production, so that guard would always block
      # this task. Explicit arming via QA_VISUAL_SEED=1 (exported by
      # bin/visual) replaces it.
      unless ENV['QA_VISUAL_SEED'] == '1'
        abort 'qa:visual:seed: refusing to run without QA_VISUAL_SEED=1 (exported by bin/visual; never arm this against a real datastore)'
      end

      require 'onetime'
      require 'onetime/models'

      begin
        Onetime.boot! :cli
      rescue StandardError => ex
        abort "qa:visual:seed: boot failed (#{ex.class}: #{ex.message})\n" \
              'Is the datastore running? bin/visual starts it (or `pnpm run database:start`).'
      end

      require 'base64'
      require 'fastimage'
      require 'fileutils'
      require 'json'
      require 'stringio'
      require 'time'

      canonical_host = 'canonical.example.org'
      # Custom fixtures live on example.com, canonical on example.org — a
      # DIFFERENT registrable domain on purpose: Chooserator.peer_of? would
      # classify same-domain peers :canonical and the branded render would
      # silently never happen.
      fixtures       = {
        'canonical' => { host: canonical_host, custom: false },
        'branded-full' => { host: 'secrets.acme.example.com', custom: true },
        'branded-edge' => { host: 'secrets.edge.example.com', custom: true },
      }

      ttl        = 7 * 24 * 3600 # under every logic-layer gate; receipts live 2x
      content    = 'QA visual fixture secret. Deterministic content for screenshot comparison.'
      passphrase = 'qa-visual-passphrase'

      # --- Owner: one customer + one organization (load-or-create; the
      # create! methods raise on duplicates, so re-runs must load) ---
      email = 'qa-visual@example.com'
      owner = Onetime::Customer.find_by_email(email) || Onetime::Customer.create!(email: email)
      org   = owner.organization_instances.first ||
              Onetime::Organization.create!('QA Visual Org', owner, email)

      # --- Brand configs ---
      brand_full = {
        'primary_color' => '#DC2626',
        'font_family' => 'sans',
        'heading_font' => 'slab',
        'corner_style' => 'rounded',
        'border_radius' => 'lg', # NEVER 'custom' — a stale 'custom' bricked domain load in prod
        'product_name' => 'Acme Secrets',
        'description' => 'Acme Secrets is the trusted way to share credentials, keys, and ' \
                         'confidential notes with clients and colleagues. Every message ' \
                         'self-destructs after a single viewing.',
        'instructions_pre_reveal' => 'You have received a confidential message from Acme. Click below to ' \
                                     'reveal it. It can only be viewed once, so make sure you are ready ' \
                                     'to save it somewhere safe before you continue.',
        'instructions_reveal' => 'This message will only be displayed once. Copy it to a secure ' \
                                 'location such as your password manager before closing this window.',
        'instructions_post_reveal' => 'The message has been viewed and permanently deleted from our ' \
                                      'servers. If you need it again, please ask the sender to share a ' \
                                      'new secret through Acme Secrets.',
        'button_text_light' => true,
      }

      # branded-edge: dark primary, mono font, no radius, German locale, and
      # LONG instruction text (450-499 chars each — the API write path caps
      # text fields at 500, so anything longer would be a state production
      # cannot produce).
      brand_edge = {
        'primary_color' => '#111827',
        'font_family' => 'mono',
        'border_radius' => 'none',
        'locale' => 'de',
        'product_name' => 'Beispiel Geheimnisse',
        'instructions_pre_reveal' => 'Sie haben eine vertrauliche Nachricht über Beispiel Geheimnisse erhalten. ' \
                                     'Diese Nachricht wurde verschlüsselt gespeichert und kann nur ein einziges ' \
                                     'Mal abgerufen werden. Bitte stellen Sie sicher, dass Sie sich an einem ' \
                                     'sicheren Ort befinden und niemand Ihren Bildschirm einsehen kann, bevor ' \
                                     'Sie fortfahren. Nach dem Anzeigen wird der Inhalt unwiderruflich von ' \
                                     'unseren Servern gelöscht und kann weder von Ihnen noch vom Absender ' \
                                     'erneut aufgerufen oder wiederhergestellt werden.',
        'instructions_reveal' => 'Der Inhalt wird jetzt genau ein einziges Mal angezeigt. Kopieren Sie die ' \
                                 'Angaben unmittelbar an einen sicheren Ort, zum Beispiel in einen ' \
                                 'Passwortmanager Ihres Vertrauens. Sobald Sie dieses Fenster schließen, ' \
                                 'aktualisieren oder verlassen, ist der Inhalt dauerhaft gelöscht und kann ' \
                                 'unter keinen Umständen wiederhergestellt werden. Geben Sie die Angaben ' \
                                 'niemals per E-Mail oder Chat weiter und melden Sie verdächtige ' \
                                 'Nachrichten bitte umgehend an unser Sicherheitsteam.',
        'instructions_post_reveal' => 'Die Nachricht wurde erfolgreich angezeigt und anschließend unwiderruflich ' \
                                      'von unseren Servern entfernt. Der Absender wird nicht automatisch ' \
                                      'benachrichtigt; bestätigen Sie den Erhalt daher bitte auf einem separaten, ' \
                                      'vertrauenswürdigen Kommunikationsweg. Sollten Sie den Inhalt nicht ' \
                                      'vollständig gesichert haben, bitten Sie den Absender, eine neue ' \
                                      'vertrauliche Nachricht über Beispiel Geheimnisse zu erstellen. Vielen ' \
                                      'Dank, dass Sie unseren sicheren Übermittlungsdienst verwenden.',
      }

      # Fail fast if seed text drifts past the API's 500-char post-strip cap —
      # the model layer has no cap, so this keeps fixtures producible states.
      text_fields = %w[description product_name footer_text instructions_pre_reveal instructions_reveal instructions_post_reveal]
      [brand_full, brand_edge].each do |brand|
        brand.slice(*text_fields).each do |field, value|
          raise "qa:visual:seed: brand #{field} is #{value.length} chars (API caps text fields at 500)" if value.length > 500
        end
      end

      # --- Custom domains: load-or-create, mark verified, enable homepage,
      # write brand hashkey through the same validator the API uses ---
      seed_domain = ->(host, brand) do
        domain = Onetime::CustomDomain.load_by_display_domain(host) ||
                 Onetime::CustomDomain.create!(host, org.objid)

        # Verification is not required to serve branded traffic, but set it
        # for realism and to silence warn logs. String 'true' matches the
        # production writer (lib/onetime/operations/verify_domain.rb).
        domain.verified  = 'true'
        domain.resolving = 'true'
        domain.updated   = OT.now.to_i
        domain.save

        # CustomDomain.create! bootstraps HomepageConfig DISABLED; without
        # this the branded homepage renders the non-interactive trust card
        # instead of the secret form.
        Onetime::CustomDomain::HomepageConfig.upsert(
          domain_id: domain.identifier,
          enabled: true,
          secrets_mode: 'create',
          signup_enabled: false,
          signin_enabled: false,
        )

        # Same write-path validator the API uses — the seed can never write
        # what the API would reject. Each brand []= is an immediate HSET;
        # Familia auto-serializes (never hand-JSON-encode values here).
        Onetime::CustomDomain::BrandSettings.validate!(brand)
        brand.each { |key, value| domain.brand[key] = value }
        domain.updated                              = OT.now.to_i
        domain.save
        domain
      end

      acme_domain = seed_domain.call(fixtures['branded-full'][:host], brand_full)
      seed_domain.call(fixtures['branded-edge'][:host], brand_edge)

      # --- Logo: branded-full only (branded-edge stays logo-less on purpose —
      # the logo-less branded render is itself a fixture property). Mirrors
      # UpdateDomainLogo's hashkey writes; each []= is an immediate HSET.
      logo_path                        = File.expand_path('../../e2e/visual/fixtures/acme-logo.png', __dir__)
      png                              = File.binread(logo_path)
      width, height                    = FastImage.size(StringIO.new(png))
      acme_domain.logo['encoded']      = Base64.strict_encode64(png)
      acme_domain.logo['filename']     = 'acme-logo.png'
      acme_domain.logo['content_type'] = 'image/png'
      acme_domain.logo['height']       = height
      acme_domain.logo['width']        = width
      acme_domain.logo['ratio']        = width.to_f / height
      acme_domain.logo['bytes']        = png.bytesize

      # --- Per-fixture screenshot cells. Cells with desktop/mobile
      # sub-records exist because visiting those pages mutates state (reveal
      # destroys the secret; the first receipt view stamps receipt_viewed_at)
      # — each viewport gets a virgin record. Single-record cells are safe to
      # share across viewports.
      seed_cells = ->(dom_host) do
        spawn = ->(**opts) { Onetime::Receipt.spawn_pair(owner.objid, ttl, content, domain: dom_host, **opts) }
        cells = {}

        _receipt, secret       = spawn.call
        cells['revealConfirm'] = { 'secretId' => secret.identifier }

        cells['revealRevealed'] = %w[desktop mobile].to_h do |viewport|
          _receipt, secret = spawn.call
          [viewport, { 'secretId' => secret.identifier }]
        end

        _receipt, secret          = spawn.call(passphrase: passphrase)
        cells['revealPassphrase'] = { 'secretId' => secret.identifier, 'passphrase' => passphrase }

        cells['receiptFresh'] = %w[desktop mobile].to_h do |viewport|
          receipt, _secret = spawn.call
          [viewport, { 'receiptId' => receipt.identifier }]
        end

        # revealed!/burned! run on the freshly spawned instances only (state
        # 'new' in memory and Redis, so the Lua CAS always wins) — never on
        # loaded records, so re-runs cannot trip over pre-claimed secrets.
        receipt, secret        = spawn.call
        secret.revealed!
        cells['receiptViewed'] = { 'receiptId' => receipt.identifier }

        receipt, secret        = spawn.call
        secret.burned!
        cells['receiptBurned'] = { 'receiptId' => receipt.identifier }

        cells['burnPage'] = %w[desktop mobile].to_h do |viewport|
          receipt, _secret = spawn.call
          [viewport, { 'receiptId' => receipt.identifier }]
        end

        # Incoming: anonymous owner + provenance fields, mirroring
        # CreateIncomingSecret. IncomingSuccess.vue renders purely from the
        # route param, but a real receipt keeps the linked /receipt page live.
        receipt, _secret         = Onetime::Receipt.spawn_pair('anon', ttl, content, domain: dom_host)
        receipt.memo             = 'Password reset request'
        receipt.recipients       = 'qa-visual-recipient@example.com'
        receipt.recipient_name   = 'QA Recipient'
        receipt.source           = 'incoming'
        receipt.save
        cells['incomingSuccess'] = { 'receiptId' => receipt.identifier }

        cells
      end

      cells_by_fixture = fixtures.to_h do |key, fixture|
        [key, seed_cells.call(fixture[:custom] ? fixture[:host] : nil)]
      end

      # 62 chars of [0-9a-z], same generator the models use, but NO object is
      # created — 256 random bits guarantee nonexistence, and no read path
      # HMAC-verifies, so it 404s identically to a consumed key.
      unknown_secret_id = Familia::VerifiableIdentifier.generate_verifiable_id

      manifest = {
        'seededAt' => Time.now.utc.iso8601,
        'canonicalHost' => canonical_host,
        'fixtures' => fixtures.transform_values { |f| { 'host' => f[:host], 'custom' => f[:custom] } },
        'unknownSecretId' => unknown_secret_id,
        'cells' => cells_by_fixture,
      }

      artifacts_dir = File.expand_path('../../e2e/visual/.artifacts', __dir__)
      FileUtils.mkdir_p(artifacts_dir)
      manifest_path = File.join(artifacts_dir, 'seed-manifest.json')
      File.write(manifest_path, JSON.pretty_generate(manifest))

      pairs_per_fixture = 11 # 1 confirm + 2 revealed + 1 passphrase + 2 fresh + 1 viewed + 1 burned + 2 burn-page + 1 incoming
      puts
      puts 'qa:visual:seed complete'
      puts "  Owner:    #{email} (org #{org.display_name})"
      fixtures.each do |key, fixture|
        puts format('  %-14s %-28s %s pairs%s', key, fixture[:host], pairs_per_fixture, fixture[:custom] ? ' (custom domain)' : '')
      end
      puts "  Unknown:  #{unknown_secret_id}"
      puts "  Manifest: #{manifest_path}"
    end
  end
end
