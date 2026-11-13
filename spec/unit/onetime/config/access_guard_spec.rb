# spec/unit/onetime/config/access_guard_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Static guard — main-config reads go through OT.conf.get
# =============================================================================
#
# Production code reads the main config with OT.conf.get('a.b.c'[, default])
# (Onetime::Config::Reader). RuboCop cannot enforce that here, because
# .rubocop.yml excludes apps/api/v1 and every spec and try directory, so this
# spec does. Calls are found with Prism, so comments and strings never match.
#
#   1. No direct reads. dig, fetch, key? and [] on OT.conf or Onetime.conf are
#      not allowed in lib/ and apps/. Files that still have them are listed in
#      PENDING with their count; a count can only go down, and a file leaves
#      the list when its count reaches zero.
#   2. A get with a literal path and no default names a path that exists in
#      the shipped config: etc/defaults/config.defaults.yaml merged over
#      Onetime::Config::DEFAULTS, plus the paths after_load builds
#      (DERIVED_PATHS). A typo or a stale path fails here, not in production.
#   3. A get with a literal path and a default, whose path is not in the
#      shipped config, is listed in OPTIONAL_PATHS with the reason it can be
#      absent.
#   4. A get whose path is not a literal (an Array with a variable segment,
#      an interpolated String, a variable) passes a default.
#
# =============================================================================

require 'spec_helper'
require 'prism'

