

routines do
  
  update_gems do
    remote do
      #gem_install :bundler
      cd '/var/www/onetimesecret.com/'
      bundle :install
    end
  end
  
  start_redis do
    remote :root do
      redis_server '/etc/redis.conf' 
    end
  end

  #stop_redis do
  #  remote :root do
  #    redis 'stop'
  #  end
  #end
  #
  #restart_redis do
  #  remote :root do
  #    redis 'restart'
  #  end
  #end
 
  start_nginx do
    remote :root do
      nginx 'start'
    end
  end

  stop_nginx do
    remote :root do
      nginx 'stop'
    end
  end

  restart_nginx do
    remote :root do
      nginx 'restart'
    end
  end
  
  reload_nginx do
    remote :root do
      nginx 'reload'
    end
  end
  
  status do
    remote do
      procs = ps 'aux'
      puts "Thin:", procs.grep(/thin/i)
      puts "Redis:", procs.grep(/redis/i)
      puts "Ruby:", procs.grep(/ruby/i)
      puts "nginx:", procs.grep(/nginx/i)
    end
  end

  sysinfo2 do
    remote do
      puts sysinfo(:v)
    end
  end
 
  echo_foobar do
    local do
      puts 'foobar!'
    end
  end
 
  start_thin do
    remote do
      cd '/var/www/onetimesecret.com'
      # Note: here is an example for running thin on a port:
      # thin :e, config_env, :R, 'config.ru', :p, '7143', 'start'
      thin :e, config_env, :R, 'config.ru', :S, '/var/run/thin/thin.sock', :s, 2, 'start'
    end
  end
  
  restart_thin do
    remote do
      cd '/var/www/onetimesecret.com'
      thin :e, config_env, :R, 'config.ru', :S, '/var/run/thin/thin.sock', :s, 2, 'restart'
    end
  end
  
  stop_thin do
    remote do
      cd '/var/www/onetimesecret.com'
      thin :e, config_env, :R, 'config.ru', :S, '/var/run/thin/thin.sock', :s, 2, 'stop'
    end
  end

end

