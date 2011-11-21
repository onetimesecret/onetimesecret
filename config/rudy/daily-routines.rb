
# ----------------------------------------------------------- ROUTINES --------
# The routines block describes the repeatable processes for each machine group.
# To run a routine, specify its name on the command-line: rudy startup
routines do

  env :dev do

    #def to_file(filename, mode, chmod=0744)
    #  mode = (mode == :append) ? 'a' : 'w'
    #  f = File.open(filename,mode)
    #  f.puts self
    #  f.close
    #  raise "Provided chmod is not a Fixnum (#{chmod})" unless chmod.is_a?(Fixnum)
    #  File.chmod(chmod, filename)
    #end

    #def increment!(msg=nil)
    #  @info[:BUILD] = @info[:BUILD].to_s.succ!
    #  @info[:STAMP] = Time.now.utc.to_i
    #  @info[:OWNER] = 'ots' 
    #  @info[:STORY] = msg || '[no message]'
    #  @info.to_yaml.to_file('BUILD.yml', 'w')
    #  @info
    #end

    #def register_build(msg=nil)
    #  begin
    #    increment! msg
    #    puts load_config
    #  rescue => ex
    #    puts ex.message
    #    exit 1
    #  end
    #end

    load_config do
      local do
        require 'yaml'
        @info ||= YAML.load_file('BUILD.yml')
        puts @info
        increment! "Yeehaw"
      end
    end

    quick_deploy do
      before :release
      after :deploy
    end

    release do
      local do |argv|
        #git 'fetch', '--tags', :origin
        msg = argv.first
        require 'yaml'
        @info ||= YAML.load_file('BUILD.yml')
        @info[:BUILD] = @info[:BUILD].to_s.succ!
        @info[:STAMP] = Time.now.utc.to_i
        @info[:OWNER] = 'ots' 
        @info[:STORY] = msg || '[no message]'
        f = File.open('BUILD.yml','w')
        f.puts @info.to_yaml 
        f.close
        File.chmod(0744, 'BUILD.yml')
        $build = @info
        $build_tag = "rel-#{$build}"
        msg_ci = "RUDY PRESENTS: #{$build}"
        msg_ci << " (#{msg})" if msg
        #git 'commit', :m, msg_ci, 'BUILD.yml'
        #git 'tag', $build_tag
        #git 'push', :origin, '--tags'
        #git 'push', :origin
      end
    end

    restart_thin do
      before :stop_thin
      after :start_thin
    end

  end
  
end
