# Cisco HUU USB Creator for Debian / Ubuntu
## Acknowledgement
This code is derived from a script posted to Cisco's community forums which works on RedHat and CentOS.

Please see this [Cisco Community post](https://community.cisco.com/t5/unified-computing-system/cisco-standalone-c-series-host-update-utility-usb-image-utility/ta-p/3638625). Code is posted without license as of 8/1/2022.

## Requirements
- Debian 10 / Ubuntu 20.04 or later
- syslinux

## Tested UCS Generations and HUU Versions
Upgrade functionality verified on:
- HUU 3.x and 4.x
- UCS C-Series 2xx M3, M4, and M5 platforms (See Community page for M6)
  - Problems encountered on C480 M5

## Running Script
1. Download script and ISO to workstation
2. Connect USB drive and determine device name
3. Execute: `sh create_util_usb_v4.sh <device> <huu iso>`
