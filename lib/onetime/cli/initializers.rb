# lib/onetime/cli/initializers.rb

# Standalone command that doesn't inherit from Onetime::CLI
# to avoid the automatic boot process
class InitializersCommand < Drydock::Command

  def initializers
    # Load only what we need without booting
    require_relative '../initializers'

    puts "Boot-time Initializers (TSort execution order):"
    puts "=" * 50

    begin
      execution_info = Onetime::Initializers::Registry.execution_order

      if execution_info.first[:name] == "ERROR"
        puts "❌ #{execution_info.first[:dependencies].first}"
        return
      end

      execution_info.each do |info|
        order_str = sprintf("%2d.", info[:order])
        name = info[:name].split('::').last # Get just the module name

        if global.verbose
          puts "#{order_str} #{name}"
          puts "    Module: #{info[:name]}"
          if option.dependencies && !info[:dependencies].empty?
            puts "    Dependencies: #{info[:dependencies].map { |d| d.split('::').last }.join(', ')}"
          end
          puts
        elsif option.dependencies
          deps_str = info[:dependencies].empty? ?
            "(no dependencies)" :
            "→ #{info[:dependencies].map { |d| d.split('::').last }.join(', ')}"
          puts "#{order_str} #{name.ljust(20)} #{deps_str}"
        else
          puts "#{order_str} #{name}"
        end
      end

      puts
      puts "Total: #{execution_info.length} initializers"

    rescue => e
      puts "❌ Error loading initializers: #{e.message}"
      puts "   This command requires the initializers to be loadable"
      puts "   but does not require a full application boot."
    end
  end
end
