#!/bin/bash

#------------ User Vars ----------------------------------
# Set desired number of snapshots to keep before pruning
# This must be >= 1
MAX_SNAPSHOTS=7
# --------------------------------------------------------

set -eu -o pipefail

trap 'catch $? $LINENO' ERR

catch() {
    echo ""
    echo "ERROR CAUGHT!"
    echo ""
    echo "Error code $1 occurred on line $2"
    echo ""
    echo "Please report this issue to: helix-cloud-support@perforce.com"
    echo "Please include copy of this script output, logs, and screenshots."
    exit "$1"
}

if [ "$(whoami)" != "perforce" ]; then
    echo "Script must be run as user: perforce"
    exit 255
fi

# Check if SDP_INSTANCE is set as environment variable or passed as positional argument
export SDP_INSTANCE=${SDP_INSTANCE:-Undefined}
export SDP_INSTANCE=${1:-$SDP_INSTANCE}
if [[ $SDP_INSTANCE == Undefined ]]; then
   echo "Instance parameter not supplied."
   echo "You must supply the Perforce instance as a parameter to this script."
   exit 1
fi

PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/root/bin


echo "Running daily offline checkpoint of depot before creating snapshot"
/p4/common/bin/daily_checkpoint.sh "${SDP_INSTANCE}"


DROPLET_ID="$(curl -s http://169.254.169.254/metadata/v1.json | jq -r -c '.droplet_id')"
EPOCH_DATE=$(date '+%s')
DATE=$(date)
VOLUME_NAME=$(lsblk -o MOUNTPOINT,SERIAL | grep -w hxdepots | awk '{print $2}')
VOLUME_ID=$(doctl compute volume list | grep -w "$VOLUME_NAME" | awk '{print $1}')

echo "Creating snapshot of Volume ID $VOLUME_ID for Droplet ID $DROPLET_ID"

doctl compute volume snapshot "$VOLUME_ID" --snapshot-name "Droplet ID: $DROPLET_ID - Helix Core Depot Data - Timestamp: $EPOCH_DATE" --snapshot-desc "Helix Core Depot volume snapshot created on $DATE" --tag helix,helixcore,helix-core,depot

SNAPSHOTS=$(doctl compute snapshot list "*Helix Core Depot Data*" --format ID,NAME --output json |  jq 'sort_by(.created_at)')
SNAPSHOT_COUNT=$(echo "$SNAPSHOTS" | jq -c 'length')
COUNT=$(echo "$SNAPSHOTS" | jq "sort_by(.created_at)[:-$MAX_SNAPSHOTS] | length")

echo "Found $SNAPSHOT_COUNT snapshots and $COUNT need to be pruned"

for ((i=0; i<COUNT; i++)); do
    SNAPSHOT_ID=$(echo "$SNAPSHOTS" | jq -r '.['"$i"'].id')
    SNAPSHOT_NAME=$(echo "$SNAPSHOTS" | jq -r '.['"$i"'].name')
    echo "Deleting snapshot ID $SNAPSHOT_ID with name $SNAPSHOT_NAME"
    doctl compute snapshot delete --force "$SNAPSHOT_ID"
done
