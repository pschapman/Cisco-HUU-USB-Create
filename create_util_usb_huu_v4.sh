#!/bin/bash
################################################################################
# Description  : Creates bootable USB from HUU ISO file
# Author       : Jeffery Foster (Cisco)
# Website      : https://community.cisco.com/t5/unified-computing-system/cisco-standalone-c-series-host-update-utility-usb-image-utility/ta-p/3638625
# 
# ## Version 4 - Debian 10 / Ubuntu Server 20.04 ##
# Acknolegement: Elliot Dierksen for providing equivalent 'apt' command and updated syslinux path.
#
# Author       : Paul Chapman (ConvergeOne)
#
# Changes      : Removed references to SCU. (Replaced with HUU for clarity.)
#              : Converted ISO test to function.
#              : Added more status messages
#              : Removed verbose file copy (-rvfp --> -rfp)
#              : New partition set to 0C (FAT32 Win95) instead of 83 (Linux) (Tightens similarity to Rufus process for Windows Users)
#              : Added '-W always' to fdisk to fix config error due to partition signature
#              : Removed unused variables / code for clarity
#              : Piped all command outputs to /dev/null (Not possible for fdisk)
#              : Added deletion warning prompt for users
#              : Added early drive validation with syntax hint (based on community feedback on original script)
#
# Validation   : Tested with HUU 3.x and 4.x on Ubuntu Server 20.04 VM (USB Host Media mounted via ESXi)
# Platforms    : UCS C220 M3 & M4, C240 M4
# 
# Syntax       : sh create_util_usb_v4.sh <device> <huu iso> [debug]
# Example      : sh create_util_usb_v4.sh /dev/sdb ucs-cxxxmx-huu-x.x.x.iso
################################################################################
echo 
echo "###### Cisco Host Update Utility (HUU) - Bootable USB Creator ######"
echo 

