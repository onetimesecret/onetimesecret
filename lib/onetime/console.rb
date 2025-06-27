# lib/onetime/console.rb

##
# Onetime Console
#
# This file contains the console setup and is run standalone (i.e. executed
# directly by IRB).
#

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
    context.workspace.binding.eval('using Onetime::IndifferentHashAccess')
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
# Configuration and Constants
CONTENT_WIDTH = 59
SPACING       = 8

# System status checks
def system_status
  {
    settings: IRB.conf[:RC].nil? ? 'DEFAULT' : 'ACTIVE',
    history: IRB.conf[:SAVE_HISTORY] > 0 ? 'ENABLED' : 'DISABLED',
    pager: IRB.conf[:USE_PAGER] ? 'ENABLED' : 'DISABLED',
  }
end

def boot_status
  OT.ready? ? 'READY' : 'NOT BOOTED'
end

# Banner generation
def ascii_header
  <<~HEADER
    ╔═══════════════════════════════════════════════════════════════╗
    ║                                                               ║
    ║    ██████  ███    ██ ███████ ████████ ██ ███    ███ ███████   ║
    ║   ██    ██ ████   ██ ██         ██    ██ ████  ████ ██        ║
    ║   ██    ██ ██ ██  ██ █████      ██    ██ ██ ████ ██ █████     ║
    ║   ██    ██ ██  ██ ██ ██         ██    ██ ██  ██  ██ ██        ║
    ║    ██████  ██   ████ ███████    ██    ██ ██      ██ ███████   ║
    ║                                                               ║
    ╚═══════════════════════════════════════════════════════════════╝
  HEADER
end

def status_table(status_data)
  table = ["┌#{'─' * (CONTENT_WIDTH + 2)}┐"]

  status_data.each do |label, value|
    label_width = CONTENT_WIDTH - SPACING
    table << (format("│ %-#{label_width}s%#{SPACING}s │", "#{label.upcase}:", value))
  end

  table << "└#{'─' * (CONTENT_WIDTH + 2)}┘"
  table.join("\n")
end

def display_system_status
  puts "\n  SYSTEM STATUS: #{boot_status.ljust(15)}\n"
end

# Main execution
puts ascii_header
puts status_table(system_status)
display_system_status

# Boot sequence
unless ENV['DELAY_BOOT'].to_s.match?(/^(true|1)$/i)
  Onetime.safe_boot! :cli
  display_system_status
end

puts <<~INSTRUCTIONS

  USE CTRL-D TO EXIT

INSTRUCTIONS

using Onetime::IndifferentHashAccess
