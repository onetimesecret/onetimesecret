# frozen_string_literal: true

require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

desc "Run tryouts"
task :tryouts do
  sh "bundle exec try tryouts/**/*_try.rb"
end

desc "Run all tests"
task test: [:spec, :tryouts]

task default: :test
