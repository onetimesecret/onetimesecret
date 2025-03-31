# lib/onetime/console.rb

ENV['RACK_ENV'] ||= 'production'
ENV['ONETIME_HOME'] = File.expand_path(File.join(__dir__, '..', '..')).freeze
app_root = ENV['ONETIME_HOME']

# Directory Constants
unless defined?(PUBLIC_DIR)
  PUBLIC_DIR = File.join(app_root, '/public/web').freeze
  APP_DIR = File.join(app_root, '/apps').freeze
end

# Load Paths
$LOAD_PATH.unshift(File.join(APP_DIR, 'api'))
$LOAD_PATH.unshift(File.join(APP_DIR, 'web'))

require_relative '../onetime'

Onetime.info 'Calling Onetime.boot!...'
Onetime.boot! :cli

# Customize the prompt
if defined?(IRB)
  require "irb/completion"
  IRB.conf[:PROMPT][:ONETIME] = {
    PROMPT_I: "onetime> ",    # The main prompt
    PROMPT_S: "%l ",   # The prompt for continuing strings
    PROMPT_C: "↳  ",    # The prompt for continuing statements
    PROMPT_N: "⇢  ",    # The prompt for nested statements
    RETURN: "⮑  %s\n",         # The format for return values
  }

  # Set the global prompt mode to :ONETIME
  IRB.conf[:PROMPT_MODE] = :ONETIME

  # Try to set it for the current context, if it exists
  if defined?(IRB.CurrentContext) && IRB.CurrentContext
    IRB.CurrentContext.prompt_mode = :ONETIME
  end

  # Additional IRB settings
  IRB.conf[:AUTO_INDENT] = true
  IRB.conf[:ECHO] = true
  IRB.conf[:BACK_TRACE_LIMIT] = 25
  IRB.conf[:SAVE_HISTORY] = 0
  IRB.conf[:HISTORY_FILE] = nil
  IRB.conf[:IGNORE_EOF] = false
  IRB.conf[:USE_PAGER] = true

  puts
  puts "Onetime console loaded (additional settings applied: #{IRB.conf[:RC]})."
  puts "History not saved. Use 'ctrl-d' to quit."
  puts
end
