
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
  
  env :dev do  
    upload_certs do
      remote :root do
        env = $global.environment
        base_path = "config/certs"
        file_upload "#{base_path}/onetimesecret.com.key", "/etc/pki/tls/private/"
        file_upload "#{base_path}/onetimesecret.com.crt", "/etc/pki/tls/certs/"
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
  
  install_redis do
    remote :root do
      yum 'install', 'redis'
    end
  end

  echo_nonsense do
    local do
      puts "Nonsense!"
    end
  end

end
