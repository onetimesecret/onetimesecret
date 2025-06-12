# lib/onetime/cli/initializers.rb

# Standalone command that doesn't inherit from Onetime::CLI
# to avoid the automatic boot process
module Onetime
  class InitializersCommand < Drydock::Command
    def initializers
      # Load only what we need without booting
      require_relative '../initializers'

      puts 'Boot-time Initializers (TSort execution order):'
      puts '=' * 50

      begin
        execution_info = Onetime::Initializers::Registry.execution_order

        return handle_error(execution_info) if execution_info.first[:name] == 'ERROR'

        if option.dependencies
          display_with_dependencies(execution_info)
        else
          display_simple_list(execution_info)
        end
      rescue StandardError => ex
        puts "❌ Error loading initializers: #{ex.message}"
        puts '   This command requires the initializers to be loadable'
        puts '   but does not require a full application boot.'
      end
    end

    private

    def handle_error(execution_info)
      puts "❌ #{execution_info.first[:dependencies].first}"
    end

    def display_with_dependencies(execution_info)
      execution_info.each do |info|
        order_str = format('%2d.', info[:order])
        name      = info[:name].split('::').last

        if verbose_mode?
          display_verbose_with_dependencies(order_str, name, info)
        else
          display_compact_with_dependencies(order_str, name, info)
        end
      end

      display_dependencies_footer(execution_info.length)
    end

    def display_simple_list(execution_info)
      execution_info.each do |info|
        order_str = format('%2d.', info[:order])
        name      = info[:name].split('::').last

        if verbose_mode?
          display_verbose_simple(order_str, name, info)
        else
          puts "#{order_str} #{name}"
        end
      end

      display_simple_footer(execution_info.length)
    end

    def display_verbose_with_dependencies(order_str, name, info)
      puts "#{order_str} #{name}"
      puts "    Module: #{info[:name]}"
      if !info[:dependencies].empty?
        puts "    Dependencies: #{info[:dependencies].map { |d| d.split('::').last }.join(', ')}"
      end
      puts
    end

    def display_compact_with_dependencies(order_str, name, info)
      deps_str = info[:dependencies].empty? ?
        '(no dependencies)' :
        "→ #{info[:dependencies].map { |d| d.split('::').last }.join(', ')}"
      puts "#{order_str} #{name.ljust(20)} #{deps_str}"
    end

    def display_verbose_simple(order_str, name, info)
      puts "#{order_str} #{name}"
      puts "    Module: #{info[:name]}"
      puts
    end

    def display_dependencies_footer(count)
      puts
      puts "Total: #{count} initializers"
      puts
      puts 'Legend:'
      puts '  → Dependencies (must run before this initializer)'
      puts '  Use --verbose for full module names'
    end

    def display_simple_footer(count)
      puts
      puts "Total: #{count} initializers"
    end

    def verbose_mode?
      global.verbose && global.verbose > 0
    end
  end
end
