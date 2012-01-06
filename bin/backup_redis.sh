#!/bin/sh
# Create backup of redis database 
# 
#   ots-HOSTNAME-YYYY-MM-DD-HH:mm:ss.rdb.bz2.gpg
#   ots-m-rackspace-bs-1-test-wo-01-2011-12-20-15:49:54.rdb.bz2.gpg
#
# Installation:
#   * cp bin/backup_redis.sh /etc/cron.hourly/
#   * chmod 755 /etc/cron.hourly/backup_redis.sh
#
# To decrypt a file:
#   $ gpg -d --passphrase-file /etc/pki/tls/private/onlinephras path/2/file
#

# Location of the redis dump. 
# TODO: call redis bgsave explicitly
RDBFILE=/var/lib/redis/dump.rdb

# Config component for s3cmd (we need to create a new bucket)
BUCKET=solutious-onetime

# Used to stamp this particular backup
NOWSTAMP=`date '+%F-%T'`
HOSTNAME=`hostname`
S3CMD='/usr/bin/s3cmd -c /root/.s3cfg --no-progress'
OUTFILE="/var/lib/ots-$HOSTNAME-$NOWSTAMP.rdb.bz2.gpg"
LOGGER="logger -i -p user.info -t ots-backup"
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

if [ ! -f "$RDBFILE" ]; then
  $LOGGER "Redis RDB file does not exists at $RDBFILE!"
  exit 10
fi

$LOGGER "Creating $OUTFILE"
/usr/bin/bzip2 -c /var/lib/redis/dump.rdb | /usr/bin/gpg $GPGOPTS > $OUTFILE

if [ ! -f "$OUTFILE" ]; then
  $LOGGER "Could not create $OUTFILE!"
  exit 20
fi

$LOGGER "Uploading to s3://$BUCKET/$HOSTNAME/"
$S3CMD put $OUTFILE s3://$BUCKET/$HOSTNAME/

$LOGGER "Moving local copy to $LOCALDIR"
/bin/mv $OUTFILE $LOCALDIR

$LOGGER "Encrypting $RDBFILE"
< $RDBFILE /usr/bin/gpg $GPGOPTS > $RDBFILE.gpg

$LOGGER "Removing the unencrypted redis file"
/bin/rm -f $RDBFILE

$LOGGER "Deleting encrypted backups older than 3 hours"
rm -f `find $LOCALDIR/ -cmin +190`
