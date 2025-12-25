# frozen_string_literal: true

# lib/tasks/rhales.rake

# Load Rhales rake tasks

require 'rhales'

begin
  spec         = Gem::Specification.find_by_name('rhales')
  rhales_tasks = "#{spec.gem_dir}/lib/tasks/rhales_schema.rake"
  load rhales_tasks
rescue Gem::LoadError
  warn 'Warning: Rhales gem not found'
rescue LoadError => ex
  warn "Warning: Rhales tasks not found: #{ex.message}"
end
