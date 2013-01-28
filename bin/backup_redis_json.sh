#!/bin/sh
# Create a JSON dump of a redis database
# 
#   ots-DB-FILTER-HOSTNAME-YYYY-MM-DD-HH:mm:ss.json.bz2.gpg
#   ots-6-customer-m-rackspace-bs-1-test-wo-01-2011-12-20-15:49:54.json.bz2.gpg
#
# Installation:
#   * vi /etc/cron.d/backup_customers
#   0,20 * * * * root /bin/sh /var/www/onetimesecret.com/bin/backup_redis_json.sh 6 customer
#   
# To decrypt a file:
#   $ gpg -d --passphrase-file $PKEYFILE path/2/file
#

DB=$1
FILTER=$2

# Config component for s3cmd (we need to create a new bucket)
BUCKET=solutious-onetime

# Used to stamp this particular backup
NOWSTAMP=`/bin/date '+%F-%T'`
HOSTNAME=`/bin/hostname`
S3CMD='/usr/bin/s3cmd -c /root/.s3cfg --no-progress'
LOGINFO="/usr/bin/logger -i -p user.info -t ots-backup-redis-json -s"
LOGERROR="/usr/bin/logger -i -p user.err -t ots-backup-redis-json -s"
LOCALDIR='/home/encrypted_backups'
OTSHOME='/var/www/onetimesecret.com'
OTSVERSION=`/usr/local/bin/ruby $OTSHOME/bin/ots build`
PREFIX="ots-$HOSTNAME-db$DB-$FILTER"
OUTFILE="/var/lib/redis/$PREFIX-$OTSVERSION-$NOWSTAMP.json.bz2.gpg"

REDIS_CONFIG=/etc/redis.conf
REDIS_PASS=$(grep '^requirepass' $REDIS_CONFIG | awk -F" " '{print $2}')
REDIS_HOST=$(grep '^bind' $REDIS_CONFIG | awk -F" " '{print $2}')
REDIS_PORT=$(grep '^port' $REDIS_CONFIG | awk -F" " '{print $2}')
REDISDUMPCMD="redis-dump -d $DB -f $FILTER"

# The passphrase used to gpg encrypt the backup
PKEYFILE="/etc/pki/tls/private/onlinephrase"
GPGOPTS="--no-use-agent --no-tty --force-mdc --passphrase-file $PKEYFILE --simple-sk-checksum -c"

if [ ! "$DB" ]; then
  $LOGERROR -s "Usage: $0 <DB> <FILTER>"
  exit 1
fi
if [ ! "$FILTER" ]; then
  $LOGERROR -s "Usage: $0 <DB> <FILTER>"
  exit 1
fi

# Derive the passphrase from another important file 
if [ ! -f "$PKEYFILE" ]; then
  rm -f $PKEYFILE
  grep 33eM /etc/pki/tls/private/onetimesecret.com.key > $PKEYFILE
  chmod 600 $PKEYFILE
fi

$LOGINFO "Creating $OUTFILE"
export REDIS_URI="redis://user:$REDIS_PASS@$REDIS_HOST:$REDIS_PORT"
$REDISDUMPCMD | /usr/bin/bzip2 -c | /usr/bin/gpg $GPGOPTS > $OUTFILE

if [ ! -f "$OUTFILE" ]; then
  $LOGINFO "Could not create $OUTFILE!"
  exit 20
fi

$LOGINFO "Uploading to s3://$BUCKET/$HOSTNAME/"
$S3CMD put $OUTFILE s3://$BUCKET/$HOSTNAME/

$LOGINFO "Moving local copy to $LOCALDIR"
/bin/mv $OUTFILE $LOCALDIR/

$LOGINFO "Deleting encrypted backups older than 3 hours"
/bin/rm -f `find $LOCALDIR/ -name "$PREFIX*.gpg" -cmin +190`
