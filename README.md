# Cisco HUU USB Creator for Debian / Ubuntu
## Acknowledgement
This code is derived from a script posted to Cisco's community forums which works on RedHat and CentOS.

Please see this [Cisco Community post](https://community.cisco.com/t5/unified-computing-system/cisco-standalone-c-series-host-update-utility-usb-image-utility/ta-p/3638625)

## Requirements
- Debian 10 / Ubuntu 20.04 or later
- syslinux

## Running Script
1. Download script and ISO to workstation
2. Connect USB drive and determine device name
3. Execute: `sh create_util_usb_v4.sh <device> <huu iso>`
