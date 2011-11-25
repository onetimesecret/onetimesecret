
# ----------------------------------------------------------- ROUTINES --------
# The routines block describes the repeatable processes for each machine group.
# To run a routine, specify its name on the command-line: rudy startup
routines do

  env :dev do

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
        git 'fetch', '--tags', :origin
        msg = argv.first
        $build = ruby './bin/ot', 'register-build', msg
        $build_tag = "rel-#{$build}"
        msg_ci = "RUDY PRESENTS: #{$build}"
        msg_ci << " (#{msg})" if msg
        git 'commit', :m, msg_ci, 'BUILD.yml'
        git 'tag', $build_tag
        git 'push', :origin, '--tags'
        git 'push', :origin
      end
    end

    restart_thin do
      before :stop_thin
      after :start_thin
    end

  end
  
end
