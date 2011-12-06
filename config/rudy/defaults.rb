

# ----------------------------------------------------------- DEFAULTS --------
# These values are used as defaults for their respective global settings. They
# can be overridden by the command-line global options.  
#
defaults do
  environment :dev
  zone :'us-east-1b'
  role :fe
  color true                         # Terminal colors? true/false
  user 'root'                        # The default remote user
  #localhost 'hostname'              # A local hostname instead of localhost
  #auto true                         # Skip interactive confirmation?
  #keydir 'path/2/keys/'             # The path to store SSH keys
end
