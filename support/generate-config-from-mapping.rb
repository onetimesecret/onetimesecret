#!/usr/bin/env ruby

require 'yaml'
require 'fileutils'

class ConfigMapper
  def initialize(project_root = nil)
    @project_root = project_root || File.expand_path('..', __dir__)
    @config_example = File.join(@project_root, 'etc', 'config.example.converted.yaml')
    @config_mapping = File.join(@project_root, 'etc', 'config.mapping.yaml')
    @static_output = File.join(@project_root, 'etc', 'config.static.yaml')
    @dynamic_output = File.join(@project_root, 'etc', 'config.dynamic.yaml')
  end

  def run
    validate_files
    mappings = load_mappings

    puts "Generating configuration files from mappings..."

    generate_static_config(mappings['static'])
    generate_dynamic_config(mappings['dynamic'])

    puts "Configuration generation completed!"
    puts "Static config: #{@static_output}"
    puts "Dynamic config: #{@dynamic_output}"

    show_structure
  end

  private

  def validate_files
    unless File.exist?(@config_example)
      raise "Config example file not found: #{@config_example}"
    end

    unless File.exist?(@config_mapping)
      raise "Config mapping file not found: #{@config_mapping}"
    end
  end

  def load_mappings
    YAML.load_file(@config_mapping)['mappings']
  end

  def generate_static_config(static_mappings)
    puts "Creating static configuration..."

    # Initialize empty config
    system("yq eval 'del(.[])' <<< '{}' > '#{@static_output}'")

    static_mappings.each do |mapping|
      from_path = mapping['from']
      to_path = mapping['to']

      generate_yq_command(@static_output, from_path, to_path)
    end
  end

  def generate_dynamic_config(dynamic_mappings)
    puts "Creating dynamic configuration..."

    # Initialize empty config
    system("yq eval 'del(.[])' <<< '{}' > '#{@dynamic_output}'")

    dynamic_mappings.each do |mapping|
      from_path = mapping['from']
      to_path = mapping['to']

      generate_yq_command(@dynamic_output, from_path, to_path)
    end
  end

  def generate_yq_command(output_file, from_path, to_path)
    # Handle wildcard mappings (ending with .)
    if from_path.end_with?('.')
      from_path = from_path.chomp('.')
    end

    # Convert dot notation to yq path notation
    from_yq = convert_to_yq_path(from_path)
    to_yq = convert_to_yq_path(to_path)

    # Generate and execute yq command
    cmd = "yq eval '.#{to_yq} = load(\"#{@config_example}\").#{from_yq}' -i '#{output_file}'"

    puts "  Mapping: #{from_path} -> #{to_path}"

    # Execute the command
    success = system(cmd)
    unless success
      puts "    Warning: Failed to map #{from_path} -> #{to_path}"
    end
  end

  def convert_to_yq_path(path)
    # yq uses dot notation, but we need to handle array indices and special characters
    # For now, keeping it simple since the paths in the mapping are already dot notation
    path
  end

  def show_structure
    if File.exist?(@static_output)
      puts "\nStatic config structure:"
      system("yq eval 'keys' '#{@static_output}'")
    end

    if File.exist?(@dynamic_output)
      puts "\nDynamic config structure:"
      system("yq eval 'keys' '#{@dynamic_output}'")
    end
  end
end

# Script execution
if __FILE__ == $0
  begin
    mapper = ConfigMapper.new
    mapper.run
  rescue => e
    puts "Error: #{e.message}"
    exit 1
  end
end
