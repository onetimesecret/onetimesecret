# lib/onetime/console.rb

ENV['RACK_ENV']   ||= 'production'
ENV['ONETIME_HOME'] = File.expand_path(File.join(__dir__, '..', '..')).freeze
app_root            = ENV.fetch('ONETIME_HOME')

Warning[:deprecated] = %w[development dev].include?(ENV.fetch('RACK_ENV', ''))

# Directory Constants
unless defined?(PUBLIC_DIR)
  PUBLIC_DIR = File.join(app_root, '/public/web').freeze
  APP_DIR    = File.join(app_root, '/apps').freeze
end

# Load Paths
$LOAD_PATH.unshift(File.join(APP_DIR, 'api'))
$LOAD_PATH.unshift(File.join(APP_DIR, 'web'))

# Only load what's necessary for successful interactive startup
require_relative '../onetime'
require_relative '../onetime/models'
require_relative '../onetime/refinements/indifferent_hash_access'

# # Create a custom workspace with your loaded environment
# workspace = IRB::WorkSpace.new(binding)
# irb = IRB::Irb.new(workspace)

# # Start the session
# IRB.conf[:MAIN_CONTEXT] = irb.context
# irb.eval_input

# Customize the prompt
if defined?(IRB)
  require 'irb/completion'
  IRB.conf[:PROMPT][:ONETIME] = {
    PROMPT_I: 'onetime> ',    # The main prompt
    PROMPT_S: '%l ',   # The prompt for continuing strings
    PROMPT_C: '↳  ',    # The prompt for continuing statements
    PROMPT_N: '⇢  ',    # The prompt for nested statements
    RETURN: "⮑  %s\n",         # The format for return values
  }
  IRB.conf[:IRB_RC]           = proc do |context|
    context.workspace.binding.eval('using IndifferentHashAccess')
  end
  # Set the global prompt mode to :ONETIME
  IRB.conf[:PROMPT_MODE]      = :ONETIME

  # Try to set it for the current context, if it exists
  if defined?(IRB.CurrentContext) && IRB.CurrentContext
    IRB.CurrentContext.prompt_mode = :ONETIME
  end

  # Additional IRB settings
  IRB.conf[:AUTO_INDENT]      = true
  IRB.conf[:BACK_TRACE_LIMIT] = 25
  IRB.conf[:ECHO]             = true
  IRB.conf[:HISTORY_FILE]     = nil if IRB.conf[:HISTORY_FILE].nil?
  IRB.conf[:IGNORE_EOF]       = false
  IRB.conf[:SAVE_HISTORY]     = 0 if IRB.conf[:SAVE_HISTORY].nil?
  IRB.conf[:USE_PAGER]        = true if IRB.conf[:USE_PAGER].nil?
end

Onetime.safe_boot! :cli

# IRB.conf[:RC] indicates whether an RC file (.irbrc) was
# loaded during IRB initialization
has_settings = !IRB.conf[:RC].nil?
has_history  = IRB.conf[:SAVE_HISTORY] > 0
use_pager    = IRB.conf[:USE_PAGER]
puts
puts '╔═══════════════════════════════════════════════════════════════╗'
puts '║                                                               ║'
puts '║    ██████  ███    ██ ███████ ████████ ██ ███    ███ ███████   ║'
puts '║   ██    ██ ████   ██ ██         ██    ██ ████  ████ ██        ║'
puts '║   ██    ██ ██ ██  ██ █████      ██    ██ ██ ████ ██ █████     ║'
puts '║   ██    ██ ██  ██ ██ ██         ██    ██ ██  ██  ██ ██        ║'
puts '║    ██████  ██   ████ ███████    ██    ██ ██      ██ ███████   ║'
puts '║                                                               ║'
puts '╚═══════════════════════════════════════════════════════════════╝'
puts
puts '  Console Status:'
puts "    → Settings: #{has_settings ? '✅ Applied (~/.irbrc)' : '❌ Default'}"
puts "    → History:  #{has_history ? '✅ Enabled' : '❌ Disabled'}"
puts "    → Pager:    #{use_pager ? '✅ Enabled' : '❌ Disabled'}"
puts
puts "  Use 'ctrl-d' to quit."
puts

using IndifferentHashAccess
