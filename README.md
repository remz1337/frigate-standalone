# This script is in the process of being integrated into my fork of Tteck's Proxmox Helper Scripts [here](https://github.com/remz1337/Proxmox).

# frigate-standalone
Bash script to deploy Frigate NVR, without the need for Docker.

This script will install Frigate, along with required components (go2rtc, nginx...), to a Debian 11 server.

I have used it to deploy Frigate to an unpriviledged Debian 11 LXC on a Proxmox 7.4 host. The whole stack needs to run as the root user.

The LXC should have the following specs:
- Debian 11
- 16Gb disk
- 2 cores (faster build)
- 1Gb memory

However, for installing I recommend 4 cores and 4Gb of memory.

# Installing Frigate without Docker
From a clean Debian 11 server, execute the following command, either as `root` or as user with `sudo` access:

```
wget -O- https://raw.githubusercontent.com/remz1337/frigate/dev/standalone_install.sh | bash -
```
