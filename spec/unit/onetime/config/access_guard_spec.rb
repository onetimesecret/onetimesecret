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
#   1. OT.conf (or Onetime.conf) is used only as the receiver of get in lib/
#      and apps/. Every other use counts: dig, fetch, key? or [] on it,
#      assigning it to a variable, passing it as an argument, a truthiness
#      guard. In lib/onetime/boot.rb the config is also `conf` and `@conf`.
#      Files that still have such uses are listed in PENDING with their count,
#      which can only go down; a use that stays is listed in ALLOWED_USES with
#      its reason.
#   2. Nothing reads into the result of get (OT.conf.get('site')['host']):
#      the whole path goes in get, where rules 3 to 5 can check it.
#   3. A get with a literal path and no default names a path that the shipped
#      config has: etc/defaults/config.defaults.yaml, run through
#      Config.after_load as boot does. A typo or a stale path fails here, not
#      in production.
#   4. A get with a literal path and a default, whose path is not in the
#      shipped config, is listed in OPTIONAL_PATHS with the reason it can be
#      absent.
#   5. A get whose path is not a literal (an Array with a variable segment,
#      an interpolated String, a variable) passes a default.
#   6. A get has no Symbol path and no keyword argument; both raise.
#
# Rules 3 to 5 check the path passed to get. A section read into a variable
# (`section = OT.conf.get('a.b', {}); section['c']`) is not checked below the
# path given to get.
#
# =============================================================================

require 'spec_helper'
require 'prism'