if [ $# -lt 2 ];then
    echo "## ERROR: Missing argurments"
    echo "syntax: sh create_util_usb_v4.sh <device> <huu-iso-image>"
    echo "example:"
    echo "  sh create_util_usb_v4.sh /dev/sdb ucs-c240m4-huu-4.2.1f.iso"
    exit 1;
elif [ $# -eq 3 ]; then
    if [ "$3" == "debug" ]; then
        set -x
    fi
fi

USB_DEV=$1
HUU_ISO=$2
PART1_DEV=$USB_DEV"1"
USB_DIR=/tmp/usb2.$$
MBR=/usr/lib/syslinux/mbr/mbr.bin
TMP_HUU=/tmp/HUU

# Verify user has correctly specified a drive, not a partition (or ISO file)
TGT_MODEL=$(fdisk -l $USB_DEV | grep -i model)
if [ $? -ne 0 ]; then
    echo "## ERROR: Invalid Device: $USB_DEV"
    echo
    echo "HINT 1: Verify syntax: sh create_util_usb.sh <device> <huu-iso-image>" 
    echo "HINT 2: If your device name ends with a number, it is probably a partition not a drive (e.g. sdb1 vs sdb). Try without the number."
    exit 1;
fi

#Check for syslinux (Debian / Ubuntu - apt)
apt list --installed 2>/dev/null | grep syslinux\/ > /dev/null
if [ $? -ne 0 ]; then
    echo "ERROR:  syslinux not installed"
    exit 1;
fi

# Verify user wants to proceed with device wipe
echo "## WARNING: THIS SCRIPT WILL DESTROY ALL PARTITIONS AND DATA ON THE SPECIFIED DEVICE!"
echo "    Device: $USB_DEV"
echo "    $TGT_MODEL"
echo "Do you want to proceed (y/N)?"
read ans
ans=`echo $ans | tr [:upper:] [:lower:]`
if [ "$ans" = "y" ]; then
    echo "Proceeding..."
else
    exit 1;
fi

test_iso ()
{
    echo "## Validating ISO..."

    basename $HUU_ISO | grep -i "huu" > /dev/null
    if [ $? -ne 0 ]; then
        echo "## WARNING: The ISO file name doesn't look correct. Do you want to proceed (y/N)?"
        read ans
        ans=`echo $ans | tr [:upper:] [:lower:]`
        if [ "$ans" = "y" ]; then
            echo "Proceeding..."
        else
            exit 1;
        fi
    fi

    TMP_TEST_DIR=/tmp/huu_test.$$
    mkdir -p $TMP_TEST_DIR
    losetup -f > /dev/null
    if [ $? -ne 0 ]; then
        echo "ERROR: No free loop device found. "
        exit 1
    fi

    mount -o loop $HUU_ISO $TMP_TEST_DIR 2> /dev/null > /dev/null
    if [ $? -ne 0 ]; then
        echo "ERROR: Unable to mount HUU iso for validation. Check file name and path."
        rm -rf $TMP_TEST_DIR
        exit 1;
    fi
    umount $TMP_TEST_DIR

    echo " "

    rm -rf $TMP_TEST_DIR

    echo "    ## ISO Validation Complete..."
}

create_part ()
{
    echo "## Repartitioning Drive..."
    
    echo "    ## Destroying partition table....."
    umount $PART1_DEV 2> /dev/null > /dev/null
    dd if=/dev/zero of=$USB_DEV bs=4096 count=10 2> /dev/null > /dev/null
    echo "    ## Building 1G partition....."
    (
        echo n # Create new partition
        echo p # Primary partition
        echo 1 # Partition 1
        echo # First sector (Accept default)
        echo +1024M # Create 1GB partition
        echo t # Set partition type (default Linux)
        echo c # Select FAT32 (Win95)
        echo w # Write changes
    ) | fdisk -W always $USB_DEV
    
    if [ $? -ne 0 ]; then
        echo "ERROR: Partition creation failed."
        exit 1;
    fi
    
    echo "    ## Marking partition 1 Active (bootable)....."
    (
        echo a # Set partition Active (bootable)
        echo w # Write changes
    ) | fdisk $USB_DEV
    
    echo "    ## Drive Partitioning Complete..."
}

format_part () 
{
    echo "## Formatting Drive with FAT32..."
    mkdosfs -F 32 $PART1_DEV > /dev/null
    if [ $? -ne 0 ]; then
        echo "ERROR: Formatting of first USB partition failed"
        exit 1;
    fi
    echo "    ## Formating Complete..."
}


add_syslinux ()
{
    echo "## Loading syslinux..."
    echo "    ## Applying Master Boot Record..."
    dd if=$MBR of=$USB_DEV 2> /dev/null > /dev/null
    if [ $? -ne 0 ]; then
        echo "ERROR: dd of mbr.bin failed ";
        exit 1;
    fi

	# Pause to allow drive to settle
	sleep 2

    echo "    ## Installing Boot Loader..."
    syslinux $PART1_DEV 
    if [ $? -ne 0 ]; then
        echo "ERROR: syslinux failed [ $PART1_DEV ] Failed";
        exit 1;
    fi
    
    echo "    ## Loading syslinux Complete..."
}


copy_files ()
{
    echo "## Starting Copy Process..."
    echo "    ## Mounting USB Partition $PART1_DEV..."
    mkdir -p $USB_DIR
    mount $PART1_DEV $USB_DIR > /dev/null
    if [ $? -ne 0 ]; then
        echo "ERROR: Mounting of partition [ $PART1_DEV ] on Dir [ $USB_DIR ] Failed";
        rm -rf $USB_DIR
        exit 1;
    fi
    
    echo "    ## Checking for Free Loop Devices..."
    losetup -f > /dev/null
    if [ $? -ne 0 ]; then
        echo "ERROR: No Free loop device found. Exiting";
        umount $USB_DIR
        rm -rf $USB_DIR
        rm -rf $TMP_HUU
        exit 1;
        
    fi
    
    echo "    ## Mounting ISO File $HUU_ISO..."
    mkdir -p $TMP_HUU
    mount -o loop $HUU_ISO $TMP_HUU 2> /dev/null > /dev/null
    if [ $? -ne 0 ]; then
        echo "ERROR: Mounting of HUU ISO [ $HUU_ISO ] on Dir [ $TMP_HUU ] Failed";
        umount $USB_DIR
        rm -rf $USB_DIR
        rm -rf $TMP_HUU
        exit 1;
    fi

    echo "    ## Copying Files. Please wait... (3 to 10 minutes)"
    cp -rpf $TMP_HUU/* $USB_DIR/.
    if [ $? -ne 0 ]; then
        echo "ERROR: Copying of HUU Files to USB failedFailed";
        umount $USB_DIR
        rm -rf $USB_DIR
        rm -rf $TMP_HUU
        exit 1;
    fi
     
    echo "    ## Renaming isolinux Directory..."
    mv $USB_DIR/isolinux/ $USB_DIR/syslinux
    echo "    ## Renaming isolinux Config File..."
    mv $USB_DIR/syslinux/isolinux.cfg $USB_DIR/syslinux/syslinux.cfg

    echo "    ## Changing Media Labels in syslinux.cfg..."
    # Set the UUID of USB FAT Partition device as part of syslinux.cfg
    USB_UUID=`blkid $PART1_DEV | cut -d" " -f2 | sed 's/\"//g'`
    sed -ir "s/root=live:CDLABEL=.*-huu-[0-9]*/root=live:${USB_UUID}/g" $USB_DIR/syslinux/syslinux.cfg    
    
    echo "    ## Cleaning Up..."
    umount $TMP_HUU
    umount $USB_DIR
    rm -rf $TMP_HUU $USB_DIR    

    echo "    ## Copy Process Complete..."
}

test_iso
create_part
format_part
add_syslinux
copy_files 

echo
echo "## Bootable drive creation complete.  New Partition Information"
echo 
fdisk -l $USB_DEV

exit 0
