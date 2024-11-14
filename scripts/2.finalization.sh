#!/usr/bin/env bash

# Caricamento file env.conf
source ${HOME}/archinstall/configs/env.conf

# Caricamento file setup.conf
source ${CONFIGS_DIR}/setup.conf

# Caricamento file helpers.sh
source ${SCRIPTS_DIR}/helpers.sh

installOpenbox() {
    homePath="/home/${USERNAME}"
    configPath="${homePath}/.config"
    xinitrcFile="${homePath}/.xinitrc"

    pacman -S openbox xorg-server xorg-xinit xorg-fonts-misc xterm --noconfirm --needed
    checkError "pacman -S openbox xorg-server xorg-xinit xorg-fonts-misc xterm --noconfirm --needed"

    cp "/etc/X11/xinit/xinitrc" "${xinitrcFile}"
    checkError 'cp "/etc/X11/xinit/xinitrc" "${xinitrcFile}"'

    chown -R ${USERNAME} "${xinitrcFile}"
    checkError 'chown -R ${USERNAME} "${xinitrcFile}"'

    grep -qxF 'exec openbox-session' ${xinitrcFile} || echo 'exec openbox-session' >> ${xinitrcFile}
    checkError "grep -qxF 'exec openbox-session' ${xinitrcFile} || echo 'exec openbox-session' >> ${xinitrcFile}"

    mkdir -p "${configPath}/openbox"
    checkError 'mkdir -p "${configPath}/openbox"'

    cp -a "/etc/xdg/openbox/" "${homePath}/.config/"
    checkError 'cp -a "/etc/xdg/openbox/" "${homePath}/.config/"'

    chown -R ${USERNAME} "${configPath}"
    checkError 'chown -R ${USERNAME} "${configPath}"'
}

installDocker() {
    if [ "${STACK,,}" = "docker" ]; then
        pacman -S --noconfirm fuse-overlayfs bridge-utils docker docker-compose
        checkError "pacman -S --noconfirm fuse-overlayfs bridge-utils docker docker-compose"

        if [ ! $(getent group docker) ]; then
            groupadd docker
            checkError "groupadd docker"
        fi
        
        usermod -aG docker "${USERNAME}"
        checkError 'usermod -aG docker "${USERNAME}"'
        
        sg docker -c 'sudo systemctl start docker.service'
        sg docker -c 'sudo systemctl enable docker.service'
    fi
}

installMono() {
    if [ "${STACK,,}" = "mono" ]; then
        pacman -S --noconfirm mono onboard
        checkError "pacman -S --noconfirm mono onboard"
    fi
}

installFonts() {
    if [ "${STACK,,}" = "mono" ]; then
        local userLocalPath="/home/${USERNAME}/.local"
        local fontsPath="$userLocalPath/share/fonts/"
        mkdir -p "$fontsPath"
        checkError "mkdir -p $fontsPath"

        cp "$ASSETS_DIR/fonts/"* "$fontsPath"
        checkError "cp $ASSETS_DIR/fonts/* $fontsPath"

        chown -R ${USERNAME} "$userLocalPath"
        checkError "chown -R ${USERNAME} $userLocalPath"
    fi
}

setHostname() {
    hostnameFile="/etc/hostname"

    if [ -f ${hostnameFile} ]; then 
        rm -f ${hostnameFile}
        checkError "rm -f ${hostnameFile}"
    fi

    touch ${hostnameFile}
    checkError "touch ${hostnameFile}"

    echo ${DEVID} >> ${hostnameFile}
}

prepareUserScripts() {
    scriptsPath="/home/${USERNAME}/startup"
    configFile="${scriptsPath}/env.conf"
    useDocker=true
    bashrcFile="/home/${USERNAME}/.bashrc"
    autoupdateScriptName=autoupdate.sh
    srcAutoupdateScript="$ASSETS_DIR/$autoupdateScriptName"
    destAutoupdateLocalScript="${scriptsPath}/${autoupdateScriptName}"

    if [ ! -d ${scriptsPath} ]; then 
        mkdir "${scriptsPath}"
        checkError 'mkdir "${scriptsPath}"'

        chown ${USERNAME} ${scriptsPath}
        checkError "chown ${USERNAME} ${scriptsPath}"
    fi

    if [ ! -f ${configFile} ]; then 
        touch "${configFile}"
        checkError 'touch "${configFile}"'
    fi

    if [ -f "$srcAutoupdateScript" ]; then 
        cp "${srcAutoupdateScript}" "${destAutoupdateLocalScript}"
        checkError 'cp "${srcAutoupdateScript}" "${destAutoupdateLocalScript}"'

        chown ${USERNAME} "${destAutoupdateLocalScript}"
        checkError 'chown ${USERNAME} "${destAutoupdateLocalScript}"'
    fi

    chown ${USERNAME} ${configFile}
    checkError "chown ${USERNAME} ${configFile}"

    chmod 755 ${configFile}
    checkError "chmod 755 ${configFile}"

    if [ "${STACK,,}" != "docker" ]; then useDocker=false; fi

    echo "PASSWORD=${PASSWD,}" >> ${configFile}
    echo "IP=${DEVIP}" >> ${configFile}
    echo "GTW=${DEVGTW}" >> ${configFile}
    echo "PROJECT_NAME=${APP,}" >> ${configFile}
    echo "WORKSPACE_FOLDER=~/workspace/${APP,,}" >> ${configFile}
    if [ "${APP,,}" = "neuron" ]; then echo "TTY_SYMLINK_ALIAS=ttyEUBOX" >> ${configFile}; fi
    echo "USE_DOCKER=${useDocker}" >> ${configFile}
    echo "AUTOUPDATE_SCRIPT_PATH=${destAutoupdateLocalScript}" >> ${configFile}
    echo "INSTALL_LOG=/home/${USERNAME}/.setuparch.log" >> ${configFile}

    if [ -f ${scriptsPath}/3.app.sh ]; then
        rm ${scriptsPath}/3.app.sh
        checkError "rm ${scriptsPath}/3.app.sh"
    fi

    cp ${SCRIPTS_DIR}/3.app.sh ${scriptsPath}/
    checkError 'cp ${SCRIPTS_DIR}/3.app.sh ${scriptsPath}/'

    chown ${USERNAME} ${scriptsPath}/3.app.sh
    checkError "chown ${USERNAME} ${scriptsPath}/3.app.sh"

    chmod 755 ${scriptsPath}/3.app.sh
    checkError "chmod 755 ${scriptsPath}/3.app.sh"

    grep -qxF "source ${scriptsPath}/3.app.sh" ${bashrcFile} || echo "source ${scriptsPath}/3.app.sh" >> ${bashrcFile}
    checkError "grep -qxF 'source ${scriptsPath}/3.app.sh' ${bashrcFile} || echo 'source ${scriptsPath}/3.app.sh' >> ${bashrcFile}"
}

cleanup() {
    rm -r "${HOME}/archinstall"
    checkError 'rm -r "${HOME}/archinstall"'
}

# 
clear
#showHeader "Setup finalization"

installOpenbox
installDocker
installMono
installFonts
setHostname

prepareUserScripts

cleanup
exit
