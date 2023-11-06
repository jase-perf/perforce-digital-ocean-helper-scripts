#!/bin/bash

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

# Save these for later
SCRIPT_NAME=$(basename -- "$0")
DIR_NAME="$(dirname "$(realpath $0)")"

usage() { 
    cat <<HELP_USAGE

================================================================================

This script will assist in transitioning your Helix Core Depot data off of your 
Droplet's root volume and onto a dedicated volume. 

NOTE: During this data migration your Helix Core process will be stopped! 
The length of time that Helix Core will be unreachable will depend on how much 
data you have checked into your Depots.  Please wait for all existing processes 
(user submits, user sync, etc) to complete before continuing this process.

If this is a brand new server with no important data on it yet:
Proceed with this script.

If this server already has important data, we strongly recommend you checkpoint 
it and make a snapshot before running this script.
- Exit this script with Ctrl+C
- Make sure no users are currently connected to the server
- Run the script /p4/common/bin/daily_checkpoint.sh as the perforce user
- Go to this droplet in your Digital Ocean account, click on Snapshots, then 
  click the "Take live snapshot" button
- Finally, return to this script and complete it.

HELP_USAGE
}


# shellcheck disable=SC2199
if [[ ( $@ == "--help") ||  $@ == "-h" ]] 
then 
	usage
	exit 0
fi  

if [ "$(whoami)" != "root" ]; then
    echo "Script must be run as user: root"
    exit 255
fi

usage

echo ""
echo ""

read -p "I have read through and understand the usage information provided with this script.  Enter 'Y' to continue. " -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo "Exiting script"
    exit 1
fi


cat <<AUTH_USAGE


================================================================================

The next step is going to prompt you to authenticate doctl for use with your 
DigitalOcean account. "doctl" is the name of the Digital Ocean command line
client that is used for automation.

This token is needed so this script can authenticate the DigitalOcean APIs to 
create your volume and run automatic snapshots.

To create your token:
- From your Digital Ocean account, click on API on the lefthand navigation
- Click the Generate New Token button
- Give it a name
- Choose "No Expiry" for the expiration
- Make sure Write is checked and then click Generate Token.
- Be sure to copy the token and save it somewhere safe. It will not be shown 
  again.

Docs: https://docs.digitalocean.com/reference/api/create-personal-access-token/


NOTE: You will not see text that is pasted or typed in.

AUTH_USAGE

DOCTL_SUCCESS=0
while [ $DOCTL_SUCCESS -eq 0 ]
do
    # this will prompt user for credentials and validate them
    DOCTL_SUCCESS=1
    doctl auth init || DOCTL_SUCCESS=0
    echo
done
# This script is running as root and needs the DO credentials to create the volume
# the credentials needs to also be available to the perforce user so that the daily snapshots will work
mkdir -p /home/perforce/.config/doctl/
cp /root/.config/doctl/config.yaml /home/perforce/.config/doctl/
chown -R perforce:perforce /home/perforce

read -e -p "What size (in GBs) would you like your new Depot Volume to be? (This can be increased later) [Default: 100] " -i '100' -r DEPOT_SIZE
read -e -p "Name for Helix Core Depot Volume.  Note this name must be unique per DigitalOcean Region [Default: helix-core-depot] " -i 'helix-core-depot' -r VOLUME_NAME

export DEPOT_SIZE="${DEPOT_SIZE}GiB"

REGION="$(curl -s http://169.254.169.254/metadata/v1.json | jq -r -c '.region')"
DROPLET_ID="$(curl -s http://169.254.169.254/metadata/v1.json | jq -r -c '.droplet_id')" 

echo "Creating new volume..."
VOLUME_ID=$(doctl compute volume create "$VOLUME_NAME" --desc "Volume used by Helix Core for storing Depot data" --region "$REGION" --size "$DEPOT_SIZE" --tag helix-core,depot --output json | jq -r -c '.[].id')

# Give DO time to create the volume before trying to attach it
sleep 5

# Give DO time to create the volume before trying to attach it
sleep 5

echo "Volume with ID $VOLUME_ID created."

echo "Attaching volume to Droplet..."
doctl compute volume-action attach "$VOLUME_ID" "$DROPLET_ID" --wait > /dev/null

sleep 2
BLOCK_DEVICE=$(lsblk -o NAME,SERIAL | grep -w "$VOLUME_NAME" | awk '{print $1}')
BLOCK_DEVICE="/dev/${BLOCK_DEVICE}"

echo "Volume attched to Droplet at $BLOCK_DEVICE."


echo "Migrating Helix Core data over to new volume..."

systemctl stop p4d_1

