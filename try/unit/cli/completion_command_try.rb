# try/unit/cli/completion_command_try.rb
#
# frozen_string_literal: true

# Unit tests for `ots completion [bash|zsh|fish]`.
# Verifies the registry-walk generator emits a static completion script for
# each supported shell, covering the full command tree (including deep,
# auto-discovered billing paths), and that unsupported shells fail loudly.
#
# Run: bundle exec try try/unit/cli/completion_command_try.rb

require_relative '../../support/test_helpers'
require 'open3'
require 'stringio'
require 'tempfile'
require 'onetime/cli'

cmd   = Onetime::CLI::CompletionCommand.new
paths = cmd.send(:command_paths)
bash  = cmd.send(:bash_script)
zsh   = cmd.send(:zsh_script)
fish  = cmd.send(:fish_script)

# Invoke `call` and return the exit status (0 when it does not exit).
# Silences stdout/stderr so the script bodies and warnings do not flood the
# tryouts output.
def call_status(**)
  orig_out = $stdout
  orig_err = $stderr
  $stdout  = StringIO.new
  $stderr  = StringIO.new
  Onetime::CLI::CompletionCommand.new.call(**)
  0
rescue SystemExit => ex
  ex.status
ensure
  $stdout = orig_out
  $stderr = orig_err
end

# Source the generated bash script under a hostile IFS and return the
# COMPREPLY candidates for the given COMP_WORDS (cursor on the last word).
def bash_complete(script, words)
  Tempfile.create(['ots', '.bash']) do |f|
    f.write(script)
    f.flush
    quoted = words.map { |w| "'#{w}'" }.join(' ')
    cmd    = "IFS=':'; source #{f.path}; COMP_WORDS=(#{quoted}); " \
             "COMP_CWORD=#{words.size - 1}; _ots_complete; " \
             "printf '%s\\n' \"${COMPREPLY[@]}\""
    out,   = Open3.capture2('bash', '-c', cmd)
    out.split("\n")
  end
end

# -------------------------------------------------------------------
# command_paths: registry walk
# -------------------------------------------------------------------

## Returns a non-trivial list of command paths
paths.size >= 10
#=> true

## Sorted and de-duplicated
paths == paths.sort.uniq
#=> true

## Includes a top-level command
paths.include?('completion')
#=> true

## Includes a nested command
paths.include?('session list')
#=> true

## Includes a deep, auto-discovered billing command
paths.include?('billing catalog drift')
#=> true

# -------------------------------------------------------------------
# bash_script
# -------------------------------------------------------------------

## Defines the completer function
bash.include?('_ots_complete()')
#=> true

## Registers completion for ots and bin/ots
bash.include?('complete -F _ots_complete ots bin/ots ./bin/ots')
#=> true

## Every registry path appears in the baked command list
paths.all? { |p| bash.include?(p) }
#=> true

## Completes nested subcommands even when the caller's IFS is customized
bash_complete(bash, ['ots', 'billing', 'catalog', '']).include?('drift')
#=> true

## Completes top-level commands by prefix under a customized IFS
bash_complete(bash, %w[ots se]).sort
#=> ['server', 'session']

# -------------------------------------------------------------------
# zsh_script
# -------------------------------------------------------------------

## Carries the #compdef tag
zsh.start_with?('#compdef ots')
#=> true

## Registers the completer via compdef (guarded)
zsh.include?('compdef _ots_complete ots bin/ots')
#=> true

## Prefix-strip is emitted literally, not swallowed by Ruby interpolation
zsh.include?('rest=${line#$prefix }')
#=> true

## Bakes a deep command path into the static tree
zsh.include?('billing catalog drift')
#=> true

# -------------------------------------------------------------------
# fish_script
# -------------------------------------------------------------------

## Defines the helper function
fish.include?('function __ots_complete')
#=> true

## Registers completion for ots
fish.include?("complete -c ots -f -a '(__ots_complete)'")
#=> true

## Bakes command paths as a quoted list
fish.include?("'billing catalog drift'")
#=> true

# -------------------------------------------------------------------
# call: dispatch and error handling
# -------------------------------------------------------------------

## Default shell (bash) succeeds
call_status
#=> 0

## zsh is supported
call_status(shell: 'zsh')
#=> 0

## fish is supported
call_status(shell: 'fish')
#=> 0

## POSIX sh is rejected (no completion facility)
call_status(shell: 'sh')
#=> 1

## An unknown shell is rejected
call_status(shell: 'tcsh')
#=> 1
