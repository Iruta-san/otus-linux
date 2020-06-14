#!/bin/bash

yum install -y http://download.zfsonlinux.org/epel/zfs-release.el7_8.noarch.rpm
gpg --quiet --with-fingerprint /etc/pki/rpm-gpg/RPM-GPG-KEY-zfsonlinux
yum install -y --disablerepo="zfs" --enablerepo="zfs-kmod" zfs