mv /hxdepots /hxdepots_tmp
mkdir /hxdepots
mkfs -t xfs "$BLOCK_DEVICE"
blkid "$BLOCK_DEVICE" | awk -v OFS="   " '{print $2,"/hxdepots","xfs","defaults,nofail","0","2"}' >> /etc/fstab
mount -a
mv /hxdepots_tmp/* /hxdepots/
rm -rf /hxdepots_tmp
chown -R perforce:perforce /hx*

systemctl start p4d_1

sleep 5

echo "Migration Helix Core data complete."

echo "Running Helix Core Verify..."

# shellcheck disable=SC2024
sudo -i -u perforce /p4/common/bin/p4verify.sh 1

echo "Helix Core Verify complete."


cat <<BACKUP_USAGE


================================================================================

A new crontab entry has been created for the perforce user that will create a 
checkpoint of the database and then snapshot the Helix Core Depot Volume on a 
daily basis. These checkpoints + snapshots can be used to restore your server 
from backup. 

The script will automatically prune older snapshots and only keep a set number.
Set the number of snapshots you wish to keep, below. See snapshot pricing here: 
https://docs.digitalocean.com/products/images/snapshots/details/pricing/




BACKUP_USAGE

read -e -p "Enter the maximum number of snapshots you would like keep (Must be an integer of 1 or higher) [default: 7] " -i '7' -r MAX_SNAPSHOTS
# Remove any whitespace or non-numeric characters
MAX_SNAPSHOTS="$(echo -e "${MAX_SNAPSHOTS}" | sed "s/[^0-9]//g")"
# If empty, set to default of 7
if [ -x "$MAX_SNAPSHOTS" ]; then MAX_SNAPSHOTS=7; fi
if [ "$MAX_SNAPSHOTS" -eq "0" ]; then MAX_SNAPSHOTS=7; fi

echo "A maximum of $MAX_SNAPSHOTS will be stored."
sed -i "s/MAX_SNAPSHOTS=.*/MAX_SNAPSHOTS=$MAX_SNAPSHOTS/" /p4/common/bin/daily-checkpoint-and-snapshot.sh

# shellcheck disable=SC2024
sudo -i -u perforce crontab -l > /tmp/crontab
# shellcheck disable=SC2024
# Comment out the daily_checkpoint.sh if it isn't commented out already
sed -i '/^[^#].*run_if_master.*daily_checkpoint\.sh.*/ s/^/# /' /tmp/crontab
# shellcheck disable=SC2024
# Add comments to explain and then insert our new checkpoint and snapshot line
sed -i '/daily_checkpoint\.sh/a\
# The daily-checkpoint-and-snapshot.sh script runs the daily-checkpoint script before creating the snapshot\
# If removing the daily-checkpoint-and-snapshot.sh line, be sure to enable the above daily-snapshot.sh line\
5 2 * * * [ -e /p4/common/bin ] && /p4/common/bin/run_if_master.sh ${INSTANCE} /p4/common/bin/daily-checkpoint-and-snapshot.sh ${INSTANCE} >> /p4/1/logs/digitalocean_volume_snapshot.log 2>&1' /tmp/crontab

# shellcheck disable=SC2024
sudo -i -u perforce crontab /tmp/crontab

rm -rf /tmp/crontab


cat <<SUMMARY


================================================================================

New drive setup complete!

Volume name:        $VOLUME_NAME
Drive size:         $DEPOT_SIZE
Drive mount point:  /hxdepots
Drive device ID:    $BLOCK_DEVICE


A Helix Core checkpoint of the server database will be created and a
Digital Ocean volume snapshot of the checkpoint and all depot files will be 
created daily. The latest $MAX_SNAPSHOTS snapshots will be stored on Digital 
Ocean and older ones will be purged.
You can view your Snapshots in the DigitalOcean Console by going to 
Images -> Snapshots -> Volumes.

If you need to edit the maximum number of snapshots later, you can edit the 
MAX_SNAPSHOTS variable in /p4/common/bin/daily-checkpoint-and-snapshot.sh

ADVANCED USERS ONLY:
  To disable or change the timing of these automated snapshots edit the crontab of
  the perforce user and comment out the daily-checkpoint-and-snapshot.sh entry via
  crontab -e
  Then un-comment the daily_checkpoint.sh entry before this one so you at 
  least get checkpoints and journal rotations.

This script will now prevent itself from being run again.

================================================================================

SUMMARY


# Prevent the script from being run again
chmod -x "${DIR_NAME}/${SCRIPT_NAME}"
mv "${DIR_NAME}/${SCRIPT_NAME}" "${DIR_NAME}/${SCRIPT_NAME%.*}.txt"
