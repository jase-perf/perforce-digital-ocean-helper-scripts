# perforce-digital-ocean-helper-scripts
(Not officially supported)

These scripts give you an easy way to move your Perforce depot files to a separate volume on Digital Ocean and setup automatics backups of that volume. This will allow you to increase your storage space independently of your instance type, likely saving a significant amount of money, especially for smaller teams.

## Installation

1. Connect to your Digital Ocean instance as root (via the web console or SSH)
2. Download the `add-depot-volume.sh` and `daily-checkpoint-and-snapshot.sh` scripts to the `/p4/common/bin/` folder with these commands:

        curl -o /p4/common/bin/add-depot-volume.sh https://raw.githubusercontent.com/jase-perf/perforce-digital-ocean-helper-scripts/main/add-depot-volume.sh
        curl -o /p4/common/bin/daily-checkpoint-and-snapshot.sh https://raw.githubusercontent.com/jase-perf/perforce-digital-ocean-helper-scripts/main/daily-checkpoint-and-snapshot.sh
3. Change the ownership and permissions for the files with these commands:

        chown perforce:perforce /p4/common/bin/add-depot-volume.sh
        chown perforce:perforce /p4/common/bin/daily-checkpoint-and-snapshot.sh
        chmod +x /p4/common/bin/add-depot-volume.sh
        chmod +x /p4/common/bin/daily-checkpoint-and-snapshot.sh
4. Continuing as root, run the `add-depot-volume.sh` script and follow the prompts:

        /p4/common/bin/add-depot-volume.sh

**NOTE**: Be sure to verify that checkpoints are being created successfully. These are required if you ever need to restore from backup so it is vital that you make sure they are working. See the "Behind the Scenes" section below for more information.

## Behind the Scenes

This script will take your Digital Ocean access key and use it to create a new storage volume and mount it to your server at the mount point: `/hxdepots`

Additionally it will replace the existing nightly checkpoint script (which is run via a linux crontab entry) with a new script that will create a checkpoint and use the DO key to create a snapshot of the volume every night, which will be stored in your DO account.

Should you ever need to restore a server from backup, these snapshots will contain the depot data (the files) and the latest checkpoint (the database backup) which are the two things needed to restore a server. 

### Checking the Checkpoints
It is very important that you check to make sure the checkpoints are being created successfully. If they are not, you will not be able to restore your server from backup. You can check the logs in `/p4/1/logs/digitalocean_volume_snapshot.log` on the server to see if there are any errors. 
The most common errors come from changing the default `perforce` user's password without also updating the password in the file `/p4/common/config/.p4passwd.p4_1.admin`.

You can check your login by connecting to the server terminal, changing to the perforce user with `su - perforce` and then running `p4login -v 1`

In order to keep costs down, it will store a maximum of 7 days of snapshots. When it creates a new one, it will purge any older ones.
(The max number to keep can be set when running the script or by editing the `MAX_SNAPSHOTS` variable in the `daily-checkpoint-and-snapshot.sh` script later.)

You can view your Snapshots in the DigitalOcean Console by going to Images -> Snapshots -> Volumes.
For information about snapshot pricing, see the [DigitalOcean snapshots pricing page](https://docs.digitalocean.com/products/images/snapshots/details/pricing/).
