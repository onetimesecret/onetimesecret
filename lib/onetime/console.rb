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

# Create a custom workspace with your loaded environment
# workspace = IRB::WorkSpace.new(binding)
# irb = IRB::Irb.new(workspace)

# Start the session
# IRB.conf[:MAIN_CONTEXT] = irb.context
# irb.eval_input

# Customize the prompt
if defined?(IRB)
  require 'irb/completion'
  IRB.conf[:PROMPT][:ONETIME] = {
    PROMPT_I: 'ONETIME> ',    # The main prompt
    PROMPT_S: '%l ',     # The prompt for continuing strings
    PROMPT_C: '↳  ',    # The prompt for continuing statements
    PROMPT_N: '⇢  ',    # The prompt for nested statements
    RETURN: "⮑  %s\n",  # The format for return values
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

# IRB.conf[:RC] indicates whether an RC file (.irbrc) was
# loaded during IRB initialization
has_settings = !IRB.conf[:RC].nil?
has_history  = IRB.conf[:SAVE_HISTORY] > 0
use_pager    = IRB.conf[:USE_PAGER]

content_width = 59
lines         = [
  ['SETTINGS', has_settings ? 'ACTIVE' : 'DEFAULT'],
  ['HISTORY', has_history ? 'ENABLED' : 'DISABLED'],
  ['PAGER', use_pager ? 'ENABLED' : 'DISABLED'],
]

banner = []
banner << <<~BANNER
  ╔═══════════════════════════════════════════════════════════════╗
  ║                                                               ║
  ║    ██████  ███    ██ ███████ ████████ ██ ███    ███ ███████   ║
  ║   ██    ██ ████   ██ ██         ██    ██ ████  ████ ██        ║
  ║   ██    ██ ██ ██  ██ █████      ██    ██ ██ ████ ██ █████     ║
  ║   ██    ██ ██  ██ ██ ██         ██    ██ ██  ██  ██ ██        ║
  ║    ██████  ██   ████ ███████    ██    ██ ██      ██ ███████   ║
  ║                                                               ║
  ╚═══════════════════════════════════════════════════════════════╝

BANNER

banner << "┌#{'─' * (content_width + 2)}┐"
lines.each do |label, value|
  banner << format("│ %-#{content_width - 8}s%8s │", "#{label}:", value)
end
banner << "└#{'─' * (content_width + 2)}┘"

banner << <<~BANNER

  SYSTEM STATUS: #{OT.ready? ? 'READY         ' : 'NOT BOOTED     '}

BANNER

puts banner

# Boot up
unless ENV['DELAY_BOOT'].to_s.match?(/^(true|1)$/i)
  Onetime.safe_boot! :cli

  puts <<~BANNER

    SYSTEM STATUS: #{OT.ready? ? 'READY         ' : 'NOT BOOTED     '}
  BANNER

end

puts <<~BANNER

  USE CTRL-D TO EXIT
  AWAITING OPERATOR INSTRUCTIONS...

BANNER

using IndifferentHashAccess
