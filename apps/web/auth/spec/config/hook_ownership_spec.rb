# apps/web/auth/spec/config/hook_ownership_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Static analysis guard
# =============================================================================
#
# WHAT THIS TESTS:
#   The one-owner invariant documented in apps/web/auth/config/hooks.rb:
#   every Rodauth before/after/around hook name is defined in exactly ONE
#   place across apps/web/auth/config/**/*.rb.
#
#   Rodauth hooks do NOT chain. Each `auth.<hook> do ... end` inside the
#   configure block REPLACES the prior definition for that hook name, so a
#   second definition silently kills the first module's logic. That is bug
#   #3275 (see hooks/password.rb) and the before_omniauth_callback_route
#   collision fixed on this branch.
#
#   And its second half (#4432): a hook can also be WRAPPED, by a module that
#   defines the hook method with `def` and is prepended onto the auth class.
#   Wrappers DO chain, in ancestor order, through `super`. The registration
#   scan cannot see them, so the approved wrapper set is pinned separately:
#   every `def before_/after_/around_*` in the config tree must be listed in
#   approved_hook_wrappers below, and each listed module must be prepended exactly
#   once. The order a wrapper takes at runtime is asserted where the auth
#   class exists: spec/integration/full/omniauth_callback_wrapper_order_spec.rb.
#
# HOW IT TESTS:
#   Pure static scan — File.read + line-anchored regex for registrations,
#   and a Prism parse for wrappers (the enclosing module name of a `def` is
#   not recoverable from one line). It deliberately does
#   NOT require apps/web/auth/config.rb or boot anything (that file's header
#   forbids test files from requiring it). This is an intentional exception
#   to the "no string matching on config files" rule used by the runtime
#   feature specs in this directory: the property under test (textual
#   duplicate definitions) is only visible statically, because at runtime the
#   duplicate has already been silently replaced.
#
# =============================================================================

require_relative '../spec_helper'
require 'prism'

# Static scanner for Rodauth hook definitions.
#
# A "hook definition" is a statement-initial call of the form:
#
#   auth.before_login_attempt do
#   rodauth.after_login do |account|
#   around_rodauth do |&blk|
#
# i.e. optional `auth.` / `rodauth.` receiver, a (before|after|around)_*
# method name, followed by a `do` block (block args allowed). Comment lines
# are ignored; mid-line mentions (strings, docs) don't match because the
# pattern is anchored to the start of the statement.
module RodauthHookOwnershipScanner
  HOOK_DEFINITION = /\A\s*(?:auth\.|rodauth\.)?((?:before|after|around)_[a-z0-9_]+)(?=\s+do\b)/
  COMMENT_LINE    = /\A\s*#/

  module_function

  # @param source [String] Ruby source text
  # @return [Hash{String => Array<Integer>}] hook name => line numbers of definitions
  def scan_source(source)
    definitions = Hash.new { |hash, key| hash[key] = [] }
    source.each_line.with_index(1) do |line, lineno|
      next if line.match?(COMMENT_LINE)

      match = line.match(HOOK_DEFINITION)
      definitions[match[1]] << lineno if match
    end
    definitions
  end

  # @param paths [Array<String>] absolute paths to Ruby files
  # @return [Hash{String => Array<String>}] hook name => ["path:line", ...]
  def scan_files(paths)
    definitions = Hash.new { |hash, key| hash[key] = [] }
    paths.sort.each do |path|
      scan_source(File.read(path)).each do |hook, lines|
        lines.each { |lineno| definitions[hook] << "#{path}:#{lineno}" }
      end
    end
    definitions
  end
end