module ConfigAccessGuard
  ROOT = File.expand_path('../../../..', __dir__)

  SOURCE_GLOBS = %w[lib/**/*.rb lib/**/*.rake apps/**/*.rb apps/**/*.ru config.ru].freeze
  EXCLUDED     = %r{/(spec|try)/|_spec\.rb\z|_try\.rb\z}

  DIRECT_READS = %i[dig fetch key? []].freeze

  # Paths that Config.after_load adds to the loaded config. A path below one
  # of these counts as shipped.
  DERIVED_PATHS = {
    'brand_manifest' => 'built from the brand pack by Config.apply_brand_manifest',
  }.freeze

  # Literal paths read with a default that are not in the shipped config.
  OPTIONAL_PATHS = {}.freeze

  # Files with direct reads (rule 1) and how many. Lower a count when you
  # convert a read to OT.conf.get; remove the file at zero.
  PENDING = {
    'apps/api/colonel/logic/colonel/elevation.rb' => 1,
    'apps/api/colonel/logic/colonel/get_colonel_info.rb' => 1,
    'apps/api/colonel/logic/colonel/get_system_settings.rb' => 10,
    'apps/api/domains/logic/domains/add_domain.rb' => 1,
    'apps/api/domains/logic/domains/refresh_domain_favicon.rb' => 1,
    'apps/api/domains/logic/homepage_config/base.rb' => 1,
    'apps/api/domains/logic/sso_config/serializers.rb' => 1,
    'apps/api/domains/policies/domain_config_authorization.rb' => 1,
    'apps/api/incoming/initializers/setup_incoming_recipients.rb' => 3,
    'apps/api/incoming/logic/create_incoming_secret.rb' => 1,
    'apps/api/organizations/logic/organizations/list_secret_activity.rb' => 1,
    'apps/api/v1/controllers/class_methods.rb' => 2,
    'apps/api/v1/logic/base.rb' => 1,
    'apps/api/v1/logic/helpers/uris.rb' => 3,
    'apps/api/v1/logic/secrets/base_secret_action.rb' => 4,
    'apps/api/v1/logic/secrets/generate_secret.rb' => 1,
    'apps/api/v1/logic/secrets/show_receipt.rb' => 1,
    'apps/api/v2/logic/helpers/uris.rb' => 3,
    'apps/api/v2/logic/secrets/access_telemetry.rb' => 1,
    'apps/api/v2/logic/secrets/base_secret_action.rb' => 3,
    'apps/api/v2/logic/secrets/generate_secret.rb' => 1,
    'apps/api/v2/logic/secrets/list_receipts.rb' => 1,
    'apps/api/v2/logic/secrets/show_receipt.rb' => 1,
    'apps/api/v3/logic/feedback.rb' => 2,
    'apps/internal/acme/application.rb' => 1,
    'apps/internal/acme/config.ru' => 2,
    'apps/web/auth/config/email/email_auth.rb' => 1,
    'apps/web/auth/config/email/reset_password.rb' => 1,
    'apps/web/auth/config/email/verify_account.rb' => 1,
    'apps/web/auth/config/hooks/omniauth.rb' => 1,
    'apps/web/auth/lib/public_host.rb' => 2,
    'apps/web/billing/cli/diagnose_command.rb' => 1,
    'apps/web/billing/controllers/base.rb' => 3,
    'apps/web/billing/controllers/billing.rb' => 2,
    'apps/web/billing/controllers/plans.rb' => 4,
    'apps/web/billing/lib/billing_service.rb' => 1,
    'apps/web/billing/metadata.rb' => 2,
    'apps/web/billing/operations/create_checkout_link.rb' => 3,
    'apps/web/billing/operations/webhook_handlers/federation_support.rb' => 1,
    'apps/web/core/controllers/base.rb' => 3,
    'apps/web/core/controllers/health.rb' => 2,
    'apps/web/core/logic/authentication/authenticate_session.rb' => 1,
    'apps/web/core/logic/page/get_favicon.rb' => 1,
    'apps/web/core/logic/page/get_webmanifest.rb' => 1,
    'apps/web/core/middleware/request_setup.rb' => 2,
    'apps/web/core/middleware/vite_proxy.rb' => 1,
    'apps/web/core/views/helpers/initialize_view_vars.rb' => 5,
    'lib/onetime.rb' => 7,
    'lib/onetime/application/auth_strategies.rb' => 3,
    'lib/onetime/application/auth_strategies/admin_session_lifetime.rb' => 1,
    'lib/onetime/application/middleware_profile.rb' => 1,
    'lib/onetime/application/middleware_stack.rb' => 7,
    'lib/onetime/auth_config.rb' => 1,
    'lib/onetime/class_methods.rb' => 1,
    'lib/onetime/cli/apitoken_command.rb' => 2,
    'lib/onetime/cli/queue/dlq_command.rb' => 1,
    'lib/onetime/cli/queue/init_command.rb' => 1,
    'lib/onetime/cli/queue/ping_command.rb' => 1,
    'lib/onetime/cli/queue/rabbitmq_helpers.rb' => 2,
    'lib/onetime/cli/queue/reset_command.rb' => 1,
    'lib/onetime/cli/queue/status_command.rb' => 4,
    'lib/onetime/cli/status_command.rb' => 2,
    'lib/onetime/cli/worker_command.rb' => 1,
    'lib/onetime/domain_validation/sender_strategies/provider_config.rb' => 2,
    'lib/onetime/helpers/homepage_mode_helpers.rb' => 1,
    'lib/onetime/helpers/session_helpers.rb' => 1,
    'lib/onetime/incoming/recipient_resolver.rb' => 3,
    'lib/onetime/initializers/configure_domains.rb' => 2,
    'lib/onetime/initializers/configure_familia.rb' => 3,
    'lib/onetime/initializers/configure_secret_activity.rb' => 1,
    'lib/onetime/initializers/configure_truemail.rb' => 1,
    'lib/onetime/initializers/load_locales.rb' => 2,
    'lib/onetime/initializers/print_log_banner.rb' => 6,
    'lib/onetime/initializers/set_secrets.rb' => 1,
    'lib/onetime/initializers/setup_diagnostics.rb' => 5,
    'lib/onetime/initializers/setup_loggers.rb' => 1,
    'lib/onetime/initializers/setup_paseto_keys.rb' => 1,
    'lib/onetime/initializers/setup_rabbitmq.rb' => 4,
    'lib/onetime/jobs/maintenance_job.rb' => 1,
    'lib/onetime/jobs/publisher.rb' => 1,
    'lib/onetime/jobs/scheduled/catalog_retry_job.rb' => 1,
    'lib/onetime/jobs/scheduled/dlq_email_consumer_job.rb' => 2,
    'lib/onetime/jobs/scheduled/dlq_monitor_job.rb' => 2,
    'lib/onetime/jobs/scheduled/domain_refresh_job.rb' => 5,
    'lib/onetime/jobs/scheduled/expiration_warning_job.rb' => 4,
    'lib/onetime/jobs/scheduled/favicon_backfill_job.rb' => 5,
    'lib/onetime/jobs/scheduled/heartbeat_job.rb' => 1,
    'lib/onetime/jobs/scheduled/plan_cache_refresh_job.rb' => 1,
    'lib/onetime/jobs/workers/favicon_fetch_worker.rb' => 1,
    'lib/onetime/logic/base.rb' => 3,
    'lib/onetime/logic/guest_route_gating.rb' => 1,
    'lib/onetime/mail/mailer.rb' => 4,
    'lib/onetime/mail/views/base.rb' => 4,
    'lib/onetime/middleware/admin_network_isolation.rb' => 1,
    'lib/onetime/middleware/assume_https.rb' => 1,
    'lib/onetime/middleware/domain_strategy.rb' => 2,
    'lib/onetime/middleware/identity_resolution.rb' => 1,
    'lib/onetime/middleware/public_host_rewrite.rb' => 1,
    'lib/onetime/middleware/security.rb' => 1,
    'lib/onetime/middleware/static_files.rb' => 1,
    'lib/onetime/middleware/tenant_csp_extras.rb' => 1,
    'lib/onetime/models/custom_domain/brand_settings.rb' => 2,
    'lib/onetime/models/custom_domain/homepage_config.rb' => 1,
    'lib/onetime/models/custom_domain/incoming_config.rb' => 1,
    'lib/onetime/models/custom_domain/signin_config.rb' => 2,
    'lib/onetime/models/custom_domain/signup_config.rb' => 2,
    'lib/onetime/models/customer/features/colonel_assignment.rb' => 1,
    'lib/onetime/models/features/with_entitlements.rb' => 1,
    'lib/onetime/models/organization/features/secret_activity.rb' => 1,
    'lib/onetime/models/receipt.rb' => 1,
    'lib/onetime/models/secret/features/display_type.rb' => 1,
    'lib/onetime/operations/fetch_domain_favicon.rb' => 7,
    'lib/onetime/operations/verify_domain.rb' => 1,
    'lib/onetime/paseto.rb' => 1,
    'lib/onetime/rodauth_admin.rb' => 1,
    'lib/onetime/secret_verifier.rb' => 2,
    'lib/onetime/security/colonel_rate_limiter.rb' => 1,
    'lib/onetime/security/conceal_secret_rate_limiter.rb' => 1,
    'lib/onetime/security/create_account_rate_limiter.rb' => 1,
    'lib/onetime/security/incoming_rate_limiter.rb' => 1,
    'lib/onetime/security/per_customer_rate_limit.rb' => 1,
    'lib/onetime/security/reset_request_rate_limiter.rb' => 1,
    'lib/onetime/session.rb' => 1,
    'lib/onetime/session/codec.rb' => 1,
    'lib/onetime/signup_validation.rb' => 1,
    'lib/onetime/utils/canonical_hosts.rb' => 3,
    'lib/onetime/utils/email_hash.rb' => 1,
    'lib/tasks/dev.rake' => 2,
  }.freeze

  module_function

  def source_files
    SOURCE_GLOBS.flat_map { |glob| Dir.glob(File.join(ROOT, glob)) }
      .uniq
      .reject { |path| path.match?(EXCLUDED) }
      .sort
  end

  def relative(path)
    path.delete_prefix("#{ROOT}/")
  end

  # OT, Onetime, ::OT, ::Onetime
  def root_constant?(node)
    case node
    when Prism::ConstantReadNode then %i[OT Onetime].include?(node.name)
    when Prism::ConstantPathNode then node.parent.nil? && %i[OT Onetime].include?(node.name)
    else false
    end
  end

  # OT.conf / Onetime.conf (with or without &.)
  def config_receiver?(node)
    node.is_a?(Prism::CallNode) && node.name == :conf && node.arguments.nil? && root_constant?(node.receiver)
  end

  # A literal path: a String without interpolation, or an Array of them.
  def literal_path(node)
    case node
    when Prism::StringNode
      node.unescaped
    when Prism::ArrayNode
      node.elements.map(&:unescaped) if node.elements.all?(Prism::StringNode)
    end
  end

  # Collects the direct reads and the get calls of one file.
  class Scanner < Prism::Visitor
    attr_reader :direct_reads, :gets

    def initialize
      super
      @direct_reads = []
      @gets         = []
    end

    def visit_call_node(node)
      if ConfigAccessGuard.config_receiver?(node.receiver)
        if DIRECT_READS.include?(node.name)
          @direct_reads << node.location.start_line
        elsif node.name == :get
          args = node.arguments&.arguments || []
          @gets << {
            line: node.location.start_line,
            path: args.first && ConfigAccessGuard.literal_path(args.first),
            default: args.length >= 2,
          }
        end
      end
      super
    end
  end

  # @return [Scanner]
  def scan_source(source, label = '(source)')
    parsed = Prism.parse(source)
    raise "Guard is broken: #{label} does not parse" unless parsed.success?

    Scanner.new.tap { |scanner| parsed.value.accept(scanner) }
  end

  # @return [Hash{String => Scanner}] the files with reads, by relative path
  def scan
    @scan ||= source_files.each_with_object({}) do |path, result|
      source = File.read(path)
      next unless source.include?('conf')

      scanner = scan_source(source, relative(path))
      result[relative(path)] = scanner unless scanner.direct_reads.empty? && scanner.gets.empty?
    end
  end

  # @return [Array<Hash>] every get call, with its :file
  def get_calls(scan)
    scan.flat_map { |file, scanner| scanner.gets.map { |call| call.merge(file: file) } }
  end

  def shipped_config
    @shipped_config ||= Onetime::Config.deep_merge(
      Onetime::Config::DEFAULTS,
      Onetime::Config.load(File.join(ROOT, 'etc/defaults/config.defaults.yaml')),
    )
  end

  def segments(path)
    path.is_a?(Array) ? path : path.split('.', -1)
  end

  def path_key(path)
    segments(path).join('.')
  end

  def label(path)
    path.is_a?(Array) ? path.inspect : path
  end

  def shipped?(path, config = shipped_config)
    parts = segments(path)
    return true if DERIVED_PATHS.keys.any? { |derived| parts.first(segments(derived).length) == segments(derived) }

    node = config
    parts.all? do |segment|
      next false unless node.is_a?(Hash) && node.key?(segment)

      node = node[segment]
      true
    end
  end

  # Rule 1.
  def direct_read_problems(scan, pending = PENDING)
    actual   = scan.transform_values { |scanner| scanner.direct_reads.length }.reject { |_, count| count.zero? }
    problems = actual.filter_map do |file, count|
      expected = pending[file]
      if expected.nil?
        "#{file}:#{scan[file].direct_reads.join(', ')} reads OT.conf directly; use OT.conf.get('a.b', default)"
      elsif count > expected
        "#{file} has #{count} direct OT.conf reads, PENDING allows #{expected}; use OT.conf.get for new reads"
      elsif count < expected
        "#{file} has #{count} direct OT.conf reads; lower its PENDING count from #{expected} to #{count}"
      end
    end
    problems + (pending.keys - actual.keys).map { |file| "#{file} has no direct OT.conf reads left; remove it from PENDING" }
  end

  # Rule 2.
  def unshipped_required_problems(calls, config = shipped_config)
    calls.select { |call| call[:path] && !call[:default] }
      .reject { |call| shipped?(call[:path], config) }
      .map do |call|
        "#{call[:file]}:#{call[:line]} reads #{label(call[:path])} with no default, but the shipped config " \
          'does not have it; fix the path, or pass a default and list it in OPTIONAL_PATHS'
      end
  end

  # Rule 3.
  def optional_path_problems(calls, optional = OPTIONAL_PATHS, config = shipped_config)
    used     = calls.select { |call| call[:path] && call[:default] }.reject { |call| shipped?(call[:path], config) }
    problems = used.reject { |call| optional.key?(path_key(call[:path])) }.map do |call|
      "#{call[:file]}:#{call[:line]} reads #{label(call[:path])}, which the shipped config does not have; " \
        'add it to OPTIONAL_PATHS with the reason it can be absent'
    end

    used_keys = used.map { |call| path_key(call[:path]) }
    optional.each_key do |path|
      if shipped?(path, config)
        problems << "OPTIONAL_PATHS lists #{path}, which the shipped config has; remove it"
      elsif !used_keys.include?(path)
        problems << "OPTIONAL_PATHS lists #{path}, which no OT.conf.get reads; remove it"
      end
    end
    problems
  end

  # Rule 4.
  def computed_path_problems(calls)
    calls.select { |call| call[:path].nil? && !call[:default] }
      .map { |call| "#{call[:file]}:#{call[:line]} reads a computed path with no default; pass one" }
  end
