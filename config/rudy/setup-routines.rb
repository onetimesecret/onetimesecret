
# ----------------------------------------------------------- ROUTINES --------
# The routines block describes the repeatable processes for each machine group.
# To run a routine, specify its name on the command-line: rudy startup
routines do
  
  env :prod do  
    upload_certs do
      remote :root do
        env = $global.environment
        base_path = "config/certs"
        file_upload "#{base_path}/onetimesecret.com.key", "/root/"
        file_upload "#{base_path}/onetimesecret.com.crt", "/root/"
      end
    end
  end
  
  env :proto, :status do
    upload_certs do
      remote :root do
        env = $global.environment
        file_upload "config/environment/#{config_env}/bs-proto-server.crt", "/root/"
        file_upload "config/environment/#{config_env}/bs-proto-server.key", "/root/"
      end
    end
  end
  
  upload_keys  do 
    remote :stella do
      base_path = "config/ssh"
      file_upload "#{base_path}/id_rsa",     '.ssh/'
      file_upload "#{base_path}/id_rsa.pub",  '.ssh/'
      file_upload "config/ssh/known_hosts", '.ssh/'
      wildly { chmod :R, 600, '.ssh/*' }
    end
  end
  
  reinstall_site do
    after :install_site
    remote :stella do
      rm :r, 'blamestella.com'
    end
  end
  
  adduser do
    adduser :stella
    local {
      $pubkey = wildly { cat '~/.ssh/id_rsa.pub' }.to_s
      puts $pubkey
    }
    remote :root do |argv|
      username = argv.first || :stella
      raise "Usage: rudy adduser USERNAME" unless username
      mkdir :p, "/home/#{username}/.ssh"
      touch "/home/#{username}/.ssh/authorized_keys"
      wildly { echo "#{$pubkey} >> /home/#{username}/.ssh/authorized_keys" }
      chmod '600', "/home/#{username}/.ssh/authorized_keys"
      chown :R, username, "/home/#{username}/.ssh"
    end
  end
  
  install_redis do
    remote :root do
      yum 'install redis'
    end
  end

  echo_nonsense do
    puts "Nonsense!"
  end

  env :prod, :status, :build do    
    prepimage do
      before :startup
      after :setup
    end
    setup do
      before :adduser, :sysupdate, :installdeps, :install_site, :install_stella, :install_redis, :init_data_dir
      remote :root do
        # For some reason the whois gem installs itself so only root can read the files
        chmod :R, 'go+r', '/usr/local/lib/ruby/gems'
        apache2 'stop'
        chmod 000, '/etc/init.d/apache2'
      end
    end
  end
  
end
