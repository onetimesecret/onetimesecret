

routines do
  
  update_gems do
    remote do
      #gem_install :bundler
      cd 'blamestella.com'
      bundle :install
    end
  end
  
  start_redis do
    remote do
      puts "(By the way, you need to run update-redis-config separately)"
      redis "blamestella.com/config/redis-server.conf"
    end
  end

  stop_redis do
    remote do
      bs "stop-redis"
    end
  end
  
  stella_version do 
    remote do
      disable_safe_mode
      ruby "./stella/bin/stella -V"
    end
  end
  
  irb do
    remote do
      irb :I, 'blamestella.com/lib', :r, 'blamestella'
    end
  end

  save_redis do
    remote do
      bs :e, config_env, "save"
    end
  end
  
  bgsave do
    remote do
      bs "bgsave"
    end
  end
  
  enqueue do
    remote do |args|
      raise "Usage: rudy enqueue CLASS [arg]" unless args.first 
      bs "enqueue", *args
    end
  end

  reprocess do
    remote do |args|
      raise "Usage: rudy reprocess [-H -V] OBJECTID [OBJECTID2,...]" unless args.first 
      bs "reprocess", *args
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
  
  update_s3cmd_config do
    remote do
      file_upload "config/environment/#{config_env}/s3cfg", ".s3cfg"
      chmod 600, '.s3cfg'
      puts "Don't forget to add the AWS secret key"
    end
  end
  
  update_nginx_config do
    after :reload_nginx
    remote :root do
      file_upload "config/environment/#{config_env}/nginx.conf", "nginx.conf"
      file_upload "config/environment/#{config_env}/htpasswd", "/etc/nginx/"
      mv '/etc/nginx/nginx.conf', '/etc/nginx/nginx.conf-PREV'
      mv 'nginx.conf', '/etc/nginx/'
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

  redis_dump do
    remote do
      stamp = bs 'build'
      base_path = '/data/bs/archive'
      quietly { mkdir :p, base_path }
      file_name = quietly { "redis-#{hostname.to_s.strip}-#{stamp.to_s.strip}.json.bz2" }
      $remote_file = File.join(base_path, file_name)
      wildly { redis_dump " | bzip2 > #{$remote_file}"}
      file_download $remote_file, $remote_file
    end
  end
    
  backup_redis do
    before :save_redis
    remote do
      base_path = '/data/bs/archive'
      quietly { mkdir :p, base_path }
      source_file = '/data/bs/current/redis.rdb'
      raise "No file" unless file_exists?(source_file)
      #stamp = Time.now.strftime("%Y%m%d-%H:%M:%S")
      stamp = bs 'build'
      file_name = quietly { "redis-#{hostname.to_s.strip}-#{stamp.to_s.strip}.rdb.bz2" }
      $remote_file = File.join(base_path, file_name)
      unsafely { cat "#{source_file} | bzip2 > #{$remote_file}" }
      file_download $remote_file, $remote_file
    end
  end
    
  restore_redis do
    before :stop_redis
    after :start_redis
    remote do |argv|
      redis_file = '/data/bs/current/redis.rdb'
      local_file = argv.first
      unless File.exists?(local_file || '')
        raise "Usage: rudy restore-redis path/2/redis.rdb.bz2" 
      end
      unless $global.auto
        puts "Restore #{local_file.bright} to #{[$global.environment,$global.role].join('-').bright}"
        exit unless Annoy.are_you_sure?
      end
      file_name = File.basename local_file
      file_upload local_file, "/data/bs/current/#{file_name}"
      mv redis_file, "#{redis_file}-PREV"
      unsafely { bunzip2 :c, "/data/bs/current/#{file_name} > #{redis_file}" }
    end
  end
  
  sysinfo2 do
    remote do
      puts sysinfo(:v)
    end
  end
 
  echo_foobar do
    puts 'foobar!'
  end
 
  thin_vars do 
    remote do 
      $user = Rudy::Huxtable.current_machine_user
      $pid = "/tmp/bs_#{$user}.pid"
      $log = "/tmp/bs_#{$user}.log"
      $sock = "/tmp/bs_#{$user}.sock"
    end
  end
  
  start_thin do
    before :thin_vars
    remote do
      cd 'blamestella.com'
      thin :R, "./app.ru", :P, $pid, :S, $sock, :l, $log, :s, thin_instances, :d, :e, config_env, 'start'
    end
  end
  stop_thin do
    before :thin_vars
    remote do
      cd 'blamestella.com'
      thin :R, "./app.ru", :P, $pid, :S, $sock, :l, $log, :s, thin_instances, :d, :e, config_env, 'stop'
    end
  end
  
  
  ## Rye 0.9.3 syntax: Add named routines
  ##
  ## routine :start_thin do
  ##   call :thin_vars
  ##   thin :e, config_env, 'start'
  ##   local do
  ##     # some jazz
  ##   end
  ## end

  stop_workers do
    remote do
      args = [:e, config_env, "stop-workers"]
      args.unshift :Y if $global.auto
      bs args
    end
  end
  
  start_workers do
    remote do |args|
      count = args.first || 5
      puts "Starting #{count} workers"
      count.to_i.times do 
        bs :e, config_env, "start-worker", :d
      end
    end
  end
  
  restart_workers do
    before :stop_workers
    after :start_workers
  end
  
  
  stop_all do
    before :stop_scheduler, :stop_thin
    local do
      sleep 5
    end
    after :stop_workers, :stop_redis
  end
  
  start_all do
    #before :start_redis
    local do
      sleep 5
    end
    after :start_thin, :start_workers, :start_scheduler
  end
end

