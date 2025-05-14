#!/usr/bin/env bash

# Caricamento file env.conf
source ${HOME}/startup/env.conf

PROJECT_NAME_LOWERCASE="${PROJECT_NAME,,}"

waitForInput() {
    printf "Premere un tasto per cleanup e riavvio..."
    read -n 1 -s
}

saveLog() {
    messageToLog="$@"
    printf "%s\n" "$messageToLog" | tee -a "${INSTALL_LOG}"
}

saveLogAndExit() {
    saveLog "$1"
    exit
}

getEthName() {
    ETHNAME="eu-lan"
    echo ${PASSWORD} | sudo -S nmcli connection modify Wired\ connection\ 1 con-name ${ETHNAME} >> /dev/null
}

setIpAddress() {
    if [ "${PROJECT_NAME,,}" = "neuron" ]; then
        getEthName
        if [ -z ${ETHNAME} ]; then saveLogAndExit "ERROR! No active ethernet interface found"; fi

        echo ${PASSWORD} | sudo -S nmcli connection modify ${ETHNAME} ipv4.addresses "${IP}/24" ipv4.gateway "${GTW}" >> /dev/null
        echo ${PASSWORD} | sudo -S nmcli connection modify ${ETHNAME} ipv4.method manual >> /dev/null
        echo ${PASSWORD} | sudo -S nmcli connection modify ${ETHNAME} connection.autoconnect yes >> /dev/null
    fi
}

cleanupAndReboot() {
    # rimozione della riga che esegue lo startup dal file .bashrc
    bashFile="${HOME}/.bashrc"

    grep -v "source /home/fertec/startup/3.app.sh" ${bashFile} > ${bashFile}2 
    mv ${bashFile}2 ${bashFile}

    # rimozione della cartella contenente gli script di avvio
    if [ -d ${HOME}/startup ]; then rm -r ${HOME}/startup; fi

    # riavvio
    echo ${PASSWORD} | sudo -S reboot >> /dev/null
}

readWritePermits() {
  saveLog
  saveLog "$PROJECT_NAME
COM ports user permits...
"
  saveLog
  sleep 1

  echo ${PASSWORD} | sudo -S usermod -a -G uucp $USER
  echo ${PASSWORD} | sudo -S usermod -a -G tty $USER
}

fontsInstall() {
  saveLog
  saveLog "$PROJECT_NAME
Installing fonts...
"
  saveLog
  sleep 1

  echo ${PASSWORD} | sudo -S pacman -S --noconfirm ttf-dejavu ttf-liberation ttf-droid ttf-ubuntu-font-family noto-fonts
}

