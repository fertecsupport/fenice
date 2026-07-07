#!/bin/bash
 
pacman -Sy --noconfirm --needed git glibc
git clone https://github.com/fertecsupport/fenice.git $HOME/neuron
 
cd $HOME/neuron
exec ./archinstall.sh neuron docker "${3:-neuron}" "$1" "$2"
