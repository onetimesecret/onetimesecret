

routines do
  
  update_gems do
    remote do
      #gem_install :bundler
      cd '/var/www/onetimesecret.com/'
      bundle :install
    end
  end
  
  start_redis do
    remote do
      puts "(By the way, you need to run update-redis-config separately)"
      redis "start"
    end
  end

  stop_redis do
    remote do
      redis "stop"
    end
  end
  
  start_nginx do
    remote :root do
      nginx "start"
    end
  end

  stop_nginx do
    remote :root do
      nginx "stop"
    end
  end

  restart_nginx do
    remote :root do
      nginx "restart"
    end
  end
  
  reload_nginx do
    remote :root do
      nginx "reload"
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
      bundle 'exec', 'thin', :R, "config.ru", :p, '7143', :e, config_env, 'start'
      #bundle exec thin -e dev -R config.ru -p 7143 start
    end
  end

  stop_thin do
    remote do
      cd 'car/www/onetimesecret.com'
      bundle 'exec', 'thin', :R, "config.ru", :p, '7143', :e, config_env, 'stop'
    end
  end

end

