# lib/tasks/rhales.rake
#
# frozen_string_literal: true

# bundle exec rake rhales:schema:generate

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
