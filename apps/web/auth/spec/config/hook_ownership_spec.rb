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
# HOW IT TESTS:
#   Pure static scan — File.read + line-anchored regex. It deliberately does
#   NOT require apps/web/auth/config.rb or boot anything (that file's header
#   forbids test files from requiring it). This is an intentional exception
#   to the "no string matching on config files" rule used by the runtime
#   feature specs in this directory: the property under test (textual
#   duplicate definitions) is only visible statically, because at runtime the
#   duplicate has already been silently replaced.
#
# =============================================================================

require_relative '../spec_helper'

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

  describe 'file-level ownership under config/hooks/' do
    # Files in hooks/ that are documented NON-owners (define zero hooks); see
    # the "Non-owners in this directory" section of config/hooks.rb.
    #   password.rb — intentionally empty tombstone (M-2 consolidation into account.rb)
    #   billing.rb  — auth_class_eval helper methods only, hooks live in account.rb
    allowed_hookless_files = %w[password.rb billing.rb]

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
end
