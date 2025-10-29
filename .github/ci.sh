#!/usr/bin/bash

set -eoux pipefail

df -alh

mkdir data
ls -lhd .

sudo mkdir -p /mnt/my
sudo chown runner:runner /mnt/my
sudo chmod 755 /mnt/my

sudo mount --bind /mnt/my "$PWD"/data

fallocate -l 10G data/10Gfile

ls -alh data
ls -alh /mnt/my

df -alh
