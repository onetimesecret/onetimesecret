#!/bin/sh
# Create backup of redis database 
# 
#   onetime-rdb-HOSTNAME-YYYY-MM-DD-HH:mm:ss.bz2.gpg
#   onetime-rdb-m-rackspace-bs-1-test-wo-01-2011-12-20-15:49:54.bz2.gpg
#
# To decrypt a file:
#   $ gpg -d --passphrase-file /etc/pki/tls/private/onlinephras path/2/file
#

# Location of the redis dump
RDBFILE=/var/lib/redis/dump.rdb

# Config component for s3cmd (we need to create a new bucket)
BUCKET=solutious-onetime

# Used to stamp this particular backup
NOWSTAMP=`date '+%F-%T'`
HOSTNAME=`hostname`
TEMPFILE="/tmp/onetime-rdb-$HOSTNAME-$NOWSTAMP"

# The passphrase used to gpg encrypt the backup
PKEYFILE="/etc/pki/tls/private/onlinephrase"

# Derive the passphrase from another important file 
if [ ! -f $PKEYFILE ]; then
  rm -f $PKEYFILE
  grep 33eM /etc/pki/tls/private/onetimesecret.com.key > $PKEYFILE
  chmod 600 $PKEYFILE
fi

# Copy the dump to a temp location, bzip2 and gpg encrypt it
/bin/cp /var/lib/redis/dump.rdb $TEMPFILE
/usr/bin/bzip2 $TEMPFILE
/usr/bin/gpg --no-use-agent --no-tty --force-mdc --passphrase-file $PKEYFILE --simple-sk-checksum -c $TEMPFILE.bz2

# Upload the file to S3
/usr/bin/s3cmd put $TEMPFILE.bz2 s3://$BUCKET/$HOSTNAME/

# Remove the backups from the temp location
/bin/rm -f $TEMPFILE.bz2

# Store the encrypted backup locally
/bin/mv $TEMPFILE.bz2.gpg /home/encrypted_backups

# Delete any encrypted backups that are older than 3 hours
rm -f `find /home/encrypted_backups/ -cmin +190`
