#!/bin/bash
 
pacman -Sy --noconfirm --needed git glibc
git clone https://github.com/fertecsupport/fenice.git $HOME/neuron
 
cd $HOME/neuron
exec ./archinstall.sh neuron docker neuron "$1"
