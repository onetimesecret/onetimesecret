# lib/onetime.rb
#
# frozen_string_literal: true

require 'bundler/setup'

if ENV['BOOT_TICKER_TAPE']
  require_relative 'onetime/boot/ticker_tape'
  $ticker = Onetime::Boot::TickerTape.new.tap(&:start) # rubocop:disable Style/GlobalVars
end

require 'securerandom'

require 'truemail'

require 'erb'

require 'yaml'

require 'bcrypt'

begin
  require 'sendgrid-ruby'
rescue LoadError
  warn 'SendGrid is not installed. Mailer not available.'
end

require 'rack'
require 'otto'
require 'familia'

Warning[:deprecated] = %w[development dev test testing].include?(ENV['RACK_ENV'].to_s.downcase)

# Ensure immediate flushing of stdout to improve real-time logging visibility.
# This is particularly useful in development and production environments where
# timely log output is crucial for monitoring and debugging purposes.
#
# Enabling sync can have a performance impact in high-throughput environments.
#
# NOTE: Use STDOUT the immuntable constant here, not $stdout (global var).
#

# Onetime is the core of the Onetime Secret application.
# It contains the core classes and modules that make up
# the app. It is the main namespace for the application.
#
module Onetime
  require_relative 'onetime/utils'
  if Onetime::Utils.yes?(ENV.fetch('STDOUT_SYNC', false))
    $stdout.sync = true
    $stderr.sync = true
    if Onetime::Utils.yes?(ENV['ONETIME_DEBUG'])
      $stderr.puts <<~NOTICE # rubocop:disable Style/StderrPuts
        [onetime] STDOUT and STDERR sync mode enabled. Output will be unbuffered
        which is useful for real-time logging visibility but is not recommended
        for production. It makes the process IO bound which can impact performance.
      NOTICE
    end
  end

  unless defined?(Onetime::HOME)
    HOME = File.expand_path(File.join(File.dirname(__FILE__), '..'))
  end

  # Add apps directories to load path for requires like 'v1/refinements'
  unless defined?(Onetime::APPS_ROOT)
    APPS_ROOT = File.join(HOME, 'apps').freeze
    $LOAD_PATH.unshift(File.join(APPS_ROOT, 'api'))
    $LOAD_PATH.unshift(File.join(APPS_ROOT, 'web'))
  end

  # Name of the tracked default brand pack. Brand-pack resolution ALWAYS lands
  # on a pack (v2, #3774): an unset BRAND_PACK resolves to this one, which holds
  # the neutral asset set + a (commented, value-free) brand.yaml under
  # public/branding/default/. #3774
  DEFAULT_BRAND_PACK = 'default'

  # The two search roots a BRAND_PACK name is resolved against, in precedence
  # order (first existing wins, #3774):
  #   1. etc/branding/  — operator space. Nothing is tracked here in the repo;
  #      it arrives at runtime (quadlet per-entry mounts of /etc/onetimesecret/,
  #      systemd confext, a Docker/K8s volume). Checked first so an operator pack
  #      shadows a vendor pack of the same name.
  #   2. public/branding/  — vendor space. Ships the tracked `default` pack and
  #      any generated packs baked into the image/repo.
  # Both are resolved against HOME (not CWD — puma's working dir is not
  # guaranteed). The `default` pack deliberately lives in the VENDOR root: a
  # quadlet mount of a host branding/ dir lands wholesale over etc/branding, so a
  # tracked etc/branding/default would be shadowed exactly when packs are in use.
  def self.brand_pack_roots
    @brand_pack_roots ||= [
      File.join(HOME, 'etc', 'branding'),
      File.join(HOME, 'public', 'branding'),
    ].freeze
  end

  # Resolve a brand-pack NAME to its absolute directory across the two search
  # roots (first existing wins), or nil when the name is unsafe or no root holds
  # it. Pure — takes a name, reads no config — so it is shared by the runtime
  # resolver (brand_overlay_dir) and the boot-time manifest loader
  # (Config#apply_brand_manifest). #3774
  def self.brand_pack_dir(name)
    name = name.to_s.strip
    return nil if name.empty?

    # SECURITY: a pack is a NAME, not a path. It is joined directly into a
    # filesystem path, so reject path separators and '..' to prevent traversal
    # outside the search roots. #3739
    return nil if name.match?(%r{[/\\]|\.\.})

    brand_pack_roots.each do |root|
      dir = File.join(root, name)
      return dir if Dir.exist?(dir)
    end
    nil
  end

  # Resolve the active brand-pack directory from explicit config values (pure —
  # does not read OT.conf, so it works at boot before OT.conf is installed).
  # Resolution ALWAYS lands on a pack (#3774). Precedence:
  #   1. brand_assets_dir — an explicit path (e.g. a runtime mount). When set &
  #      non-empty it WINS: absolute used as-is, relative resolved against HOME.
  #      Missing (e.g. a volume not yet mounted) → warn once, fall back to the
  #      default pack so the install still serves neutral assets.
  #   2. brand_pack — a pack NAME resolved across brand_pack_roots; an unset name
  #      means DEFAULT_BRAND_PACK. A set-but-not-found name warns (listing the
  #      searched roots) and falls back to the default pack.
  #   3. the default pack. nil only if even that is absent (a broken checkout).
  def self.resolve_brand_pack_dir(brand_assets_dir: nil, brand_pack: nil)
    explicit = brand_assets_dir.to_s.strip
    unless explicit.empty?
      dir = File.absolute_path?(explicit) ? explicit : File.join(HOME, explicit)
      return dir if Dir.exist?(dir)

      if @warned_missing_brand_assets_dir != dir
        OT.le "[brand_overlay_dir] brand_assets_dir=#{dir.inspect} configured but missing; falling back to the #{DEFAULT_BRAND_PACK.inspect} brand pack"
        @warned_missing_brand_assets_dir = dir
      end
      return brand_pack_dir(DEFAULT_BRAND_PACK)
    end

    name = brand_pack.to_s.strip
    name = DEFAULT_BRAND_PACK if name.empty?
    dir  = brand_pack_dir(name)
    return dir if dir

    if name != DEFAULT_BRAND_PACK && @warned_missing_brand_pack != name
      searched                   = brand_pack_roots.map { |r| File.join(r, name) }
      OT.le "[brand_overlay_dir] brand_pack=#{name.inspect} not found (searched #{searched.inspect}); falling back to the #{DEFAULT_BRAND_PACK.inspect} brand pack"
      @warned_missing_brand_pack = name
    end
    brand_pack_dir(DEFAULT_BRAND_PACK)
  end

  # Runtime-resolved absolute brand-pack directory, read from OT.conf. Always a
  # real directory (the default pack when nothing is selected); nil only if the
  # default pack itself is missing. #3774
  def self.brand_overlay_dir
    resolve_brand_pack_dir(
      brand_assets_dir: OT.conf.dig('site', 'brand_assets_dir'),
      brand_pack: OT.conf.dig('site', 'brand_pack'),
    )
  end

  # Overlay-first single-file resolver for the route-served brand assets
  # (favicon.ico, site.webmanifest). Tries the resolved pack (a selected pack or
  # the default), then the default pack (in case a selected pack is partial). No
  # public/web fallback (#3774): the default pack is the canonical home, so when
  # nothing carries the file this returns the default-pack path even if absent —
  # callers already handle a missing file (GetFavicon serves an empty body;
  # GetWebmanifest falls back to NEUTRAL_FALLBACK). A drift spec guards the
  # default pack's file set so canonical assets are always present.
  def self.brand_asset_path(name)
    default_dir = brand_pack_dir(DEFAULT_BRAND_PACK)
    [brand_overlay_dir, default_dir].compact.uniq.each do |dir|
      candidate = File.join(dir, name)
      return candidate if File.exist?(candidate)
    end

    canonical = default_dir || File.join(brand_pack_roots.last, DEFAULT_BRAND_PACK)
    File.join(canonical, name)
  end

  # Read-only brand-pack resolution diagnostics for the v0.26.0 branding
  # incident (#3822): byte-identical brand files rendered correctly on CA/NZ but
  # fell back to neutral on UK. The cause is one of three modes a running
  # instance otherwise cannot tell apart — config divergence, env not reaching
  # the container, or a boot-time mount race — so this surfaces all three at
  # once. It is the SINGLE SOURCE OF TRUTH: the `bin/ots config brand` command
  # and the Colonel `GET /system/brand` endpoint are thin adapters over this
  # payload. String keys throughout — it is serialized to JSON and printed by a
  # CLI.
  #
  # Purity: reads ENV, OT.conf, and the filesystem; mutates nothing (OT.conf is
  # frozen in prod) and adds no memoization, so two calls reflect current disk
  # both times. Resolution is delegated to the live resolvers
  # (brand_overlay_dir, brand_pack_dir), never reimplemented. #3822
  def self.brand_pack_diagnostics
    # Asset-URL constants live on the middleware path, which the CLI adapter may
    # never build. require_relative is idempotent, so load it on demand.
    require_relative 'onetime/middleware/static_files'

    resolved_dir = brand_overlay_dir                  # LIVE re-resolution, not the boot snapshot
    default_dir  = brand_pack_dir(DEFAULT_BRAND_PACK)

    # site.* as the FROZEN BOOT snapshot saw it (may differ from raw ENV now).
    cfg_pack   = OT.conf.dig('site', 'brand_pack')
    cfg_assets = OT.conf.dig('site', 'brand_assets_dir')

    # fell_back_to_default is TRUE only when a non-default pack was INTENDED yet
    # the DEFAULT pack was served (a stale brand_assets_dir masking a good pack,
    # a typo'd pack name, or env not arriving all land here). Landing on the
    # default with nothing configured is CORRECT, not a fallback — hence the
    # intent gate. brand_assets_dir WINS over brand_pack, so a non-empty
    # brand_assets_dir signals intent — UNLESS it points at the default pack
    # itself. An operator MAY deliberately pin brand_assets_dir (or brand_pack)
    # at the default pack: that is neutral-by-choice, not a fallback, and must
    # not gate a deploy (#3822 #9). Normalize brand_assets_dir exactly as
    # resolve_brand_pack_dir does (absolute as-is; relative against HOME) and
    # exclude it when it equals default_dir — mirroring the resolver's string
    # handling, not re-resolving. The brand_pack branch already excludes an
    # explicit 'default' name the same way.
    assets_norm = cfg_assets.to_s.strip
    assets_norm = File.join(HOME, assets_norm) unless assets_norm.empty? || File.absolute_path?(assets_norm)

    intended_non_default = (!assets_norm.empty? && assets_norm != default_dir) ||
                           (!cfg_pack.to_s.strip.empty? && cfg_pack.to_s.strip != DEFAULT_BRAND_PACK)
    served_default       = resolved_dir == default_dir
    fell_back_to_default = intended_non_default && served_default

    # Live manifest re-read: what boot WOULD absorb if apply_brand_manifest ran
    # NOW, filtered exactly as it filters (whitelist ∩ String ∩ stripped
    # non-empty). resolved_dir is nil only on a broken checkout (default pack
    # absent); every field below is nil-safe for that case.
    manifest_path   = resolved_dir ? File.join(resolved_dir, Onetime::Config::BRAND_MANIFEST_FILENAME) : nil
    manifest_exists = !!(manifest_path && File.exist?(manifest_path))
    live_scalars    = manifest_exists ? read_brand_manifest_scalars(manifest_path) : {}

    # boot_vs_live_mismatch — the mount-race detector. TRUE when a real manifest
    # sits in the resolved pack NOW, but the frozen boot conf disagrees with what
    # disk offers for some key, for a reason that can only be a race. The scan
    # covers the UNION of two key sets so a REMOVED key is not missed:
    #
    #   * keys the manifest carries on disk NOW (live_scalars) — catches a value
    #     that CHANGED or APPEARED since boot; and
    #   * keys the pack manifest was absorbed FROM at boot
    #     (conf['brand_manifest']['absorbed_keys']) — catches a value REMOVED from
    #     brand.yaml since boot: it lingers in the frozen conf but is absent from a
    #     live disk re-read, so a disk-only scan would miss it (#8). This holds
    #     whether a SINGLE key was deleted (brand.yaml still on disk) or the WHOLE
    #     brand.yaml was removed (file gone, pack dir still resolving via a lingering
    #     logo/favicon): when the manifest is gone live_scalars is empty, so the union
    #     collapses to absorbed_keys alone and the removal still scans. Provenance-
    #     gated to absorbed keys so a legacy/default-filled conf key (config.rb
    #     LEGACY_BRAND_FALLBACKS — never pack-sourced) is not mistaken for a race
    #     on a supported back-compat path (#3612).
    #
    # TWO layers legitimately outrank the manifest and are excluded so neither
    # false-positives:
    #
    #   1. BRAND_* env — the TOP precedence layer (normalize_brand applies it AFTER
    #      the manifest). Any ordinary env override makes conf differ from disk by
    #      design, so the env-backed key is skipped (brand_env_override?).
    #   2. operator brand: config — apply_brand_manifest fills ONLY keys the
    #      operator left nil, so a key the operator SET in config legitimately
    #      diverges from a differing pack brand.yaml. Those keys are recorded at
    #      boot in conf['brand_manifest']['operator_keys'] and skipped here.
    #
    # What survives is a genuine race: a key the operator did NOT set and env does
    # NOT override, where the boot conf (nil, filled from a stale pack, or holding
    # a since-removed value) disagrees with what the resolved pack offers on disk NOW.
    #
    # SCOPE (#7, deferred): this detects SCALAR races only. An asset-only race — a
    # pack whose logo/favicon mount but whose brand.yaml is value-free or absent —
    # leaves both live_scalars and absorbed_keys empty, so it does NOT auto-flag
    # here (and a resolved non-default pack keeps fell_back_to_default false too, so
    # the CLI exits 0). overlay_assets is exposed for manual cross-region diffing
    # meanwhile. An automatic asset-race signal needs a boot baseline of the mounted
    # overlay set (StaticFiles instrumentation) that does not yet exist. The tryout
    # pins this asset-only-reads-healthy behavior so any future change is deliberate.
    operator_keys         = OT.conf.dig('brand_manifest', 'operator_keys') || []
    absorbed_keys         = OT.conf.dig('brand_manifest', 'absorbed_keys') || []
    # No manifest_exists guard is needed: when the manifest is absent live_scalars is
    # empty, so the union collapses to absorbed_keys alone. A WHOLE brand.yaml removed
    # since boot then still scans its lingering absorbed keys (each compares unequal —
    # "" from the absent disk read vs the frozen conf value — and flags), while an
    # asset-only pack (#7, empty absorbed_keys) yields an empty union so `.any?`
    # short-circuits to false and correctly does NOT flag.
    boot_vs_live_mismatch = (live_scalars.keys | absorbed_keys).any? do |key|
      next false if operator_keys.include?(key)
      next false if brand_env_override?(key)

      live_scalars[key].to_s != OT.conf.dig('brand', key).to_s
    end

    # Pack assets present on disk in the resolved pack RIGHT NOW. This may differ
    # from what StaticFiles actually serves — that overlay set is frozen at boot
    # — so a divergence here is itself a mount-race signal.
    overlay_urls   = Onetime::Middleware::StaticFiles::BRAND_PACK_URLS +
                     Onetime::Middleware::StaticFiles::BRAND_PACK_LOGO_URLS
    overlay_assets = overlay_urls.select { |u| resolved_dir && File.exist?(File.join(resolved_dir, u)) }

    {
      'home' => Onetime::HOME,
      'env' => {
        # Raw ENV right now (nil if unset) — catches "env not reaching the
        # container": nil here while config expects a pack.
        'brand_pack' => ENV.fetch('BRAND_PACK', nil),
        'brand_assets_dir' => ENV.fetch('BRAND_ASSETS_DIR', nil),
      },
      'config' => {
        'brand_pack' => cfg_pack,
        'brand_assets_dir' => cfg_assets,
        # PROVENANCE as boot recorded it (conf['brand_manifest']), NOT key
        # presence: brand_absorbed = keys apply_brand_manifest filled FROM the
        # pack manifest; brand_operator_keys = keys the operator had already set
        # in brand: config. A key filled by BRAND_* env or a legacy fallback
        # appears in NEITHER list — deriving these from non-empty conf['brand']
        # values would misread env/operator overrides as pack-absorbed and skew
        # a cross-region diff during an incident.
        'brand_absorbed' => absorbed_keys,
        'brand_operator_keys' => operator_keys,
      },
      'roots' => brand_pack_roots.map { |path| { 'path' => path, 'exists' => Dir.exist?(path) } },
      'resolved_dir' => resolved_dir,
      'fell_back_to_default' => fell_back_to_default,
      'manifest' => {
        'path' => manifest_path,
        'exists' => manifest_exists,
        'keys_on_disk' => live_scalars.keys,
      },
      'boot_vs_live_mismatch' => boot_vs_live_mismatch,
      'overlay_assets' => overlay_assets,
    }
  end

  # Internal helper for brand_pack_diagnostics: the { key => stripped value } a
  # brand.yaml would contribute to conf['brand'] if apply_brand_manifest ran now,
  # replicating its exact filter (BRAND_MANIFEST_KEYS ∩ String ∩ stripped
  # non-empty). The rescue is scoped to the live YAML read only, so a
  # missing/malformed/non-mapping manifest surfaces as an empty contribution
  # rather than an exception. #3822
  def self.read_brand_manifest_scalars(path)
    return {} unless path && File.exist?(path)

    manifest = YAML.safe_load_file(path) || {}
    return {} unless manifest.is_a?(Hash)

    Onetime::Config::BRAND_MANIFEST_KEYS.each_with_object({}) do |key, acc|
      value = manifest[key]
      next unless value.is_a?(String)

      value    = value.strip
      acc[key] = value unless value.empty?
    end
  rescue StandardError
    {}
  end

  # Internal helper for brand_pack_diagnostics: true when the BRAND_* env var
  # backing this brand key is set to a non-empty value. The mount-race detector
  # (boot_vs_live_mismatch) EXCLUDES such keys: env is the top precedence layer
  # applied after the manifest, so a legitimate BRAND_* override makes conf
  # differ from the on-disk manifest BY DESIGN and must not read as a race. #3822
  def self.brand_env_override?(key)
    env_var = Onetime::Config::BRAND_ENV[key]
    return false unless env_var

    !ENV.fetch(env_var, '').to_s.strip.empty?
  end

  require_relative 'onetime/class_methods'
  extend ClassMethods

  # Load runtime state management
  require_relative 'onetime/runtime'

  # Load application framework components
  require_relative 'onetime/application'

  # Load backwards compatibility accessors
  # TODO: Remove this require and delete lib/onetime/deprecated_methods.rb
  # after migrating all code to use Runtime state objects directly
  require_relative 'onetime/deprecated_methods'
