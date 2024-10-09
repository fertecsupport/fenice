#!/usr/bin/env bash

# Caricamento file setup.conf
source $CONFIGS_DIR/setup.conf

# Caricamento file helpers.sh
source $SCRIPTS_DIR/helpers.sh

isRoot() {
    if [ "$(id -u)" != "0" ]; then
        saveLog "ERROR! This script must be run under the 'root' user"
        exit
    fi
}

isOnline() {
    nc -z 8.8.8.8 53  >/dev/null 2>&1
    online=$?

    if [ $online -ne 0 ]; then
        saveLog "ERROR! This script must be run with a working Internet connection"
        exit
    fi
}

isArchOS() {
    if [ ! -e /etc/arch-release ]; then
        saveLog "ERROR! This script must be run in Arch Linux"
        exit
    fi
}

isPacmanOk() {
    if [ -f /var/lib/pacman/db.lck ]; then
        saveLog "ERROR! Pacman is blocked. If not running remove /var/lib/pacman/db.lck"
        exit
    fi
}

doChecks() {
    isRoot
    isArchOS
    isOnline
    isPacmanOk
}

getFirstDiskAvailable() {
    DISK=""
    PARTSEP=""

    for dev in $(lsblk -ndo name); do
        devinfo="$(udevadm info --query=property --path=/sys/block/$dev)"

        devname=$( sed -n 's/.*DEVNAME=\([^;]*\).*/\1/p' <<< $devinfo )
        devtype=$( sed -n 's/.*DEVTYPE=\([^;]*\).*/\1/p' <<< $devinfo )

        if [ "${devtype,,}" = "disk" ]; then
            if [ "${APP,,}" = "fenice" ]; then 
                partType=$( sed -n 's/.*ID_PART_TABLE_TYPE=\([^;]*\).*/\1/p' <<< $devinfo )
                if [ "${partType,,}" = "gpt" ]; then
                    DISK="$devname"
                    PARTSEP="p"; 
                fi
            else
                devbus=$( sed -n 's/.*ID_BUS=\([^;]*\).*/\1/p' <<< $devinfo )

                if { [ "${devbus,,}" = "ata" ] || [ "${devbus,,}" = "scsi" ]; }; then
                    DISK="$devname"
                fi
            fi
        fi
    done
}

getDisk() {
    getFirstDiskAvailable
    checkError "getFirstDiskAvailable"

    if [ -z $DISK ]; then
        saveLog "ERROR! No available disks ata or scsi found"
        exit 
    else
        sed -i "s|^DISK=|DISK=${DISK}|" $CONFIGS_DIR/setup.conf
        checkError "sed -i \"s|^DISK=|DISK=${DISK}|\" $CONFIGS_DIR/setup.conf"
    fi
}

setTime() {
    timedatectl --no-ask-password set-timezone ${TIMEZONE}
    checkError "timedatectl --no-ask-password set-timezone ${TIMEZONE}"

    timedatectl --no-ask-password set-ntp 1
    checkError "timedatectl --no-ask-password set-ntp 1"
}

createVolumes() {
    sgdisk -Z $DISK 
    checkError "sgdisk -Z $DISK"

    sgdisk -a 2048 -o $DISK
    checkError "sgdisk -a 2048 -o $DISK"

    sgdisk -n 1::$UEFI --typecode=1:ef00 --change-name=1:'EFIBOOT' $DISK
    checkError "sgdisk -n 1::$UEFI --typecode=1:ef00 --change-name=1:'EFIBOOT' $DISK"

    sgdisk -n 2::$SWAP --typecode=1:8200 --change-name=2:'SWAP' $DISK
    checkError "sgdisk -n 2::$SWAP --typecode=1:8200 --change-name=2:'SWAP' $DISK"

    sgdisk -n 3::-0 --typecode=3:8300 --change-name=3:'ROOT' $DISK
    checkError "sgdisk -n 3::-0 --typecode=3:8300 --change-name=3:'ROOT' $DISK"

    partprobe $DISK
    checkError "partprobe $DISK"
}

formatVolumes() {
    mkfs.fat -F 32 ${DISK}${PARTSEP}1
    checkError "mkfs.fat -F 32 ${DISK}${PARTSEP}1"

    mkswap ${DISK}${PARTSEP}2
    checkError "mkswap ${DISK}${PARTSEP}2"

    mkfs.ext4 -qF ${DISK}${PARTSEP}3
    checkError "mkfs.ext4 -qF ${DISK}${PARTSEP}3"
}

mountVolumes() {
    mount ${DISK}${PARTSEP}3 /mnt
    checkError "mount ${DISK}${PARTSEP}3 /mnt"

    mount --mkdir ${DISK}${PARTSEP}1 /mnt/boot
    checkError "mount --mkdir ${DISK}${PARTSEP}1 /mnt/boot"

    swapon ${DISK}${PARTSEP}2
    checkError "swapon ${DISK}${PARTSEP}2"
}

eraseDisk() {
    sgdisk -Z $DISK 
    checkError "sgdisk -Z $DISK"

    showInfo "Il sistema verrà riavviato. Ripetere il comando di installazione al prompt"
    waitForInput

    reboot now
}

setDisk() {
    if [[ $(sgdisk -d ${DISK} 2>&1) == "" ]]; then 
        createVolumes
        formatVolumes
        mountVolumes
    else
        eraseDisk
    fi
}

initPacman() {
    pacman -Syy --noconfirm --needed
    checkError "pacman -Syy --noconfirm --needed"

    pacstrap -i /mnt base base-devel --noconfirm --needed
    checkError "pacstrap -i /mnt base --noconfirm --needed"
}

initFSTable() {
    genfstab -U -p /mnt >> /mnt/etc/fstab
    checkError "genfstab -U -p /mnt >> /mnt/etc/fstab"
}

clone() {
    targetPath="/mnt/root/archinstall"
    configPath="${targetPath}/configs"
    configFile="${configPath}/env.conf"

    if [ ! -d $targetPath ]; then
        mkdir $targetPath
        checkError "mkdir $targetPath"
    fi

    cp -R ${BASE_DIR}/* ${targetPath}
    checkError "cp -R ${BASE_DIR}/* ${targetPath}"

    touch -f "${configFile}"
    checkError 'touch -f "${configFile}'

    targetPath="${HOME}/archinstall"

    echo "ASSETS_DIR=${targetPath}/assets" >> ${configFile}
    echo "SCRIPTS_DIR=${targetPath}/scripts" >> ${configFile}
    echo "CONFIGS_DIR=${targetPath}/configs" >> ${configFile}
    echo "LOGS_DIR=${targetPath}/logs" >> ${configFile}
    echo "INSTALL_LOG=${targetPath}/logs/$( date "+%Y%m%d-%H%M%S" ).log" >> ${configFile}
}

# Esecuzione verifiche preliminari alla procedura di installazione
clear
#showHeader "Preliminary checks and parameters/disk setup"

doChecks
getDisk

# Esecuzione delle operazioni preliminari alla procedura di installazione
# 1. Impostazione di timezone e ntp
# 2. Partizionamento disco, formattazione e mounting volumi
# 3. Inizializzazione pacman e installazione package base sistema operativo
clear
#showHeader "Date/Time Setup, Disk preparation and Pacman initialization" 

setTime
setDisk
initPacman

# Preparazione della FSTable e clonazione degli script per esecuzione in arch-chroot
clear
#showHeader "FSTable initialization and resources cloning" 

initFSTable
clone