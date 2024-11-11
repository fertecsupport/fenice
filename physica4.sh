#!/bin/bash

pacman -Sy --noconfirm --needed git glibc
git clone https://github.com/aferretti/fenice.git

cd $HOME/fenice
exec ./archinstall.sh fenice mono physica4