desktopEnvInstall() {
  saveLog
  saveLog "$PROJECT_NAME
Installing desktop environment...
"
  saveLog
  sleep 1

  echo ${PASSWORD} | sudo -S pacman -S --noconfirm xorg-server xorg-xinit openbox xterm unclutter xdotool x11vnc xorg-fonts-misc python-xdg xorg-xhost feh

  echo ${PASSWORD} | sudo -S pacman -Syu --noconfirm
  # se da errore su versione glibc obsoleta
  echo ${PASSWORD} | sudo -S pacman -S --noconfirm glibc

  local KEYBOARD_CONF_PATH=/etc/X11/xorg.conf.d/00-keyboard.conf

  ## cultura tastiera in xterm
  echo ${PASSWORD} | sudo -S touch "$KEYBOARD_CONF_PATH"

  if ! grep -q $PROJECT_NAME "$KEYBOARD_CONF_PATH"; then
    saveLog
    saveLog "$PROJECT_NAME
Setting up terminal keyboard locale...
"
    saveLog
    sleep 1

  local TMP_KEYBOARD_CONF=~/.tmp.keyboard.xorg.conf

    echo "# $PROJECT_NAME - xterm keyboard locale
Section \"InputClass\"
    Identifier \"system-keyboard\"
    MatchIsKeyboard \"on\"
    Option \"XkbLayout\" \"it\"
EndSection" | tee $TMP_KEYBOARD_CONF

    echo ${PASSWORD} | sudo -S mv "$TMP_KEYBOARD_CONF" "$KEYBOARD_CONF_PATH"

  fi


  # disabilitare screen sleep

  local XORG_CONF_PATH=/etc/X11/xorg.conf

  echo ${PASSWORD} | sudo -S touch "$XORG_CONF_PATH"

  # disabilita screen sleep

  if ! grep -q $PROJECT_NAME "$XORG_CONF_PATH"; then
    saveLog
    saveLog "$PROJECT_NAME
Disabling screen sleep...
"
    saveLog
    sleep 1
    
    local TMP_CONF=~/.tmp.xorg.conf

    echo "# $PROJECT_NAME - disable screen sleep
Section \"ServerFlags\"
  Option \"StandbyTime\" \"0\"
  Option \"SuspendTime\" \"0\"
  Option \"OffTime\" \"0\"
  Option \"BlankTime\" \"0\"
EndSection" | tee "$TMP_CONF"

    echo ${PASSWORD} | sudo -S mv "$TMP_CONF" "$XORG_CONF_PATH"

  fi

  # impostazione shortcut openbox

  echo ${PASSWORD} | sudo -S mkdir -p ~/.config/openbox
  echo ${PASSWORD} | sudo -S cp -a /etc/xdg/openbox ~/.config/
  
  echo ${PASSWORD} | sudo -S chown -R $USER ~/.config

  ## aggiungo keybinding custom

  if ! grep -q $PROJECT_NAME ~/.config/openbox/rc.xml; then
    saveLog
    saveLog "$PROJECT_NAME
Adding custom keybindings...
"
    saveLog
    sleep 1
    
    echo ${PASSWORD} | sudo -S sed -i -e "s|</keyboard>| \
\
  <!-- $PROJECT_NAME custom keybindings --> \
  <keybind key=\"W-t\"> \
    <action name=\"Execute\"> \
      <command>xterm</command> \
    </action> \
  </keybind> \
  <keybind key=\"F11\"> \
    <action name=\"ToggleFullscreen\" /> \
  </keybind> \
</keyboard>|g" ~/.config/openbox/rc.xml 
  fi

  if ! grep -q $PROJECT_NAME ~/.config/openbox/environment; then
    saveLog
    saveLog "$PROJECT_NAME
Setting up openbox environment...
"
    saveLog
    sleep 1
    
    echo "
# $PROJECT_NAME - openbox environment
export XSOCK=/tmp/.X11-unix
export XAUTH=~/.docker.xauth
export QT_X11_NO_MITSHM=1" | tee -a ~/.config/openbox/environment
  fi

  # openbox autostart

  if ! grep -q $PROJECT_NAME ~/.config/openbox/autostart; then
    saveLog
    saveLog "$PROJECT_NAME
Setting up autostart...
"
    saveLog
    sleep 1
    
    echo "
# $PROJECT_NAME - project autostart
# x11vnc server

if [ -z "\${VNC_PWD}" ]; then
    export VNC_PWD=n3ur0n3
fi

x11vnc -wait 50 -noxdamage -passwd \$VNC_PWD -display :0 -forever -bg 

#esecuzione keyboard linux
# onboard & sleep 2 && dbus-send --type=method_call --dest=org.onboard.Onboard /org/onboard/Onboard/Keyboard org.onboard.Onboard.Keyboard.Hide &

# unclutter -idle 0.1 & 			### altri flag: -grab -root 
(sleep 3s && touch \$XAUTH) &
(sleep 3s && xauth nlist \$DISPLAY | sed -e s/^..../ffff/ | xauth -f ~/.docker.xauth nmerge -) &
$WORKSPACE_FOLDER/start.sh " | tee -a ~/.config/openbox/autostart
  fi

  # avvio openbox

  # appendo l'avvio di sessione openbox se non l'ho già fatto
  if ! grep -q $PROJECT_NAME ~/.xinitrc; then
    saveLog
    saveLog "$PROJECT_NAME
Setting up openbox session...
"
    saveLog
    sleep 1

    echo "# $PROJECT_NAME - avvia lo script per impostare il background al desktop virtuale
local \$FEHBG_SCRIPT = ${WORKSPACE_FOLDER}/feh_bg.sh
if [ -e "\$FEHBG_SCRIPT" ]
then 
  sh \$FEHBG_SCRIPT &
fi

# $PROJECT_NAME - autoavvia sessione openbox
xhost +local:

exec openbox-session " | tee ~/.xinitrc
  fi

  # appendo l'avvio di startx al file se non l'ho già fatto
  if ! grep -q $PROJECT_NAME ~/.bash_profile; then
    saveLog
    saveLog "$PROJECT_NAME
Setting up startx...
"
    saveLog
    sleep 1

    echo "

# $PROJECT_NAME - autoavvia Openbox
#[[ -z \$DISPLAY && \$XDG_VTNR -eq 1 ]] && exec startx -- -nocursor
[[ -z \$DISPLAY && \$XDG_VTNR -eq 1 ]] && exec startx -- -nocursor &> /dev/null # &> /dev/null per nascondere oppure &> ~/.Xoutput per loggare su file

dbus-update-activation-environment --systemd DISPLAY XAUTHORITY " >>  ~/.bash_profile
  fi

  echo ${PASSWORD} | sudo -S mkdir -p ~/.config/onboard
  echo ${PASSWORD} | sudo -S chown -R $USER ~/.config

  touch ~/.config/onboard/settings.conf

  if ! grep -q $PROJECT_NAME ~/.config/onboard/settings.conf; then
    echo "
# $PROJECT_NAME - onboard settings
[Window]
dock-expanded=true
[Layout]
layout-name=Phone
[Theme]
theme-name=Droid
[UniversalAccess]
transparency=50" | tee -a ~/.config/onboard/settings.conf
  fi

  # appendo l'id macchina a .bashrc
  if ! grep -q $PROJECT_NAME ~/.bashrc; then
    saveLog
    saveLog "$PROJECT_NAME
Setting up machine id...
"
    saveLog
    sleep 1

    echo "
cd ${WORKSPACE_FOLDER}

# $PROJECT_NAME - machine id
_deviceid=\$(cat /etc/machine-id)

#ultimi 8 caratteri del deviceid
_charcount=8

${PROJECT_NAME^^}_DEVICE_ID=\${_deviceid:\${#_deviceid}-_charcount:_charcount}

export ${PROJECT_NAME^^}_DEVICE_ID=\${${PROJECT_NAME^^}_DEVICE_ID^^}
" >>  ~/.bashrc
  fi
}

AUTOUPDATE_SERVICE_NAME="$PROJECT_NAME_LOWERCASE-autoupdate.service"
AUTOUPDATE_SCRIPT_FOLDER="/home/$USER/scripts/"
AUTOUPDATE_SCRIPT_FULLPATH="${AUTOUPDATE_SCRIPT_FOLDER}$PROJECT_NAME_LOWERCASE-autoupdate.sh"

udevRules() {
  local RULES_PATH="/etc/udev/rules.d/99-"$PROJECT_NAME_LOWERCASE".rules"
  touch "$RULES_PATH"

  if ! grep -q $PROJECT_NAME "$RULES_PATH"; then
    saveLog
    saveLog "$PROJECT_NAME
Setting up udev rules...
"
    saveLog
    sleep 1
    
    local TMP_RULES=~/.tmp.99.rules

    echo "# $PROJECT_NAME - crea symlink EUBOX in base al percorso del device (USB1 -> EUBOX1)
KERNELS==\"1-1:1.0\", MODE=\"0660\", SYMLINK+=\"${TTY_SYMLINK_ALIAS}1\"
KERNELS==\"1-2:1.0\", MODE=\"0660\", SYMLINK+=\"${TTY_SYMLINK_ALIAS}2\"
KERNELS==\"1-3:1.0\", MODE=\"0660\", SYMLINK+=\"${TTY_SYMLINK_ALIAS}3\"
KERNELS==\"1-4:1.0\", MODE=\"0660\", SYMLINK+=\"${TTY_SYMLINK_ALIAS}4\"

KERNEL==\"ttyS0\", MODE=\"0660\", SYMLINK+=\"${TTY_SYMLINK_ALIAS}0\"

# $PROJECT_NAME - regola per autoupdate - non compatibile con udiskie
# SUBSYSTEMS==\"usb\", ACTION==\"add\", ENV{SYSTEMD_WANTS}==\"$AUTOUPDATE_SERVICE_NAME\"
" | tee -a "$TMP_RULES"

    echo ${PASSWORD} | sudo -S mv "$TMP_RULES" "$RULES_PATH"

  fi
}

autoupdateServiceInstall() {
	local AUTOUPDATE_SERVICE_DIR=/home/$USER/.config/systemd/user/
	local AUTOUPDATE_SERVICE_PATH="${AUTOUPDATE_SERVICE_DIR}$AUTOUPDATE_SERVICE_NAME"
	
	mkdir -p "$AUTOUPDATE_SERVICE_DIR"
  touch "$AUTOUPDATE_SERVICE_PATH"

  if ! grep -q $PROJECT_NAME "$AUTOUPDATE_SERVICE_PATH" ; then
    saveLog
    saveLog "$PROJECT_NAME
Setting up autoupdate service...
"
    saveLog
    sleep 1

    echo "# $PROJECT_NAME - servizio invocato da udiskie per l'autoupdate
[Unit]
Description=Triggers $PROJECT_NAME autoupdate when device is mounted

[Service]
Environment=WORKSPACE_FOLDER=\"$WORKSPACE_FOLDER/\" PROJECT_NAME=\"$PROJECT_NAME\"
ExecStart=/usr/bin/udiskie -TFN --no-terminal --event-hook='$AUTOUPDATE_SCRIPT_FULLPATH --event="{event}" --path="{device_presentation}" --device-id="{device_id}" --is-mounted="{is_mounted}" --mount-path="{mount_path}" --id-label="{id_label}" --mount-paths="{mount_paths}"'

[Install]
WantedBy=default.target
" | tee -a "$AUTOUPDATE_SERVICE_PATH"

    systemctl --user daemon-reload
    systemctl --user enable "$AUTOUPDATE_SERVICE_NAME"
  fi
}

autoupdateScriptInstall() {
  SOURCE_AUTOUPDATE_SCRIPT_FULLPATH="$AUTOUPDATE_SCRIPT_PATH"

  saveLog
  saveLog "$PROJECT_NAME
Setting up script, checking path $SOURCE_AUTOUPDATE_SCRIPT_FULLPATH...
"
  saveLog
  sleep 1

  if [ -e "$SOURCE_AUTOUPDATE_SCRIPT_FULLPATH" ]
  then
    if [ ! -d "$AUTOUPDATE_SCRIPT_FOLDER" ]
    then 
      mkdir -p "$AUTOUPDATE_SCRIPT_FOLDER"
    fi

    cp "$SOURCE_AUTOUPDATE_SCRIPT_FULLPATH" "$AUTOUPDATE_SCRIPT_FULLPATH"

    chmod +x "$AUTOUPDATE_SCRIPT_FULLPATH"
  fi
}

## permessi utente di lettura/scrittura su porte COM
readWritePermits

## installazione fonts
fontsInstall

## installazione desktop
desktopEnvInstall

## regole UDEV
udevRules

## servizio autoupdate
autoupdateServiceInstall
autoupdateScriptInstall

# Impostazione indirizzo IP statico
setIpAddress
clear

# Pulizia e riavvio
cleanupAndReboot
