
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
      addresses '184.106.176.70'
    end
    
  end
  
  # ------------------------------------------------
  # LOCAL DEV ENVIRONMENT
  #
  env :dev do
    role :fe do
      user 'cmurtagh' 
      hostname 'centos5'
    end
  end

end
