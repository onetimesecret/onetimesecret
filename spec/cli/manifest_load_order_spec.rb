# spec/cli/manifest_load_order_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'open3'

# Every command file must require its own dependencies rather than leaning on
# the order of the require_relative list in lib/onetime/cli.rb. A file that
# `include`s a shared module it never required loads fine today only because
# the manifest happens to require that module first; loaded directly, or after
# any reordering of that manifest, it raises NameError at class-definition time.
#
# The check has to run out-of-process twice over: once because
# spec/cli/cli_spec_helper.rb has already required 'onetime/cli' (a repeat
# require is a no-op), and once per command file because loading file A can
# satisfy file B's missing dependency. Merely reversing the manifest is not
# enough for that second reason — org/create_command.rb legitimately requires
# customers/shared, which would mask the gap in a customers command.
#
# So: boot one Ruby, evaluate only the base classes at the head of
# lib/onetime/cli.rb, then fork a child per manifest entry. Each child requires
# exactly one file against that bare base and reports what it raised. The
# expensive `require 'onetime'` is paid once; the whole sweep costs ~2s.
RSpec.describe 'CLI command file self-sufficiency' do
  root = File.expand_path('../..', __dir__)

  # Evaluates this repo's own lib/onetime/cli.rb header — the file under test,
  # not external input.
  harness = <<~RUBY
    cli_rb = File.join(Dir.pwd, 'lib/onetime/cli.rb')
    head, manifest = File.read(cli_rb).split('# Load core CLI commands', 2)
    eval(head, TOPLEVEL_BINDING, cli_rb, 1)

    paths = manifest.scan(/^require_relative '([^']+)'/).flatten
    abort 'manifest parsed as empty' if paths.empty?

    failed = paths.reject do |rel|
      reader, writer = IO.pipe
      pid = fork do
        reader.close
        begin
          require File.expand_path("lib/onetime/\#{rel}", Dir.pwd)
        rescue ScriptError, StandardError => e
          writer.write("\#{e.class}: \#{e.message.lines.first.strip}")
        end
        writer.close
        exit!(0)
      end
      writer.close
      message = reader.read
      reader.close
      Process.wait(pid)
      message.empty? || (STDERR.puts("  lib/onetime/\#{rel} -- \#{message}") && false)
    end

    puts paths.size
    exit(failed.empty? ? 0 : 1)
  RUBY

  it 'loads every command file without help from the rest of the manifest' do
    skip 'requires fork' unless Process.respond_to?(:fork)

    stdout, stderr, status = Open3.capture3(
      { 'RACK_ENV' => 'test' }, RbConfig.ruby, '-Ilib', '-e', harness, chdir: root
    )

    expect(status).to be_success,
                      "Command files that do not require their own dependencies " \
                      "(they load today only because lib/onetime/cli.rb happens to " \
                      "require those dependencies first):\n#{stderr}"
    expect(stdout.to_i).to be > 50
  end
end
