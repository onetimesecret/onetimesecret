# spec/unit/onetime/config/access_guard_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Static guard — main-config reads go through OT.conf.get
# =============================================================================
#
# Code reads the main config with OT.conf.get('a.b.c'[, default])
# (Onetime::Config::Reader), so that grepping a dotted path finds every
# reader of that setting. RuboCop cannot enforce that here, because
# .rubocop.yml excludes apps/api/v1 and every spec and try directory, so this
# spec does. Calls are found with Prism, so comments and strings never match.
#
# In lib/ and apps/:
#
#   1. OT.conf (or Onetime.conf) is used only as the receiver of get. Every
#      other use counts: dig, fetch, key? or [] on it, assigning it to a
#      variable, passing it as an argument, a truthiness guard. In
#      lib/onetime/boot.rb the config is also `conf` and `@conf`. A use that
#      stays is listed in ALLOWED_USES with its count and reason.
#   2. Nothing reads into a section (a Hash) that get returned: not on the
#      call (OT.conf.get('site')['host']), and not through a local or
#      instance variable that holds it, a method or RSpec let that returns
#      it, or an attr_reader of such an instance variable
#      (`admin = OT.conf.get('site.admin', {}); admin['enabled']`), also from
#      one branch of a conditional or the left of ||.
#      The whole path goes in get, where rules 3 to 5 can check it. A get
#      result is a section when the shipped config has a Hash at its path,
#      or, for a path the shipped config does not have, when its default is
#      not a literal of another type. Iterating, copying or serializing a
#      section is not a read.
#   3. A get with a literal path and no default names a path that the shipped
#      config has: etc/defaults/config.defaults.yaml, run through
#      Config.after_load as boot does. A typo or a stale path fails here, not
#      in production.
#   4. A get with a literal path and a default, whose path is not in the
#      shipped config, is listed in OPTIONAL_PATHS with the reason it can be
#      absent.
#   5. A get whose path is not a literal (an Array with a variable segment,
#      an interpolated String, a variable) passes a default, and its literal
#      leading segments name a path the shipped config has.
#   6. A get has no Symbol path and no keyword argument; both raise.
#   7. A get with a literal path and no default does not raise when an
#      operator file sets a section on that path to nil. Config.load lets
#      such a nil replace the defaults section (preserve_nils: false), and
#      Config.after_load refills some sections from Config::DEFAULTS with
#      fewer keys. dig read every such key as nil; pass nil as the default.
#
# In test code (spec/ and try/ directories, *_spec.rb and *_try.rb files,
# e2e/ and tests/), which builds, replaces and stubs configs of its own:
#
#   8. OT.conf, and a local variable that holds it, never receives a read
#      (dig, fetch, key?, [] and the other Hash lookups). A test reads with
#      get, and writes through it: OT.conf.get('site')['host'] = 'example.com'.
#      A write to a top-level key (OT.conf['site'] = {...}), a copy
#      (OT.conf.dup, YAML.dump(OT.conf)) and a stub are not reads.
#   Rules 2 and 6 apply as in lib/ and apps/. Rules 3 to 5 and 7 do not: a
#   test reads the config it set up, and get raises on a path that config
#   does not have.
#
# Rule 2 follows a section through variables and methods in one file. A
# section passed as an argument to another method, or yielded to a block
# (each, map), is not followed.
#
# =============================================================================

require 'spec_helper'
require 'prism'

