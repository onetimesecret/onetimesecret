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

  # Neutral bundled brand-asset directory (public/web), resolved against the app
  # root rather than CWD. Retained as a last-ditch fallback for brand_asset_path
  # (e.g. a legacy public/web runtime mount); the canonical neutral assets now
  # live in the default brand pack (public/branding/default). #3739 / #3774
  def self.public_web_dir
    File.join(HOME, 'public', 'web')
  end

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
  # the default), then the default pack (in case a selected pack is partial),
  # then the historical public/web location as a last-ditch safety net for a
  # legacy runtime mount. #3774 collapse of the pre-#3739 public/web literal.
  def self.brand_asset_path(name)
    default_dir = brand_pack_dir(DEFAULT_BRAND_PACK)
    [brand_overlay_dir, default_dir].compact.uniq.each do |dir|
      candidate = File.join(dir, name)
      return candidate if File.exist?(candidate)
    end

    File.join(OT.conf.dig('site', 'public_dir') || 'public/web', name)
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
