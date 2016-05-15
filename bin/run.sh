#!/bin/sh

#Move to the folder where onetimepad is installed
cd `dirname $0`

#Was this script started in the bin folder? if yes move out
if [ -d "../bin" ]; then
  cd "../"
fi

ignoreRoot=0
for ARG in $*
do
  if [ "$ARG" = "--root" ]; then
    ignoreRoot=1
  fi
done

#Stop the script if its started as root
if [ "$(id -u)" -eq 0 ] && [ $ignoreRoot -eq 0 ]; then
   echo "You shouldn't start OneTimePad as root!"
   echo "Please type 'OneTimePad rocks my socks' or supply the '--root' argument if you still want to start it as root"
   read rocks
   if [ ! "$rocks" == "OneTimePad rocks my socks" ]
   then
     echo "Your input was incorrect"
     exit 1
   fi
fi

# set port if specified
port=7143
if [ $# -ge 1 ]; then
   port=$1
fi

#start redis server
redis-server /etc/onetime/redis.conf

#Move to the node folder and start
echo "Started OneTimeSecret..."

bundle exec thin -e dev -R config.ru -p $port start