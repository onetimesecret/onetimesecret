#!/bin/sh
# Create backup of redis database 
# 
#   ots-HOSTNAME-YYYY-MM-DD-HH:mm:ss.rdb.bz2.gpg
#   ots-m-rackspace-bs-1-test-wo-01-2011-12-20-15:49:54.rdb.bz2.gpg
#
# Installation:
#   * vi /etc/cron.d/backup_redis
#   0,30 * * * * root /bin/sh /var/www/onetimesecret.com/bin/backup_redis.sh && /usr/bin/ruby /var/www/onetimesecret.com/bin/clean_backups.rb
#   * On another machine, sync the S3 bucket to local disk:
#   5,35 * * * * root /usr/bin/logger "syncing ots backups" && /usr/local/s3cmd/s3cmd -c /root/.s3cfg sync --skip-existing s3://solutious-onetime/ /data/ots/
#   59 * * * * root /usr/bin/logger "deleting ots files older than 3 days" && /bin/rm -f `find /data/ots/ -name '*.gpg'  -cmin +4340`
#   
#   
# To decrypt a file:
#   $ gpg -d --passphrase-file $PKEYFILE path/2/file
#

# Location of the redis dump. 
# TODO: call redis bgsave explicitly
RDBFILE=/var/lib/redis/ots-global.rdb

# Config component for s3cmd (we need to create a new bucket)
BUCKET=solutious-onetime

# Used to stamp this particular backup
NOWSTAMP=`/bin/date '+%F-%T'`
HOSTNAME=`/bin/hostname`
S3CMD='/usr/bin/s3cmd -c /root/.s3cfg --no-progress'
OUTFILE="/var/lib/redis/ots-$HOSTNAME-$NOWSTAMP.rdb.bz2.gpg"
LOGGER="/usr/bin/logger -i -p user.info -t ots-backup-redis"
LOCALDIR='/home/encrypted_backups'

# The passphrase used to gpg encrypt the backup
PKEYFILE="/etc/pki/tls/private/onlinephrase"
GPGOPTS="--no-use-agent --no-tty --force-mdc --passphrase-file $PKEYFILE --simple-sk-checksum -c"

# Derive the passphrase from another important file 
if [ ! -f "$PKEYFILE" ]; then
  rm -f $PKEYFILE
  grep 33eM /etc/pki/tls/private/onetimesecret.com.key > $PKEYFILE
  chmod 600 $PKEYFILE
fi

$LOGGER "Creating $RDBFILE"
su -c "cd onetimesecret.com; /usr/local/bin/ruby bin/ots redis --save" -l ots

if [ ! -f "$RDBFILE" ]; then
  $LOGGER "Redis RDB file does not exists at $RDBFILE!"
  exit 10
fi

$LOGGER "Encrypting to $RDBFILE.bz2.gpg"
/usr/bin/bzip2 -c $RDBFILE | /usr/bin/gpg $GPGOPTS > $RDBFILE.bz2.gpg
/bin/rm -f $RDBFILE

$LOGGER "Copying to $OUTFILE"
/bin/cp $RDBFILE.bz2.gpg $OUTFILE

if [ ! -f "$OUTFILE" ]; then
  $LOGGER "Could not create $OUTFILE!"
  exit 20
fi

$LOGGER "Uploading to s3://$BUCKET/$HOSTNAME/"
$S3CMD put $OUTFILE s3://$BUCKET/$HOSTNAME/

$LOGGER "Moving local copy to $LOCALDIR"
/bin/mv $OUTFILE $LOCALDIR

$LOGGER "Deleting encrypted backups older than 3 hours"
/bin/rm -f `find $LOCALDIR/ -name "ots-$HOSTNAME-*.rdb*.gpg" -cmin +190`