module ConfigAccessGuard
  ROOT = File.expand_path('../../../..', __dir__)

  SOURCE_GLOBS = %w[lib/**/*.rb lib/**/*.rake apps/**/*.rb apps/**/*.ru config.ru].freeze
  EXCLUDED     = %r{(\A|/)(spec|try)/|_spec\.rb\z|_try\.rb\z}

  # The file where the config is also read as `conf` and `@conf`.
  BOOT_FILE = 'lib/onetime/boot.rb'

  DIRECT_READS = %i[dig fetch key? []].freeze

  # Reads into a get result (rule 2): the direct reads plus the other ways
  # to look inside a Hash.
  CHAINED_READS = (DIRECT_READS + %i[has_key? include? member? values_at fetch_values slice to_h then]).freeze

  # Literal paths read with a default that are not in the shipped config,
  # with the reason each can be absent.
  OPTIONAL_PATHS = {
    'jobs.dlq_monitor_enabled' => 'opt-in switch for DlqMonitorJob; the defaults file does not define it',
    'jobs.domain_refresh.rate_limit' => "commented out in the defaults: unset means the strategy's own pacing",
    'jobs.heartbeat_enabled' => 'opt-in switch for HeartbeatJob; the defaults file does not define it',
    'jobs.rabbitmq_management_url' => 'optional; RABBITMQ_MANAGEMENT_URL or localhost is used without it',
    'locales' => 'legacy top-level list, read when internationalization.locales is unset',
    'site.authentication.colonels' => 'operator-set list of colonel emails; the defaults file does not define it',
    'site.authentication.external' => 'opt-in external auth section; the defaults file does not define it',
  }.freeze

  # Uses of OT.conf other than OT.conf.get that stay: file => [count, reason].
  ALLOWED_USES = {
    'lib/onetime/config.rb' => [1, 'apply_config merges an override over the whole config'],
  }.freeze

  # Uses of OT.conf other than OT.conf.get that are still to be converted
  # (rule 1): file => count. Lower a count when you convert a use; remove the
  # file at zero.
  PENDING = {
    'apps/api/colonel/logic/colonel/elevation.rb' => 1,
    'apps/api/colonel/logic/colonel/get_colonel_info.rb' => 1,
    'apps/api/colonel/logic/colonel/get_system_settings.rb' => 10,
    'apps/api/domains/cli/helpers.rb' => 1,
    'apps/api/domains/logic/domains/add_domain.rb' => 1,
    'apps/api/domains/logic/domains/get_dns_widget_token.rb' => 1,
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
    'apps/web/billing/operations/webhook_handlers/federation_support.rb' => 2,
    'apps/web/core/controllers/base.rb' => 3,
    'apps/web/core/controllers/health.rb' => 2,
    'apps/web/core/logic/authentication/authenticate_session.rb' => 1,
    'apps/web/core/logic/page/get_favicon.rb' => 1,
    'apps/web/core/logic/page/get_webmanifest.rb' => 1,
    'apps/web/core/middleware/request_setup.rb' => 2,
    'apps/web/core/middleware/vite_proxy.rb' => 1,
    'apps/web/core/views/helpers/initialize_view_vars.rb' => 5,
    'lib/onetime/application/auth_strategies/admin_session_lifetime.rb' => 1,
    'lib/onetime/application/middleware_profile.rb' => 1,
    'lib/onetime/application/middleware_stack.rb' => 7,
    'lib/onetime/application/registry.rb' => 2,
    'lib/onetime/boot.rb' => 4,
    'lib/onetime/domain_validation/sender_strategies/provider_config.rb' => 4,
    'lib/onetime/initializers/configure_domains.rb' => 1,
    'lib/onetime/initializers/setup_loggers.rb' => 1,
    'lib/onetime/mail/mailer.rb' => 6,
    'lib/onetime/mail/views/base.rb' => 5,
    'lib/onetime/middleware/domain_strategy.rb' => 2,
    'lib/onetime/models/custom_domain/brand_settings.rb' => 4,
    'lib/onetime/models/custom_domain/chores/remove_orphaned_approximated_vhosts.rb' => 1,
    'lib/onetime/models/custom_domain/serving_policy.rb' => 1,
    'lib/onetime/models/organization/features/secret_activity.rb' => 1,
    'lib/onetime/operations/domains/collision_resolution.rb' => 1,
    'lib/onetime/operations/domains/teardown.rb' => 1,
    'lib/onetime/operations/verify_domain.rb' => 1,
    'lib/onetime/sso_provider/saml.rb' => 1,
    'lib/onetime/utils/email_hash.rb' => 2,
    'lib/tasks/dev.rake' => 2,
  }.freeze

  module_function

  def source_files
    SOURCE_GLOBS.flat_map { |glob| Dir.glob(File.join(ROOT, glob)) }
      .uniq
      .reject { |path| relative(path).match?(EXCLUDED) }
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

  # A literal path: a String without interpolation, or an Array of them.
  def literal_path(node)
    case node
    when Prism::StringNode
      node.unescaped
    when Prism::ArrayNode
      node.elements.map(&:unescaped) if node.elements.all?(Prism::StringNode)
    end
  end

  def symbol_path?(node)
    symbol = ->(element) { element.is_a?(Prism::SymbolNode) || element.is_a?(Prism::InterpolatedSymbolNode) }
    symbol.call(node) || (node.is_a?(Prism::ArrayNode) && node.elements.any?(&symbol))
  end

  # Collects, for one file, every expression that is the config and every
  # get call on it.
  class Scanner < Prism::Visitor
    attr_reader :gets, :chained_reads

    # @param boot [Boolean] the file is BOOT_FILE
    def initialize(boot: false)
      super()
      @boot          = boot
      @defs          = []
      @uses          = {} # start offset => line, for each expression that is the config
      @get_receivers = []
      @gets          = []
      @chained_reads = []
    end

    # Lines of the uses that are not the receiver of get (rule 1).
    def other_uses
      @uses.except(*@get_receivers).values.sort
    end

    def visit_def_node(node)
      @defs.push(node.name)
      super
    ensure
      @defs.pop
    end

    def visit_instance_variable_read_node(node)
      record_use(node) if config?(node)
      super
    end

    def visit_call_node(node)
      record_use(node) if config?(node)

      if config?(node.receiver) && node.name == :get
        @get_receivers << node.receiver.location.start_offset
        @gets << get_call(node)
      elsif get_result?(node.receiver) && CHAINED_READS.include?(node.name)
        @chained_reads << node.location.start_line
      end

      super
    end

    private

    def record_use(node)
      @uses[node.location.start_offset] = node.location.start_line
    end

    # OT.conf / Onetime.conf anywhere; in BOOT_FILE also conf, self.conf and
    # @conf, outside the conf reader and writer themselves.
    def config?(node)
      case node
      when Prism::CallNode
        return false unless node.name == :conf && node.arguments.nil? && node.block.nil?
        return true if ConfigAccessGuard.root_constant?(node.receiver)

        boot_scope? && (node.receiver.nil? || node.receiver.is_a?(Prism::SelfNode))
      when Prism::InstanceVariableReadNode
        boot_scope? && node.name == :@conf
      else
        false
      end
    end

    def boot_scope?
      @boot && !%i[conf conf=].include?(@defs.last)
    end

    def get_call?(node)
      node.is_a?(Prism::CallNode) && node.name == :get && config?(node.receiver)
    end

    # A get call, also inside parentheses or on the left of ||:
    # (OT.conf.get('a', nil) || {})['b'].
    def get_result?(node)
      case node
      when Prism::ParenthesesNode
        body = node.body
        body.is_a?(Prism::StatementsNode) && body.body.length == 1 && get_result?(body.body.first)
      when Prism::OrNode
        get_result?(node.left)
      else
        get_call?(node)
      end
    end

    def get_call(node)
      args       = node.arguments&.arguments || []
      positional = args.grep_v(Prism::KeywordHashNode)
      {
        line: node.location.start_line,
        path: positional.first && ConfigAccessGuard.literal_path(positional.first),
        default: positional.length >= 2,
        symbol: positional.first && ConfigAccessGuard.symbol_path?(positional.first),
        keyword: args.length != positional.length,
      }
    end
  end

  # @return [Scanner]
  def scan_source(source, label = '(source)', boot: false)
    parsed = Prism.parse(source)
    raise "Guard is broken: #{label} does not parse" unless parsed.success?

    Scanner.new(boot: boot).tap { |scanner| parsed.value.accept(scanner) }
  end

  # @return [Hash{String => Scanner}] the files that use the config
  def scan
    @scan ||= source_files.each_with_object({}) do |path, result|
      source = File.read(path)
      next unless source.include?('conf')

      file    = relative(path)
      scanner = scan_source(source, file, boot: file == BOOT_FILE)
      next if scanner.other_uses.empty? && scanner.gets.empty? && scanner.chained_reads.empty?

      result[file] = scanner
    end
  end

  # @return [Array<Hash>] every get call, with its :file
  def get_calls(scan)
    scan.flat_map { |file, scanner| scanner.gets.map { |call| call.merge(file: file) } }
  end

  # The config boot builds from the shipped defaults. after_load also sets
  # Onetime.d9s_enabled, which is put back.
  def shipped_config
    @shipped_config ||= begin
      d9s_enabled = Onetime.d9s_enabled
      Onetime::Config.after_load(Onetime::Config.load(File.join(ROOT, 'etc/defaults/config.defaults.yaml')))
    ensure
      Onetime.d9s_enabled = d9s_enabled
    end
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
    return false if parts.empty?

    node = config
    parts.all? do |segment|
      next false unless node.is_a?(Hash) && node.key?(segment)

      node = node[segment]
      true
    end
  end

  # Rule 1.
  def use_problems(scan, pending = PENDING, allowed = ALLOWED_USES)
    actual = scan.transform_values { |scanner| scanner.other_uses.length }.reject { |_, count| count.zero? }

    (actual.keys | pending.keys | allowed.keys).sort.filter_map do |file|
      count         = actual.fetch(file, 0)
      allowed_count = allowed.fetch(file, [0]).first
      pending_count = pending.fetch(file, 0)
      expected      = allowed_count + pending_count
      next if count == expected

      if count > expected
        "#{file}:#{scan[file].other_uses.join(', ')} uses OT.conf other than OT.conf.get #{count} times, " \
          "#{expected} allowed; read with OT.conf.get('a.b', default)"
      elsif pending_count.positive? && count > allowed_count
        "#{file} has #{count - allowed_count} pending uses of OT.conf; lower its PENDING count from #{pending_count}"
      elsif pending_count.positive?
        "#{file} has no pending uses of OT.conf left; remove it from PENDING"
      else
        "#{file} uses OT.conf other than OT.conf.get #{count} times; ALLOWED_USES says #{allowed_count}, update it"
      end
    end
  end

  # Rule 2.
  def chained_read_problems(scan)
    scan.flat_map do |file, scanner|
      scanner.chained_reads.map do |line|
        "#{file}:#{line} reads into the result of OT.conf.get; put the whole path in get"
      end
    end
  end

  # Rule 3.
  def unshipped_required_problems(calls, config = shipped_config)
    calls.select { |call| call[:path] && !call[:default] }
      .reject { |call| shipped?(call[:path], config) }
      .map do |call|
        "#{call[:file]}:#{call[:line]} reads #{label(call[:path])} with no default, but the shipped config " \
          'does not have it; fix the path, or pass a default and list it in OPTIONAL_PATHS'
      end
  end

  # Rule 4.
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

  # Rule 5.
  def computed_path_problems(calls)
    calls.select { |call| call[:path].nil? && !call[:symbol] && !call[:default] }
      .map { |call| "#{call[:file]}:#{call[:line]} reads a computed path with no default; pass one" }
  end

  # Rule 6.
  def invalid_call_problems(calls)
    calls.flat_map do |call|
      problems = []
      problems << "#{call[:file]}:#{call[:line]} passes a Symbol path; config paths are Strings" if call[:symbol]
      problems << "#{call[:file]}:#{call[:line]} passes a keyword argument; pass the default positionally" if call[:keyword]
      problems
    end
  end
