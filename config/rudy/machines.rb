
# ---------------------------------------------------------  MACHINES  --------
# The machines block describes the 'physical' characteristics of your machines. 
machines do
  
  bucket 'onetimesecret'

  # ------------------------------------------------
  # PRODUCTION ENVIRONMENT (184.106.176.70)
  #
  env :prod do
    role :fe do
      user :ots
      hostname 'onetimesecret.com'
    end
    
  end
  
  # ------------------------------------------------
  # LOCAL DEV ENVIRONMENT
  #
  env :dev do
    role :fe do
      user Rudy.sysinfo.user 
      hostname 'localhost'
    end
  end

end
