
# ----------------------------------------------------------- ROUTINES --------
# The routines block describes the repeatable processes for each machine group.
# To run a routine, specify its name on the command-line: rudy startup
routines do

  role :fe do
    
    quick_deploy do
      before :release
      after :deploy
    end
    
    deploy do 
      before :promote
      after :restart_thin
    end
    
    upgrade do
      before :promote
      after :bundle_install
    end
    
    promote do
      local do
        # TODO: can do a fetch without a release using: 
        # git describe --tags HEAD
        $build = ruby './bin/ots', 'build'
      end
      remote do |argv|
        rel = argv.first || $build
        cd 'onetimesecret.com'
        git 'fetch', '--tags', 'origin'
        git 'checkout', "rel-#{rel}"
      end
    end
    
    release do
      local do |argv|
        git 'fetch', '--tags', :origin
        msg = argv.first
        $build = ruby './bin/ots', 'register-build', msg
        $build_tag = "rel-#{$build}"
        msg_ci = "RUDY PRESENTS: #{$build}"
        msg_ci << " (#{msg})" if msg
        git 'commit', :m, msg_ci, 'BUILD.yml'
        git 'tag', $build_tag
        git 'push', :origin, '--tags'
        git 'co', 'production'
        git 'merge', 'master'
        git 'co', 'master'
        git 'push', :origin
      end
    end

    restart_thin do
      before :stop_thin
      after :start_thin
    end

  end
  
end