# Static scanner for hook WRAPPERS: methods named like a Rodauth hook that are
# defined with `def` inside a module (rather than registered with
# `auth.<hook> do`), and the `prepend` sites that install such modules.
#
#   module Callback
#     def before_omniauth_callback_route   # <- wrapper, owner "...::Callback"
#       super
#     end
#   end
#   auth.auth_class_eval { prepend Auth::Config::Hooks::OmniAuthConnect::Callback }
module RodauthHookWrapperScanner
  HOOK_METHOD = /\A(?:before|after|around)_[a-z0-9_]+\z/

  Wrapper     = Struct.new(:hook, :owner, :location)
  PrependSite = Struct.new(:target, :location)

  # Collects wrappers and prepend sites with their lexical namespace.
  class Visitor < Prism::Visitor
    attr_reader :wrappers, :prepends

    def initialize(label)
      super()
      @label     = label
      @namespace = []
      @wrappers  = []
      @prepends  = []
    end

    def visit_module_node(node) = within(node) { super }
    def visit_class_node(node)  = within(node) { super }

    def visit_def_node(node)
      if node.receiver.nil? && node.name.to_s.match?(HOOK_METHOD)
        @wrappers << Wrapper.new(node.name.to_s, @namespace.join('::'), location(node))
      end
      super
    end

    def visit_call_node(node)
      if node.name == :prepend && node.receiver.nil?
        (node.arguments&.arguments || []).each do |argument|
          @prepends << PrependSite.new(argument.slice.delete_prefix('::'), location(node))
        end
      end
      super
    end

    private

    def within(node)
      @namespace.push(node.constant_path.slice.delete_prefix('::'))
      yield
    ensure
      @namespace.pop
    end

    def location(node) = "#{@label}:#{node.location.start_line}"
  end

  module_function

  # @param source [String] Ruby source text
  # @param label [String] what to call this source in locations
  # @return [Visitor] with #wrappers and #prepends populated
  def scan_source(source, label: 'source')
    visitor = Visitor.new(label)
    Prism.parse(source).value.accept(visitor)
    visitor
  end

  # @param paths [Array<String>] absolute paths to Ruby files
  # @return [Array(Array<Wrapper>, Array<PrependSite>)]
  def scan_files(paths)
    scans = paths.sort.map { |path| scan_source(File.read(path), label: path) }
    [scans.flat_map(&:wrappers), scans.flat_map(&:prepends)]
  end

  # Everything that departs from the approved set, as sentences. Empty means
  # the wrapper invariant holds.
  #
  # @param wrappers [Array<Wrapper>]
  # @param prepends [Array<PrependSite>]
  # @param approved [Hash{String => Array<String>}] hook => wrapper modules
  # @return [Array<String>]
  def violations(wrappers, prepends, approved)
    found = wrappers.group_by(&:hook).transform_values { |list| list.map(&:owner) }

    problems = wrappers.reject { |w| approved.fetch(w.hook, []).include?(w.owner) }.map do |w|
      "#{w.hook} is wrapped by #{w.owner} (#{w.location}), which is not an approved wrapper"
    end

    approved.each do |hook, owners|
      owners.each do |owner|
        defined_times = found.fetch(hook, []).count(owner)
        sites         = prepends.select { |site| site.target == owner }
        problems << "#{owner} defines #{hook} #{defined_times} times, expected once" unless defined_times == 1
        unless sites.size == 1
          problems << "#{owner} is prepended #{sites.size} times " \
                      "(#{sites.map(&:location).join(', ')}), expected once"
        end
      end
    end

    problems
  end
end

