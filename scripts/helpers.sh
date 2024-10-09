#!/usr/bin/env bash

showHeader() {
    printf "*****************************************************\n"
    printf "* \n"
    printf "* $1\n"    
    printf "* \n"
    printf "*****************************************************\n"
}

showInfo() {
    if [ -n "$1" ]; then echo "$1"; fi
}

saveLog() {
    messageToLog="$1"
    printf "%s\n" "$messageToLog" | tee -a "${INSTALL_LOG}"
}

saveLogAndExit() {
    saveLog "$1"
    exit
}

checkError() {
    if [ $? -ne 0 ]; then
        if [ -n "$1" ]; then 
            errorMessage="$1"
        else
            errorMessage="Errore non specificato"
        fi

        saveLog "$errorMessage"
        if [ -z $2 ]; then exit 1; fi
    fi
}

waitForInput() {
    printf "Premere un tasto per continuare..."
    read -n 1 -s
}