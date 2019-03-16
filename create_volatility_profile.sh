#!/bin/bash

# Created by: John Marzella

# Description:
	# This script creates a a system memory profile for Volatility on Debian or Ubuntu systems
	# This script should be run on the memory dump source system or a like-for-like system (same cpu architecture, OS & kernel)
	# Internet access is required to install dependencies and clone volatility source code

# References:
	# https://github.com/volatilityfoundation/volatility/wiki/Linux#creating-a-new-profile

set -e

# variables
dependencies=(git zip dwarfdump gcc make nm)
kernel_ver="$(uname -r)"
kernel_arch="$(uname -m)"
os_release="$(grep DISTRIB_DESCRIPTION /etc/lsb-release | awk -F "=" '{print $2}' | tr -d ' "')"
profile_name="$HOSTNAME-$os_release-$kernel_ver-$kernel_arch.zip"
volatility_repo="https://github.com/volatilityfoundation/volatility.git"
log="create_volatility_profile.log"
declare -A PKGMAP
PKGMAP[headers]="linux-headers-$kernel_ver"
PKGMAP[git]="git"
PKGMAP[gcc]="build-essential"
PKGMAP[make]="build-essential"
PKGMAP[zip]="zip"
PKGMAP[dwarfdump]="dwarfdump"
PKGMAP[nm]="binutils"

# ensure we run commands as root
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
	SUDO="sudo"
fi

log() {
	echo "[$(date --rfc-3339=seconds)]: $*" | tee -a "$log"
}

install_pkg() {
	if [ "$apt_cache_updated" != "true" ]; then
		if ! "$SUDO" apt-get update; then
			log "ERROR: apt-get update failed - aborting script"
			exit
		fi
		apt_cache_updated="true"
	fi
	if ! "$SUDO" apt-get install -y "$1"; then
		log "ERROR: Unable to install $1 package - aborting script"
		exit
	fi
}

### SCRIPT ###

log "Voltaility profile creation script started"

# check and install dependencies if they don't exist
log "Checking package dependecies"
for dependency in "${dependencies[@]}"
	do
		if [ -x "$(command -v "$dependency")" ]; then
	    	log "$dependency dependency exists"
		else
	    	log "$dependency dependency does not exist - attempting install via apt-get"
	    	dep_pkg="${PKGMAP[$dependency]}"
	    	install_pkg "$dep_pkg"
			log "$dependency installed via $dep_pkg package"
		fi
	done

# check and install linux kernel headers
log "Checking linux header dependency"
linux_header="/lib/modules/$kernel_ver"
if [ -d "$linux_header" ]; then
	log "Linux header file found"
else
	log "Linux header file not found - attempting install via apt-get"
	dep_pkg="${PKGMAP[$headers]}"
	install_pkg "$dep_pkg"
	log "$linux_header installed via $dep_pkg package"
fi

# check and create system map
log "Checking system map dependency"
system_map="/boot/System.map-$kernel_ver"
if [ -f "$system_map" ]; then
	log "Linux system map file found"
else
	log "Linux system map file not found - creating now"
	if ! nm "/boot/vmlinuz-$kernel_ver" > "$system_map"; then
		log "ERROR: System map creation failed - aborting script"
	fi
	log "Linux system map file created from vmlinuz-$kernel_ver"
fi

# clone Volatility github repo
log "Downloading latest volatility source code from github"
if ! git clone "$volatility_repo"; then
	log "ERROR: Volatility github repo clone failed - aborting script"
	exit
else
	log "Volatility github repo cloned"
fi

# compile module.c with linux headers and create module.dwarf using dwarfdump
log "Creating kernel data structures (vtypes)"
cd volatility/tools/linux
if ! make; then
	log "ERROR: Make module.dwarf failed - aborting script"
else
	log "Created module.dwarf using dwarfdump"
fi

# bundle module.dwarf and kernel system map into a zip file
cd ../../
if ! "$SUDO" zip "volatility/plugins/overlays/linux/$profile_name" "tools/linux/module.dwarf" "/boot/System.map-$kernel_ver"; then
	log "ERROR: Zip bundle failed - aborting script"
fi
log "Volatility profile ZIP created"

# navigate to the profile and list it
cd volatility/plugins/overlays/linux/
pwd
ls -al "$profile_name"

log "Volatility profile creation script completed successfully"