RSpec.describe 'Rodauth hook ownership (static guard)' do
  config_dir   = File.expand_path('../../config', __dir__)
  config_files = Dir.glob(File.join(config_dir, '**', '*.rb'))

  # Relative paths keep failure output readable.
  repo_relative = ->(path) { path.sub("#{File.expand_path('../../../../..', __dir__)}/", '') }

  describe 'one-owner invariant across apps/web/auth/config/**/*.rb' do
    it 'defines every before/after/around hook in exactly one place' do
      definitions = RodauthHookOwnershipScanner.scan_files(config_files)
      duplicates  = definitions.select { |_hook, locations| locations.size > 1 }

      message = +"Rodauth hooks do not chain — the last registered definition silently " \
                 "replaces the others; see apps/web/auth/config/hooks.rb and #3275.\n" \
                 "Duplicate hook definitions found:\n"
      duplicates.each do |hook, locations|
        message << "  #{hook}:\n"
        locations.each { |loc| message << "    #{repo_relative.call(loc)}\n" }
      end

      expect(duplicates).to be_empty, message
    end

    it 'finds hook definitions at all (guards against the scanner regex rotting)' do
      # If the config tree is ever restructured so the scanner matches nothing,
      # the duplicate check above would pass vacuously. Known-stable anchors:
      definitions = RodauthHookOwnershipScanner.scan_files(config_files)

      expect(definitions.keys).to include('after_login', 'before_create_account', 'around_rodauth')
      expect(definitions.size).to be >= 20 # 31 hooks as of 2026-07; loose lower bound
    end
  end

  describe 'wrapper invariant across apps/web/auth/config/**/*.rb (#4432)' do
    # hook name => the modules allowed to wrap it, outermost first. Adding a
    # module here is the explicit ownership decision the invariant asks for:
    # say in config/hooks.rb where it sits in the chain and why, and extend
    # the runtime order spec to match.
    approved_hook_wrappers = {
      'before_omniauth_callback_route' => ['Auth::Config::Hooks::OmniAuthConnect::Callback'],
    }.freeze

    wrappers, prepends = RodauthHookWrapperScanner.scan_files(config_files)

    it 'finds the known wrapper and its prepend site (the scan is not vacuous)' do
      expect(wrappers.map { |w| [w.hook, w.owner, repo_relative.call(w.location).sub(/:\d+\z/, '')] })
        .to include(
          [
            'before_omniauth_callback_route',
            'Auth::Config::Hooks::OmniAuthConnect::Callback',
            'apps/web/auth/config/hooks/omniauth_connect.rb',
          ],
        )
      expect(prepends.map(&:target)).to include('Auth::Config::Hooks::OmniAuthConnect::Callback')
    end

    it 'permits exactly the approved wrapper set, each prepended once' do
      problems = RodauthHookWrapperScanner.violations(wrappers, prepends, approved_hook_wrappers)

      expect(problems).to be_empty,
        "Prepended hook wrappers chain through `super` in ancestor order, so an " \
        "unplanned one can reorder or skip the wrappers beside it; see " \
        "apps/web/auth/config/hooks.rb.\n  " +
        problems.map { |problem| repo_relative.call(problem) }.join("\n  ")
    end

    it 'installs the Connect wrapper from hooks/omniauth.rb' do
      site = prepends.find { |s| s.target == 'Auth::Config::Hooks::OmniAuthConnect::Callback' }

      expect(repo_relative.call(site.location)).to start_with('apps/web/auth/config/hooks/omniauth.rb:')
    end

    it 'keeps omniauth_tenant.rb the sole registered owner of the wrapped hook' do
      locations = RodauthHookOwnershipScanner.scan_files(config_files)['before_omniauth_callback_route']

      expect(locations.size).to eq(1)
      expect(repo_relative.call(locations.first))
        .to start_with('apps/web/auth/config/hooks/omniauth_tenant.rb:')
    end
  end

  describe 'file-level ownership under config/hooks/' do
    # Files in hooks/ that are documented NON-owners (define zero hooks); see
    # the "Non-owners in this directory" section of config/hooks.rb.
    #   password.rb          — intentionally empty tombstone (M-2 consolidation into account.rb)
    #   billing.rb           — auth_class_eval helper methods only, hooks live in account.rb
    #   oauth.rb             — registers get_oidc_param, a keyed value method the scanner
    #                          (correctly) doesn't count as a before/after hook; its
    #                          only_json? exemption is owned by config/json_mode.rb (#3104)
    #   omniauth_connect.rb  — wraps before_omniauth_callback_route via `prepend` +
    #                          `super`, not `auth.<hook> do`. The hook is still owned
    #                          by omniauth_tenant.rb; the prepended module chains
    #                          Connect authorization ahead of it. Being hookless
    #                          does not leave it unguarded: the wrapper invariant
    #                          above pins it.
    allowed_hookless_files = %w[password.rb billing.rb oauth.rb omniauth_connect.rb]

    it 'permits only the documented non-owner files to define zero hooks' do
      hooks_files = Dir.glob(File.join(config_dir, 'hooks', '*.rb'))

      hookless = hooks_files.reject do |path|
        RodauthHookOwnershipScanner.scan_source(File.read(path)).any?
      end
      unexpected = hookless.map { |path| File.basename(path) } - allowed_hookless_files

      expect(unexpected).to be_empty,
        "Files under config/hooks/ define no hooks but are not documented non-owners " \
        "(#{allowed_hookless_files.join(', ')}): #{unexpected.join(', ')}. " \
        "Either they lost their hooks to a refactor (update config/hooks.rb and this " \
        "list) or the scanner missed a definition style."
    end
  end

  describe RodauthHookOwnershipScanner do
    describe '.scan_source' do
      it 'detects a duplicated hook with both line numbers' do
        source = <<~RUBY
          module A
            def self.configure(auth)
              auth.before_create_account do
                validate_signup
              end
            end
          end

          module B
            def self.configure(auth)
              auth.before_create_account do
                capture_plan_selection
              end
            end
          end
        RUBY

        expect(described_class.scan_source(source)['before_create_account']).to eq([3, 11])
      end

      it 'matches bare, auth.-prefixed, and rodauth.-prefixed forms with block args' do
        source = <<~RUBY
          before_login_attempt do
          end
          rodauth.after_login do |account|
          end
          auth.around_rodauth do |&blk|
          end
        RUBY

        expect(described_class.scan_source(source).keys)
          .to contain_exactly('before_login_attempt', 'after_login', 'around_rodauth')
      end

      it 'ignores comment lines and mid-line mentions in strings or docs' do
        source = <<~RUBY
          # auth.before_login_attempt do — historical example, not a definition
          #   after_login do
          log('after_login do things happen here')
          message = "before_create_account do"
        RUBY

        expect(described_class.scan_source(source)).to be_empty
      end

      it 'ignores before_/after_ method calls without a do block' do
        source = <<~RUBY
          auth.before_rodauth
          after_login_redirect '/dashboard'
          auth.before_view_recovery_codes_route? ? a : b
        RUBY

        expect(described_class.scan_source(source)).to be_empty
      end
    end
  end

  describe RodauthHookWrapperScanner do
    approved = { 'before_omniauth_callback_route' => ['Hooks::Connect::Callback'] }.freeze

    approved_source = <<~RUBY
      module Hooks
        module Connect
          module Callback
            def before_omniauth_callback_route
              super
            end

            private

            def helper_that_is_not_a_hook; end
          end
        end

        def self.configure(auth)
          auth.auth_class_eval { prepend Hooks::Connect::Callback }
        end
      end
    RUBY

    second_wrapper_source = <<~RUBY
      module Hooks::Audit
        module Callback
          def before_omniauth_callback_route
            record_callback
            super
          end
        end

        def self.configure(auth)
          auth.auth_class_eval { prepend Hooks::Audit::Callback }
        end
      end
    RUBY

    def violations_for(approved, *sources)
      scans = sources.map { |source| described_class.scan_source(source) }
      described_class.violations(scans.flat_map(&:wrappers), scans.flat_map(&:prepends), approved)
    end

    it 'names a wrapper by its full lexical namespace and records the prepend site' do
      scan = described_class.scan_source(approved_source, label: 'fixture.rb')

      expect(scan.wrappers.map(&:to_a)).to eq(
        [['before_omniauth_callback_route', 'Hooks::Connect::Callback', 'fixture.rb:4']],
      )
      expect(scan.prepends.map(&:to_a)).to eq([['Hooks::Connect::Callback', 'fixture.rb:15']])
    end

    it 'passes the approved wrapper alone' do
      expect(violations_for(approved, approved_source)).to be_empty
    end

    it 'fails when a second module is prepended around the same hook' do
      expect(violations_for(approved, approved_source, second_wrapper_source)).to contain_exactly(
        a_string_matching(/before_omniauth_callback_route is wrapped by Hooks::Audit::Callback .*not an approved/),
      )
    end

    it 'fails for a second wrapper even when nothing prepends it yet' do
      unprepended = second_wrapper_source.sub(/^\s*auth\.auth_class_eval.*\n/, '')

      expect(violations_for(approved, approved_source, unprepended).size).to eq(1)
    end

    it 'fails when the approved wrapper is prepended twice, or not at all' do
      twice = approved_source.sub(/^(\s*auth\.auth_class_eval.*\n)/, '\\1\\1')
      never = approved_source.sub(/^\s*auth\.auth_class_eval.*\n/, '')

      expect(violations_for(approved, twice)).to contain_exactly(a_string_matching(/prepended 2 times/))
      expect(violations_for(approved, never)).to contain_exactly(a_string_matching(/prepended 0 times/))
    end

    it 'fails when the approved wrapper no longer defines the hook' do
      renamed = approved_source.sub('def before_omniauth_callback_route', 'def before_something_else_entirely')

      expect(violations_for(approved, renamed)).to include(
        a_string_matching(/Callback defines before_omniauth_callback_route 0 times/),
        a_string_matching(/before_something_else_entirely is wrapped by/),
      )
    end

    it 'ignores singleton methods and hook-like names behind an explicit receiver' do
      source = <<~RUBY
        module Hooks
          def self.before_configure; end
          auth.before_login { nil }
          other.prepend Something
        end
      RUBY
      scan = described_class.scan_source(source)

      expect(scan.wrappers).to be_empty
      expect(scan.prepends).to be_empty
    end
  end
end