end

RSpec.describe 'OT.conf access guard' do
  guard = ConfigAccessGuard

  describe 'the codebase' do
    it 'parses every source file and finds config reads' do
      expect(guard.scan.values.sum { |scanner| scanner.direct_reads.length + scanner.gets.length }).to be > 0
    end

    it 'has no direct dig, fetch, key? or [] reads outside PENDING, and PENDING counts are current' do
      problems = guard.direct_read_problems(guard.scan)
      expect(problems).to be_empty, problems.join("\n")
    end

    it 'reads only shipped paths when no default is given' do
      problems = guard.unshipped_required_problems(guard.get_calls(guard.scan))
      expect(problems).to be_empty, problems.join("\n")
    end

    it 'lists every non-shipped path read with a default in OPTIONAL_PATHS' do
      problems = guard.optional_path_problems(guard.get_calls(guard.scan))
      expect(problems).to be_empty, problems.join("\n")
    end

    it 'passes a default whenever the path is not a literal' do
      problems = guard.computed_path_problems(guard.get_calls(guard.scan))
      expect(problems).to be_empty, problems.join("\n")
    end
  end

  # The checks above pass vacuously when nothing violates them. These prove
  # that each one can fail.
  describe 'the guard itself' do
    let(:source) do
      <<~'RUBY'
        a = OT.conf.dig('site', 'host')
        b = OT.conf&.dig('site', 'host')
        c = Onetime.conf['site']
        d = ::OT.conf.fetch('site', {})
        e = OT.conf.key?('site')
        f = OT.conf.get('site.host')
        g = OT.conf.get(%w[site host], nil)
        h = OT.conf.get("features.#{kind}.enabled")
        i = OT.conf&.get(['features', kind, 'enabled'], false)
        # OT.conf.dig('in', 'a comment')
        j = "OT.conf.dig('in', 'a string')"
        k = conf.dig('site')
        l = settings.get('site.host')
      RUBY
    end

    let(:scanner) { guard.scan_source(source) }

    it 'finds every direct read form and nothing in comments, strings or other receivers' do
      expect(scanner.direct_reads).to eq([1, 2, 3, 4, 5])
    end

    it 'classifies get calls by literal path and default' do
      expect(scanner.gets).to eq([
        { line: 6, path: 'site.host', default: false },
        { line: 7, path: %w[site host], default: true },
        { line: 8, path: nil, default: false },
        { line: 9, path: nil, default: true },
      ])
    end

    it 'reports a file outside PENDING, a raised count, a stale count and a cleared file' do
      scan = { 'new.rb' => scanner, 'grew.rb' => scanner, 'shrank.rb' => scanner }

      problems = guard.direct_read_problems(scan, { 'grew.rb' => 4, 'shrank.rb' => 6, 'gone.rb' => 1 })

      expect(problems).to contain_exactly(
        a_string_starting_with('new.rb:1, 2, 3, 4, 5 reads OT.conf directly'),
        a_string_starting_with('grew.rb has 5 direct OT.conf reads, PENDING allows 4'),
        a_string_starting_with('shrank.rb has 5 direct OT.conf reads; lower its PENDING count from 6 to 5'),
        a_string_starting_with('gone.rb has no direct OT.conf reads left'),
      )
    end

    let(:config) { { 'site' => { 'host' => nil, 'admin' => nil } } }

    let(:calls) do
      [
        { file: 'x.rb', line: 1, path: 'site.host', default: false },
        { file: 'x.rb', line: 2, path: 'site.hots', default: false },
        { file: 'x.rb', line: 3, path: 'site.admin.elevation', default: false },
        { file: 'x.rb', line: 4, path: 'brand_manifest.operator_keys', default: false },
        { file: 'x.rb', line: 5, path: 'site.product_name', default: true },
        { file: 'x.rb', line: 6, path: %w[site host], default: true },
        { file: 'x.rb', line: 7, path: nil, default: false },
        { file: 'x.rb', line: 8, path: nil, default: true },
      ]
    end

    it 'reports a no-default read of a path the shipped config lacks, including below a nil section' do
      expect(guard.unshipped_required_problems(calls, config)).to contain_exactly(
        a_string_starting_with('x.rb:2 reads site.hots with no default'),
        a_string_starting_with('x.rb:3 reads site.admin.elevation with no default'),
      )
    end

    it 'reports an unlisted optional path, a listed shipped path and an unused listing' do
      optional = { 'site.host' => 'shipped', 'site.unused' => 'nobody reads it' }

      expect(guard.optional_path_problems(calls, optional, config)).to contain_exactly(
        a_string_starting_with('x.rb:5 reads site.product_name'),
        'OPTIONAL_PATHS lists site.host, which the shipped config has; remove it',
        'OPTIONAL_PATHS lists site.unused, which no OT.conf.get reads; remove it',
      )
      expect(guard.optional_path_problems(calls, { 'site.product_name' => 'reason' }, config)).to be_empty
    end

    it 'reports a computed path without a default' do
      expect(guard.computed_path_problems(calls)).to eq(['x.rb:7 reads a computed path with no default; pass one'])
    end
  end
end
