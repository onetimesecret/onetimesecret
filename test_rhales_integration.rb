#!/usr/bin/env ruby

require 'onetime'

# Simple test script to verify Rhales integration with manifold
require_relative 'apps/api/v2/controllers'
require_relative 'apps/api/v2/models'
require_relative 'apps/web/manifold/controllers'
require_relative 'apps/web/manifold/views'

puts 'Testing Rhales integration with Manifold...'

# Test 1: Verify UIContext can be created
puts "\n1. Testing UIContext creation..."
begin
  context = Onetime::Services::UIContext.minimal(props: { test: 'value' })
  puts '✓ UIContext created successfully'
  puts "  - Context has onetime_window: #{!context.get('onetime_window').nil?}"
rescue StandardError => ex
  puts "✗ UIContext creation failed: #{ex.message}"
end

# Test 2: Test VuePoint view creation
puts "\n2. Testing VuePoint view creation..."
begin
  view = Manifold::Views::VuePoint.new(nil, nil, nil, 'en', props: { test: 'value' })
  puts '✓ VuePoint view created successfully'
  puts "  - View has context: #{!view.instance_variable_get(:@rsfc_context).nil?}"
rescue StandardError => ex
  puts "✗ VuePoint view creation failed: #{ex.message}"
end

# Test 3: Test SPA JSON rendering
puts "\n3. Testing SPA JSON rendering..."
begin
  json_output = Manifold::Views::VuePoint.render_spa(nil, nil, nil, 'en')
  parsed      = JSON.parse(json_output)
  puts '✓ SPA JSON rendered successfully'
  puts "  - JSON contains locale: #{parsed.key?('locale')}"
  puts "  - JSON contains authenticated: #{parsed.key?('authenticated')}"
rescue StandardError => ex
  puts "✗ SPA JSON rendering failed: #{ex.message}"
end

# Test 4: Test ExportWindow view
puts "\n4. Testing ExportWindow view..."
begin
  export_view = Manifold::Views::ExportWindow.new(nil, nil, nil, 'en')
  json_output = export_view.render
  parsed      = JSON.parse(json_output)
  puts '✓ ExportWindow rendered successfully'
  puts "  - Output is valid JSON with #{parsed.keys.length} keys"
rescue StandardError => ex
  puts "✗ ExportWindow rendering failed: #{ex.message}"
end

puts "\nRhales integration test complete."
