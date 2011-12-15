
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
        $branch = git 'rev-parse', '--abbrev-ref', 'HEAD'
        git 'co', 'production'
        git 'merge', 'master'
        git 'push', 'origin', 'production'
        git 'co', $branch
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
        $branch = git 'rev-parse', '--abbrev-ref', 'HEAD'
        raise "Cannot release from master" if $branch == 'master'
        git 'fetch', '--tags', :origin
        msg = argv.first
        $build = ruby './bin/ots', 'register-build', msg
        $build_tag = "rel-#{$build}"
        msg_ci = "RUDY PRESENTS: #{$build}"
        msg_ci << " (#{msg})" if msg
        git 'commit', :m, msg_ci, 'BUILD.yml'
        git 'co', 'master'
        git 'merge', $branch
        git 'tag', $build_tag
        git 'push', :origin, '--tags'
        git 'push', :origin
        git 'co', $branch
      end
    end
    
  end
  
end