end

RSpec.describe 'OT.conf access guard' do
  guard = ConfigAccessGuard

  describe 'the codebase' do
    it 'parses every source file and finds config uses' do
      expect(guard.scan.values.sum { |scanner| scanner.other_uses.length + scanner.gets.length }).to be > 0
      expect(guard.scan).to have_key(guard::BOOT_FILE)
    end

    it 'uses OT.conf only as OT.conf.get outside PENDING and ALLOWED_USES, whose counts are current' do
      problems = guard.use_problems(guard.scan)
      expect(problems).to be_empty, problems.join("\n")
    end

    it 'does not read into the result of OT.conf.get' do
      problems = guard.chained_read_problems(guard.scan)
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

    it 'passes no Symbol path and no keyword argument to get' do
      problems = guard.invalid_call_problems(guard.get_calls(guard.scan))
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
        m = OT.conf
        n = Strategy.for_config(OT.conf)
        o = OT.conf.get('site')['hots']
        p = OT.conf.get(:site, {})
        q = OT.conf.get('site.host', default: false)
        r = (OT.conf.get('site.admin', nil) || {})['elevation']
        s = OT.conf.get('site').include?('host')
        t = OT.conf.get(:"site.#{kind}", nil)
      RUBY
    end

    let(:scanner) { guard.scan_source(source) }

    it 'counts every use of OT.conf that is not get, and nothing in comments, strings or other receivers' do
      expect(scanner.other_uses).to eq([1, 2, 3, 4, 5, 14, 15])
    end

    it 'finds a read into the result of get, also through parentheses and ||' do
      expect(scanner.chained_reads).to eq([16, 19, 20])
    end

    it 'classifies get calls by path, default, Symbol path and keyword argument' do
      expect(scanner.gets).to eq([
        { line: 6, path: 'site.host', default: false, symbol: false, keyword: false },
        { line: 7, path: %w[site host], default: true, symbol: false, keyword: false },
        { line: 8, path: nil, default: false, symbol: false, keyword: false },
        { line: 9, path: nil, default: true, symbol: false, keyword: false },
        { line: 16, path: 'site', default: false, symbol: false, keyword: false },
        { line: 17, path: nil, default: true, symbol: true, keyword: false },
        { line: 18, path: 'site.host', default: false, symbol: false, keyword: true },
        { line: 19, path: 'site.admin', default: true, symbol: false, keyword: false },
        { line: 20, path: 'site', default: false, symbol: false, keyword: false },
        { line: 21, path: nil, default: true, symbol: true, keyword: false },
      ])
    end

    context 'in the boot file' do
      let(:boot_source) do
        <<~'RUBY'
          def conf
            @conf
          end

          def conf=(value)
            @conf = value
          end

          def session_config
            x = conf&.dig('site', 'session')
            y = @conf.dig('redis', 'uri')
            z = self.conf.get('site.secret')
            w = conf.get('site.ssl', false)
          end
        RUBY
      end

      it 'counts conf and @conf outside the reader and writer' do
        boot = guard.scan_source(boot_source, boot: true)

        expect(boot.other_uses).to eq([10, 11])
        expect(boot.gets.map { |call| call[:line] }).to eq([12, 13])
      end

      it 'ignores conf and @conf in other files' do
        other = guard.scan_source(boot_source)

        expect(other.other_uses).to be_empty
        expect(other.gets).to be_empty
      end
    end

    it 'reports a file outside the tables, a raised count, a stale count, a cleared file and a changed allowance' do
      scan = { 'new.rb' => scanner, 'grew.rb' => scanner, 'shrank.rb' => scanner, 'kept.rb' => scanner }

      problems = guard.use_problems(
        scan,
        { 'grew.rb' => 6, 'shrank.rb' => 8, 'gone.rb' => 1 },
        { 'kept.rb' => [8, 'reason'] },
      )

      expect(problems).to contain_exactly(
        a_string_starting_with('new.rb:1, 2, 3, 4, 5, 14, 15 uses OT.conf other than OT.conf.get 7 times, 0 allowed'),
        a_string_starting_with('grew.rb:1, 2, 3, 4, 5, 14, 15 uses OT.conf other than OT.conf.get 7 times, 6 allowed'),
        'shrank.rb has 7 pending uses of OT.conf; lower its PENDING count from 8',
        'gone.rb has no pending uses of OT.conf left; remove it from PENDING',
        'kept.rb uses OT.conf other than OT.conf.get 7 times; ALLOWED_USES says 8, update it',
      )
    end

    it 'reports a read into the result of get' do
      expect(guard.chained_read_problems({ 'x.rb' => scanner })).to eq(
        [16, 19, 20].map { |line| "x.rb:#{line} reads into the result of OT.conf.get; put the whole path in get" },
      )
    end

    let(:config) { { 'site' => { 'host' => nil, 'admin' => nil } } }

    let(:calls) do
      [
        { file: 'x.rb', line: 1, path: 'site.host', default: false },
        { file: 'x.rb', line: 2, path: 'site.hots', default: false },
        { file: 'x.rb', line: 3, path: 'site.admin.elevation', default: false },
        { file: 'x.rb', line: 4, path: '', default: false },
        { file: 'x.rb', line: 5, path: 'site.product_name', default: true },
        { file: 'x.rb', line: 6, path: %w[site host], default: true },
        { file: 'x.rb', line: 7, path: nil, default: false },
        { file: 'x.rb', line: 8, path: nil, default: true },
        { file: 'x.rb', line: 9, path: nil, default: true, symbol: true },
        { file: 'x.rb', line: 10, path: 'site.host', default: false, keyword: true },
      ]
    end

    it 'reports a no-default read of a path the shipped config lacks, below a nil section, or empty' do
      expect(guard.unshipped_required_problems(calls, config)).to contain_exactly(
        a_string_starting_with('x.rb:2 reads site.hots with no default'),
        a_string_starting_with('x.rb:3 reads site.admin.elevation with no default'),
        a_string_starting_with('x.rb:4 reads  with no default'),
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

    it 'reports a Symbol path and a keyword argument' do
      expect(guard.invalid_call_problems(calls)).to eq([
        'x.rb:9 passes a Symbol path; config paths are Strings',
        'x.rb:10 passes a keyword argument; pass the default positionally',
      ])
    end

    it 'builds the shipped config the way boot does' do
      expect(guard.shipped?('site.host')).to be(true)
      expect(guard.shipped?('site.no_such_key')).to be(false)
      expect(guard.shipped?('brand_manifest.operator_keys')).to be(true)
      expect(guard.shipped?('brand_manifest.absorbed_key')).to be(false)
      expect(guard.shipped?('diagnostics.sentry.backend.sampleRate')).to be(true)
      expect(guard.shipped?('diagnostics.sentry.defaults')).to be(false)
    end
  end
end
