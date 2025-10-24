# Rakefile
#
# This file loads Rhales rake tasks for schema generation and validation.
#

require 'bundler/setup'

# Load Rhales rake tasks
require 'rhales'
rhales_tasks = File.expand_path('../rhales/lib/tasks/rhales_schema.rake', __dir__)
if File.exist?(rhales_tasks)
  load rhales_tasks
else
  warn "Warning: Rhales tasks not found at #{rhales_tasks}"
  warn "Ensure rhales gem is installed and the path is correct."
end