module ConfigAccessGuard
  ROOT = File.expand_path('../../../..', __dir__)

  SOURCE_GLOBS = %w[lib/**/*.rb lib/**/*.rake apps/**/*.rb apps/**/*.ru config.ru].freeze
  EXCLUDED     = %r{(\A|/)(spec|try)/|_spec\.rb\z|_try\.rb\z}

  # Test code: the EXCLUDED files of SOURCE_GLOBS, and these.
  TEST_GLOBS = %w[spec/**/*.rb try/**/*.rb e2e/**/*.rb tests/**/*.rb].freeze

  # The file where the config is also read as `conf` and `@conf`.
  BOOT_FILE = 'lib/onetime/boot.rb'

  DIRECT_READS = %i[dig fetch key? []].freeze

  # Reads into a section (rule 2): the direct reads plus the other ways to
  # look inside a Hash.
  CHAINED_READS = (DIRECT_READS + %i[has_key? include? member? values_at fetch_values slice then]).freeze

  # Reads of OT.conf in test code (rule 8). then is a whole-config operation
  # there.
  TEST_READS = (CHAINED_READS - %i[then]).freeze

  # Default literals whose type is not a Hash: a get with one of these
  # returns a value, not a section, when the path is absent.
  VALUE_LITERALS = [
    Prism::ArrayNode, Prism::StringNode, Prism::InterpolatedStringNode, Prism::IntegerNode,
    Prism::FloatNode, Prism::RationalNode, Prism::TrueNode, Prism::FalseNode, Prism::SymbolNode
  ].freeze

  # Literal paths read with a default that are not in the shipped config,
  # with the reason each can be absent.
  OPTIONAL_PATHS = {
    'emailer.allow_unauthenticated_fallback' => 'opt-in: Delivery::SMTP retries without AUTH after the server rejects it only when set',
    'emailer.domain' => 'SMTP HELO domain; SMTP_DOMAIN is read when it is unset',
    'emailer.fromname' => 'deprecated since v0.23 (from_name replaces it); read only when from_name is unset',
    'emailer.lettermint_api_token' => 'operator-set override; email_providers.lettermint, emailer.pass and LETTERMINT_API_TOKEN follow',
    'emailer.lettermint_base_url' => 'operator-set override; email_providers.lettermint and LETTERMINT_BASE_URL follow',
    'emailer.lettermint_team_token' => 'operator-set override; email_providers.lettermint and LETTERMINT_TEAM_TOKEN follow',
    'emailer.lettermint_timeout' => 'operator-set override; the Lettermint client default applies without it',
    'emailer.sendgrid_api_key' => 'operator-set override; emailer.pass and SENDGRID_API_KEY follow',
    'emailer.smtp2go_api_key' => 'operator-set override; email_providers.smtp2go and SMTP2GO_API_KEY follow',
    'emailer.smtp2go_timeout' => 'operator-set override; the SMTP2GO client default applies without it',
    'features.domains.strict_strategy' => 'opt-in: an unknown validation_strategy raises instead of falling back to passthrough',
    'jobs.dlq_monitor_enabled' => 'opt-in switch for DlqMonitorJob; the defaults file does not define it',
    'jobs.domain_refresh.rate_limit' => "commented out in the defaults: unset means the strategy's own pacing",
    'jobs.heartbeat_enabled' => 'opt-in switch for HeartbeatJob; the defaults file does not define it',
    'jobs.maintenance.housekeeping.batch_size' => 'operator-set; HousekeepingJob::DEFAULT_BATCH_SIZE without it',
    'jobs.maintenance.housekeeping.models' => 'operator-set model list; HousekeepingJob scans its default model list without it',
    'jobs.rabbitmq_management_url' => 'optional; RABBITMQ_MANAGEMENT_URL or localhost is used without it',
    'locales' => 'legacy top-level list, read when internationalization.locales is unset',
    'site.authentication.colonels' => 'operator-set list of colonel emails; the defaults file does not define it',
    'site.authentication.external.enabled' => 'opt-in external auth section; the defaults file does not define it',
    'site.authentication.external.service_url' => 'opt-in external auth section; the defaults file does not define it',
    'site.federation_secret' => 'FEDERATION_SECRET is read first; the defaults file does not define this key',
  }.freeze

  # Test files that read into a config section on purpose (rule 2), with the
  # reason: they test the section Hashes themselves.
  TEST_SECTION_READS = {
    'spec/unit/onetime/config/strict_keys_spec.rb' => 'StrictKeys raises on a Symbol read into a section',
    'try/unit/config/strict_keys_try.rb' => 'StrictKeys raises on a Symbol read into a section',
  }.freeze

  # Uses of OT.conf other than OT.conf.get that stay: file => [count, reason].
  ALLOWED_USES = {
    'lib/onetime/application/registry.rb' => [2, 'warns on an app registered before boot (nil?); the config object is the rack_url_map cache token (object_id)'],
    'lib/onetime/config.rb' => [1, 'apply_config merges an override over the whole config'],
  }.freeze

  module_function

  def source_files
    SOURCE_GLOBS.flat_map { |glob| Dir.glob(File.join(ROOT, glob)) }
      .uniq
      .reject { |path| relative(path).match?(EXCLUDED) }
      .sort
  end

  def test_files
    sources = SOURCE_GLOBS.flat_map { |glob| Dir.glob(File.join(ROOT, glob)) }
      .select { |path| relative(path).match?(EXCLUDED) }
    (sources + TEST_GLOBS.flat_map { |glob| Dir.glob(File.join(ROOT, glob)) })
      .uniq
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

  # The literal segments before the first computed one, or nil: ['site',
  # 'admin'] for ['site', 'admin', key] and for "site.admin.#{key}".
  def literal_prefix(node)
    parts = case node
            when Prism::ArrayNode then node.elements.take_while { |e| e.is_a?(Prism::StringNode) }.map(&:unescaped)
            when Prism::InterpolatedStringNode
              head = node.parts.first
              head.is_a?(Prism::StringNode) ? head.unescaped.split('.', -1)[0...-1] : []
            else []
            end
    parts.empty? ? nil : parts
  end

  def symbol_path?(node)
    symbol = ->(element) { element.is_a?(Prism::SymbolNode) || element.is_a?(Prism::InterpolatedSymbolNode) }
    symbol.call(node) || (node.is_a?(Prism::ArrayNode) && node.elements.any?(&symbol))
  end

  # :hash for a Hash literal, :value for a literal of another type, nil for
  # no default, nil, or an expression.
  def default_kind(node)
    case node
    when Prism::HashNode then :hash
    when *VALUE_LITERALS then :value
    end
  end

  # Collects, for one file, every expression that is the config, every get
  # call on it, and every read into a section that a get call returned.
  class Scanner < Prism::Visitor
    attr_reader :gets, :test_reads

    # @param boot [Boolean] the file is BOOT_FILE
    # @param test [Boolean] the file is test code (rule 8)
    def initialize(boot: false, test: false)
      super()
      @boot          = boot
      @test          = test
      @defs          = []
      @uses          = {} # start offset => line, for each expression that is the config
      @get_receivers = []
      @gets          = []
      @test_reads    = []
      @reads         = [] # [line, get call] for reads whose holder is known
      @pending       = [] # [line, :ivar or :method, name] resolved by #chained_reads
      @locals        = [{}] # per scope: name => get call, [:method, name], or :config
      @ivars         = {}   # name => get call or [:method, name]
      @methods       = {}   # name => get call
      @attr_readers  = {}   # method name => instance variable, from attr_reader
      @config_lets   = []   # in test code: lets that return OT.conf
    end

    # Lines of the uses that are not the receiver of get (rule 1).
    def other_uses
      @uses.except(*@get_receivers).values.sort
    end

    # Reads into a get result (rule 2), each { line:, call: } with the get
    # call that returned the value read into, in source order.
    def chained_reads
      resolved = @pending.filter_map do |line, kind, name|
        held = kind == :ivar ? @ivars[name] : (@methods[name] || @ivars[@attr_readers[name]])
        held = @methods[held.last] if held.is_a?(Array)
        [line, held] if held
      end
      (@reads + resolved).sort_by(&:first).map { |line, call| { line: line, call: call } }
    end

    # A method whose last expression is a section is recorded once its body
    # is visited, so that a local it returns is known.
    def visit_def_node(node)
      @defs.push(node.name)
      @locals.push({})
      super
      returned = held_by(node.body)
      @methods[node.name] = returned if returned.is_a?(Hash)
    ensure
      @locals.pop
      @defs.pop
    end

    def visit_class_node(node)
      in_scope { super }
    end

    def visit_module_node(node)
      in_scope { super }
    end

    def visit_singleton_class_node(node)
      in_scope { super }
    end

    def visit_local_variable_write_node(node)
      hold_local(node.name, node.value)
      super
    end

    def visit_local_variable_or_write_node(node)
      hold_local(node.name, node.value)
      super
    end

    def visit_local_variable_operator_write_node(node)
      @locals.last.delete(node.name)
      super
    end

    def visit_instance_variable_write_node(node)
      hold_ivar(node.name, node.value)
      super
    end

    def visit_instance_variable_or_write_node(node)
      hold_ivar(node.name, node.value)
      super
    end

    def visit_instance_variable_read_node(node)
      record_use(node) if config?(node)
      super
    end

    def visit_local_variable_read_node(node)
      record_use(node) if config?(node)
      super
    end

    def visit_call_node(node)
      record_use(node) if config?(node)

      if config?(node.receiver) && node.name == :get
        @get_receivers << node.receiver.location.start_offset
        @gets << get_call(node)
      elsif CHAINED_READS.include?(node.name)
        record_read(node)
      end

      @test_reads << node.location.start_line if @test && config?(node.receiver) && TEST_READS.include?(node.name)
      record_attr_readers(node)
      record_let(node)

      super
    end

    private

    # let(:admin) { OT.conf.get('site.admin') } makes `admin` return it.
    def record_let(node)
      return unless node.receiver.nil? && %i[let let!].include?(node.name) && node.block.is_a?(Prism::BlockNode)

      name = node.arguments&.arguments&.first
      return unless name.is_a?(Prism::SymbolNode)

      body = node.block.body
      held = held_by(body)
      @methods[name.unescaped.to_sym] = held if held.is_a?(Hash)
      last = body.is_a?(Prism::StatementsNode) ? body.body.last : body
      @config_lets << name.unescaped.to_sym if @test && config?(last)
    end

    # attr_reader :site makes `site` return @site.
    def record_attr_readers(node)
      return unless node.receiver.nil? && %i[attr_reader attr_accessor].include?(node.name)

      node.arguments&.arguments&.grep(Prism::SymbolNode)&.each do |symbol|
        @attr_readers[symbol.unescaped.to_sym] = :"@#{symbol.unescaped}"
      end
    end

    def in_scope
      @locals.push({})
      yield
    ensure
      @locals.pop
    end

    def record_use(node)
      @uses[node.location.start_offset] = node.location.start_line
    end

    # A read into what +node+'s receiver holds: a get call, a local holding
    # one, or (resolved later) an instance variable or a method.
    def record_read(node)
      receiver = node.receiver
      line     = node.location.start_line
      held     = held_by(receiver)

      case held
      when Hash then @reads << [line, held]
      when Array then @pending << [line, :method, held.last]
      else
        if receiver.is_a?(Prism::InstanceVariableReadNode)
          @pending << [line, :ivar, receiver.name]
        elsif method_call?(receiver)
          @pending << [line, :method, receiver.name]
        end
      end
    end

    # `name`, `name(args)` or `self.name`, without a block.
    def method_call?(node)
      node.is_a?(Prism::CallNode) && node.block.nil? &&
        (node.receiver.nil? || node.receiver.is_a?(Prism::SelfNode)) && !config?(node)
    end

    def hold_local(name, value)
      held = held_by(value)
      held ||= [:method, value.name] if method_call?(value)
      if held
        @locals.last[name] = held
      elsif @test && config?(value)
        @locals.last[name] = :config
      else
        @locals.last.delete(name)
      end
    end

    def hold_ivar(name, value)
      held = held_by(value)
      held ||= [:method, value.name] if method_call?(value)
      @ivars[name] = held if held
    end

    # What +node+ evaluates to, when that can be a get result: the get call
    # (as #get_call describes it), or [:method, name] for a local that holds
    # the return value of a method in this file. Looks through parentheses,
    # the left of ||, the branches of a conditional, the last statement of a
    # body, an assignment (@x = OT.conf.get(...) or @x ||= ...), and locals
    # of the current scope.
    def held_by(node)
      case node
      when Prism::CallNode then get_call(node) if get_call?(node)
      when Prism::OrNode then held_by(node.left)
      when Prism::ParenthesesNode then held_by(node.body)
      when Prism::StatementsNode then held_by(node.body.last)
      when Prism::BeginNode then held_by(node.statements) unless node.rescue_clause
      when Prism::IfNode then held_by(node.statements) || held_by(node.subsequent)
      when Prism::UnlessNode then held_by(node.statements) || held_by(node.else_clause)
      when Prism::ElseNode then held_by(node.statements)
      when Prism::InstanceVariableOrWriteNode, Prism::LocalVariableOrWriteNode,
           Prism::InstanceVariableWriteNode, Prism::LocalVariableWriteNode
        held_by(node.value)
      when Prism::LocalVariableReadNode
        held = @locals.last[node.name]
        held unless held == :config
      end
    end

    # OT.conf / Onetime.conf anywhere; in BOOT_FILE also conf, self.conf and
    # @conf, outside the conf reader and writer themselves; in test code also
    # a local variable or a let that holds OT.conf.
    def config?(node)
      case node
      when Prism::CallNode
        return true if @test && node.receiver.nil? && node.arguments.nil? && @config_lets.include?(node.name)
        return false unless node.name == :conf && node.arguments.nil? && node.block.nil?
        return true if ConfigAccessGuard.root_constant?(node.receiver)

        boot_scope? && (node.receiver.nil? || node.receiver.is_a?(Prism::SelfNode))
      when Prism::InstanceVariableReadNode
        boot_scope? && node.name == :@conf
      when Prism::LocalVariableReadNode
        @test && @locals.last[node.name] == :config
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

    def get_call(node)
      args       = node.arguments&.arguments || []
      positional = args.grep_v(Prism::KeywordHashNode)
      {
        line: node.location.start_line,
        path: positional.first && ConfigAccessGuard.literal_path(positional.first),
        prefix: nil,
        default: positional.length >= 2 || node.block.is_a?(Prism::BlockNode),
        default_kind: ConfigAccessGuard.default_kind(positional[1]),
        symbol: positional.first && ConfigAccessGuard.symbol_path?(positional.first),
        keyword: args.length != positional.length,
      }.tap do |call|
        call[:prefix] = ConfigAccessGuard.literal_prefix(positional.first) if call[:path].nil? && positional.first
      end
    end
  end

  # @return [Scanner]
  def scan_source(source, label = '(source)', boot: false, test: false)
    parsed = Prism.parse(source)
    raise "Guard is broken: #{label} does not parse" unless parsed.success?

    Scanner.new(boot: boot, test: test).tap { |scanner| parsed.value.accept(scanner) }
  end

  # @return [Hash{String => Scanner}] the files that use the config
  def scan
    @scan ||= scan_files(source_files)
  end

  # @return [Hash{String => Scanner}] the test files that use the config
  def scan_tests
    @scan_tests ||= scan_files(test_files, test: true)
  end

  def scan_files(paths, test: false)
    paths.each_with_object({}) do |path, result|
      source = File.read(path)
      next unless source.include?('conf')

      file    = relative(path)
      scanner = scan_source(source, file, boot: file == BOOT_FILE, test: test)
      next if [scanner.other_uses, scanner.gets, scanner.chained_reads, scanner.test_reads].all?(&:empty?)

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

  # Whether a get call returns a section (rule 2): the shipped value at its
  # path is a Hash; or, when that value is nil or the path is not shipped or
  # not a literal, its default is not a literal of another type.
  def section?(call, config = shipped_config)
    if call[:path] && shipped?(call[:path], config)
      value = segments(call[:path]).reduce(config) { |node, segment| node[segment] }
      return value.is_a?(Hash) unless value.nil?
    end

    call[:default_kind] != :value
  end

  # Rule 1.
  def use_problems(scan, allowed = ALLOWED_USES)
    actual = scan.transform_values { |scanner| scanner.other_uses.length }.reject { |_, count| count.zero? }

    (actual.keys | allowed.keys).sort.filter_map do |file|
      count         = actual.fetch(file, 0)
      allowed_count = allowed.fetch(file, [0]).first
      next if count == allowed_count

      if count > allowed_count
        "#{file}:#{scan[file].other_uses.join(', ')} uses OT.conf other than OT.conf.get #{count} times, " \
          "#{allowed_count} allowed; read with OT.conf.get('a.b', default)"
      else
        "#{file} uses OT.conf other than OT.conf.get #{count} times; ALLOWED_USES says #{allowed_count}, update it"
      end
    end
  end

  # Rule 2.
  def chained_read_problems(scan, config = shipped_config)
    scan.flat_map do |file, scanner|
      scanner.chained_reads.select { |read| section?(read[:call], config) }.map { |read| read[:line] }.uniq.map do |line|
        "#{file}:#{line} reads into a section that OT.conf.get returned; put the whole path in get"
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
  def computed_path_problems(calls, config = shipped_config)
    no_default = calls.select { |call| call[:path].nil? && !call[:symbol] && !call[:default] }
      .map { |call| "#{call[:file]}:#{call[:line]} reads a computed path with no default; pass one" }
    unshipped  = calls.select { |call| call[:path].nil? && call[:prefix] && !shipped?(call[:prefix], config) }
      .map do |call|
        "#{call[:file]}:#{call[:line]} reads a computed path below #{path_key(call[:prefix])}, " \
          'which the shipped config does not have; fix the literal segments'
      end
    no_default + unshipped
  end

  # The YAML layer of the shipped config, before after_load.
  def yaml_defaults
    @yaml_defaults ||= Onetime::Config.load(File.join(ROOT, 'etc/defaults/config.defaults.yaml'))
  end

  # The config boot builds when an operator file sets +section+ to nil, or
  # nil when after_load rejects it (boot fails on it already).
  def config_with_nil_section(section, base = yaml_defaults)
    operator = section[0..-2].reverse.reduce({ section.last => nil }) { |inner, key| { key => inner } }
    merged   = Onetime::Utils::Enumerables.deep_merge(base, operator, preserve_nils: false)
    d9s_enabled = Onetime.d9s_enabled
    Onetime::Config.after_load(merged)
  rescue Onetime::ConfigError
    nil
  ensure
    Onetime.d9s_enabled = d9s_enabled
  end

  # Rule 7.
  def nil_section_problems(calls, base = yaml_defaults)
    required = calls.select { |call| call[:path] && !call[:default] }
    sections = required.flat_map { |call| (1...segments(call[:path]).size).map { |n| segments(call[:path])[0, n] } }.uniq

    sections.flat_map do |section|
      conf = config_with_nil_section(section, base)
      next [] unless conf

      required.select { |call| segments(call[:path])[0, section.size] == section }.filter_map do |call|
        conf.get(call[:path])
        nil
      rescue KeyError, TypeError => ex
        "#{call[:file]}:#{call[:line]} reads #{label(call[:path])} with no default, which raises " \
          "(#{ex.class.name.split('::').last}) when an operator file sets #{section.join('.')} to nil; pass nil as the default"
      end
    end
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

  # Rule 8.
  def test_read_problems(scan)
    scan.flat_map do |file, scanner|
      scanner.test_reads.uniq.map do |line|
        "#{file}:#{line} reads OT.conf without get; read with OT.conf.get('a.b'), " \
          "write through it: OT.conf.get('a')['b'] = value"
      end
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

    it 'uses OT.conf only as OT.conf.get outside ALLOWED_USES, whose counts are current' do
      problems = guard.use_problems(guard.scan)
      expect(problems).to be_empty, problems.join("\n")
    end

    it 'does not read into a section that OT.conf.get returned' do
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

    it 'reads no required path that a nil section in an operator file leaves unset' do
      problems = guard.nil_section_problems(guard.get_calls(guard.scan))
      expect(problems).to be_empty, problems.join("\n")
    end

    it 'passes no Symbol path and no keyword argument to get' do
      problems = guard.invalid_call_problems(guard.get_calls(guard.scan))
      expect(problems).to be_empty, problems.join("\n")
    end
  end

  describe 'the test code' do
    it 'parses every test file and finds config uses' do
      expect(guard.scan_tests.values.sum { |scanner| scanner.gets.length }).to be > 0
      expect(guard.scan_tests.keys).to include(a_string_starting_with('spec/'), a_string_starting_with('try/'))
    end

    it 'reads OT.conf only through OT.conf.get' do
      problems = guard.test_read_problems(guard.scan_tests)
      expect(problems).to be_empty, problems.join("\n")
    end

    it 'does not read into a section that OT.conf.get returned, outside TEST_SECTION_READS' do
      problems = guard.chained_read_problems(guard.scan_tests.except(*guard::TEST_SECTION_READS.keys))
      expect(problems).to be_empty, problems.join("\n")
    end

    it 'lists in TEST_SECTION_READS only files that read into a section' do
      listed = guard::TEST_SECTION_READS.keys
      stale  = listed.reject { |file| guard.chained_read_problems(guard.scan_tests.slice(file)).any? }
      expect(stale).to be_empty, "TEST_SECTION_READS lists files with no section read: #{stale.join(', ')}"
    end

    it 'passes no Symbol path and no keyword argument to get' do
      problems = guard.invalid_call_problems(guard.get_calls(guard.scan_tests))
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
      expect(scanner.chained_reads.map { |read| read[:line] }).to eq([16, 19, 20])
      expect(scanner.chained_reads.map { |read| read[:call][:path] }).to eq(%w[site site.admin site])
    end

    it 'classifies get calls by path, default, Symbol path and keyword argument' do
      expect(scanner.gets).to eq([
        { line: 6, path: 'site.host', prefix: nil, default: false, default_kind: nil, symbol: false, keyword: false },
        { line: 7, path: %w[site host], prefix: nil, default: true, default_kind: nil, symbol: false, keyword: false },
        { line: 8, path: nil, prefix: %w[features], default: false, default_kind: nil, symbol: false, keyword: false },
        { line: 9, path: nil, prefix: %w[features], default: true, default_kind: :value, symbol: false, keyword: false },
        { line: 16, path: 'site', prefix: nil, default: false, default_kind: nil, symbol: false, keyword: false },
        { line: 17, path: nil, prefix: nil, default: true, default_kind: :hash, symbol: true, keyword: false },
        { line: 18, path: 'site.host', prefix: nil, default: false, default_kind: nil, symbol: false, keyword: true },
        { line: 19, path: 'site.admin', prefix: nil, default: true, default_kind: nil, symbol: false, keyword: false },
        { line: 20, path: 'site', prefix: nil, default: false, default_kind: nil, symbol: false, keyword: false },
        { line: 21, path: nil, prefix: nil, default: true, default_kind: nil, symbol: true, keyword: false },
      ])
    end

    context 'with a section held in a variable or returned by a method' do
      let(:held_source) do
        <<~'RUBY'
          class Holder
            def admin
              OT.conf.get('site.admin', {})
            end

            def memoized
              @memoized ||= OT.conf.get('site.authentication', nil)
            end

            def with_param(name)
              OT.conf.get('site.admin', {})
            end

            def run
              a = OT.conf.get('site.admin', {})
              a['elevation']
              b = OT.conf.get('site.admin.allowlist', [])
              b.include?('x')
              c = OT.conf.get('site.admin', {})
              c = {}
              c['elevation']
              admin['elevation']
              memoized['enabled']
              @memoized.dig('signup')
              with_param(1)['elevation']
              @held['enabled']
              a['elevation'] = 1
              a.each { |key, value| value }
              self.admin.fetch('elevation')
              checked = guarded
              checked['elevation']
              (flag ? OT.conf.get('site.admin') : {})['elevation']
              site.fetch('host')
              memo_write['enabled']
            end

            def other_scope
              a['elevation']
            end

            def held
              @held = OT.conf.get('site.authentication')
            end

            def guarded
              domains = OT.conf.get('site.admin', {})
              domains.is_a?(Hash) ? domains : {}
            end

            attr_reader :site

            def setup
              @site = OT.conf.get('site', {})
            end

            def memo_write
              return @memo if defined?(@memo)

              @memo = OT.conf.get('site.authentication', {})
            end
          end
        RUBY
      end

      let(:held) { guard.scan_source(held_source) }

      let(:config) do
        { 'site' => { 'host' => 'x', 'admin' => { 'elevation' => {}, 'allowlist' => [] }, 'authentication' => { 'enabled' => true } } }
      end

      it 'follows locals in their scope, instance variables, attr_readers, methods and conditionals' do
        expect(held.chained_reads.map { |read| read[:line] }).to eq([16, 18, 22, 23, 24, 25, 26, 29, 31, 32, 33, 34])
      end

      it 'reports reads into a section, and not into another value' do
        expect(guard.chained_read_problems({ 'x.rb' => held }, config)).to eq(
          [16, 22, 23, 24, 25, 26, 29, 31, 32, 33, 34].map do |line|
            "x.rb:#{line} reads into a section that OT.conf.get returned; put the whole path in get"
          end,
        )
      end

      it 'decides from the shipped value, then from the default literal' do
        expect(guard.section?({ path: 'site.admin', default_kind: nil }, config)).to be(true)
        expect(guard.section?({ path: 'site.admin.allowlist', default_kind: :hash }, config)).to be(false)
        expect(guard.section?({ path: 'site.absent', default_kind: :value }, config)).to be(false)
        expect(guard.section?({ path: 'site.absent', default_kind: :hash }, config)).to be(true)
        expect(guard.section?({ path: nil, default_kind: nil }, config)).to be(true)
      end
    end

    context 'in test code' do
      let(:test_source) do
        <<~'RUBY'
          a = OT.conf.dig('site', 'host')
          OT.conf['site']['host'] = 'example.com'
          OT.conf['site'] = {}
          OT.conf.get('site')['host'] = 'example.com'
          copy = OT.conf.dup
          copy['site']
          held = OT.conf
          held['site']
          held.get('site.host')
          YAML.dump(OT.conf)
          OT.conf.to_h.merge('site' => {})
          OT.conf.key?('site')
          section = OT.conf.get('site')
          section['host']
          allow(OT).to receive(:conf).and_return(OT::Config.wrap({}))
          let(:network) { OT.conf.get('site.network') }
          network['assume_https']
          let(:conf_alias) { OT.conf }
          conf_alias['site']
        RUBY
      end

      let(:test_scanner) { guard.scan_source(test_source, test: true) }

      it 'finds reads of OT.conf and of a local or let holding it, and not writes, copies or stubs' do
        expect(test_scanner.test_reads).to eq([1, 2, 8, 12, 19])
      end

      it 'counts get on a local holding OT.conf' do
        expect(test_scanner.gets.map { |call| call[:line] }).to eq([4, 9, 13, 16])
      end

      it 'follows a section into a local and a let' do
        expect(test_scanner.chained_reads.map { |read| read[:line] }).to eq([14, 17])
      end

      it 'reports each read' do
        expect(guard.test_read_problems({ 'x_spec.rb' => test_scanner })).to eq(
          [1, 2, 8, 12, 19].map do |line|
            "x_spec.rb:#{line} reads OT.conf without get; read with OT.conf.get('a.b'), " \
              "write through it: OT.conf.get('a')['b'] = value"
          end,
        )
      end

      it 'treats a local holding OT.conf as a plain variable outside test code' do
        expect(guard.scan_source(test_source).test_reads).to be_empty
      end
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

    it 'reports a file outside ALLOWED_USES, a raised count, a lowered count and a cleared file' do
      scan = { 'new.rb' => scanner, 'grew.rb' => scanner, 'shrank.rb' => scanner, 'kept.rb' => scanner }

      problems = guard.use_problems(
        scan,
        { 'grew.rb' => [6, 'reason'], 'shrank.rb' => [8, 'reason'], 'kept.rb' => [7, 'reason'], 'gone.rb' => [1, 'reason'] },
      )

      expect(problems).to contain_exactly(
        a_string_starting_with('new.rb:1, 2, 3, 4, 5, 14, 15 uses OT.conf other than OT.conf.get 7 times, 0 allowed'),
        a_string_starting_with('grew.rb:1, 2, 3, 4, 5, 14, 15 uses OT.conf other than OT.conf.get 7 times, 6 allowed'),
        'shrank.rb uses OT.conf other than OT.conf.get 7 times; ALLOWED_USES says 8, update it',
        'gone.rb uses OT.conf other than OT.conf.get 0 times; ALLOWED_USES says 1, update it',
      )
    end

    it 'reports a read into the result of get' do
      expect(guard.chained_read_problems({ 'x.rb' => scanner }, { 'site' => { 'admin' => {} } })).to eq(
        [16, 19, 20].map { |line| "x.rb:#{line} reads into a section that OT.conf.get returned; put the whole path in get" },
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
        { file: 'x.rb', line: 8, path: nil, prefix: %w[site hots], default: true },
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

    it 'reports a computed path without a default, or below a path the shipped config lacks' do
      expect(guard.computed_path_problems(calls, config)).to eq([
        'x.rb:7 reads a computed path with no default; pass one',
        'x.rb:8 reads a computed path below site.hots, which the shipped config does not have; fix the literal segments',
      ])
    end

    # Config::DEFAULTS refills features.domains without a default key, so an
    # operator file with an empty `domains:` leaves features.domains.default
    # absent.
    it 'reports a required read that a nil section leaves absent, and not one with a default' do
      calls = [
        { file: 'x.rb', line: 1, path: 'features.domains.default', default: false },
        { file: 'y.rb', line: 2, path: 'features.domains.default', default: true },
      ]

      expect(guard.nil_section_problems(calls)).to contain_exactly(
        'x.rb:1 reads features.domains.default with no default, which raises (MissingPathError) ' \
        'when an operator file sets features to nil; pass nil as the default',
        'x.rb:1 reads features.domains.default with no default, which raises (MissingPathError) ' \
        'when an operator file sets features.domains to nil; pass nil as the default',
      )
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