end

# Track whether we received SIGINT for graceful shutdown coordination.
# This flag is set in the trap and checked in at_exit, avoiding thread
# operations inside the signal handler (which Ruby forbids).
$ot_received_sigint = false # rubocop:disable Style/GlobalVars

# SIGINT handler: minimal work only — set flag and re-raise.
# Thread operations (Sentry.close, logging) are deferred to at_exit.
trap('SIGINT') do
  # Prevent re-entry if signal is received again during cleanup
  trap('SIGINT', 'DEFAULT')

  $ot_received_sigint = true # rubocop:disable Style/GlobalVars

  # Cannot use semantic_logger from trap context - use direct STDERR
  warn 'Shutting down gracefully...'

  # Re-raise signal to trigger default handler (ensures proper exit code 130)
  Process.kill('SIGINT', Process.pid)
end

# Sentry cleanup runs in at_exit (outside trap context) where thread
# operations are safe. This replaces the previous in-trap Sentry.close
# which caused ThreadError.
at_exit do
  next unless $ot_received_sigint # rubocop:disable Style/GlobalVars

  OT.with_diagnostics do
    if defined?(Sentry) && Sentry.initialized?
      begin
        Sentry.close
      rescue Sentry::Error, IOError, SystemCallError => ex
        # Ignore Sentry-related/network errors during shutdown
        warn "Error during Sentry shutdown: #{ex.class}" if OT.debug?
      end
    end
  end
end

require_relative 'onetime/alias'
require_relative 'onetime/errors'
require_relative 'onetime/error_handler'
require_relative 'onetime/version'
require_relative 'onetime/config'
require_relative 'onetime/config_generator'
require_relative 'onetime/billing_config'
require_relative 'onetime/models'
require_relative 'onetime/signup_validation'
require_relative 'onetime/domain_validation/strategy'
require_relative 'onetime/boot'
