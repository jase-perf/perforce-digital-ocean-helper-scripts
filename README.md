# perforce-digital-ocean-helper-scripts
Helper scripts for the official Perforce Digital Ocean image. (Not officially supported)


You will need to download the scripts `add-depot-volume.sh` and `daily-checkpoint-and-snapshot.sh` to the `/p4/common/bin/` folder on your Digital Ocean instance.

### Step 1:
You can do that with these commands:

    curl -o /p4/common/bin/add-depot-volume.sh https://raw.githubusercontent.com/jase-perf/perforce-digital-ocean-helper-scripts/main/add-depot-volume.sh
    curl -o /p4/common/bin/daily-checkpoint-and-snapshot.sh https://raw.githubusercontent.com/jase-perf/perforce-digital-ocean-helper-scripts/main/daily-checkpoint-and-snapshot.sh

### Step 2:
Then run these commands as root:

    chown perforce:perforce /p4/common/bin/add-depot-volume.sh
    chown perforce:perforce /p4/common/bin/daily-checkpoint-and-snapshot.sh
    chmod +x /p4/common/bin/add-depot-volume.sh
    chmod +x /p4/common/bin/daily-checkpoint-and-snapshot.sh