#!/bin/bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright © 2019 ANSSI. All rights reserved.

set -eu -o pipefail

# Set appropriate hostname
echo " [*] Setup hostname to: '${HOSTNAME}'..."
HOSTNAME="ipsec-gw"
hostnamectl set-hostname "${HOSTNAME}"
echo "${HOSTNAME}" > /etc/hostname
echo "127.0.0.1 ${HOSTNAME}" >> /etc/hosts

echo " [*] Fix networkd configuration..."
for f in "50-vagrant-ens7.network" "99-dhcp.network"; do
    install -v -o 0 -g 0 -m 0644 "/vagrant/networkd/${f}" "/etc/systemd/network/${f}"
done

echo " [*] Restart systemd-networkd & systemd-resolved services..."
systemctl restart systemd-networkd systemd-resolved

# Update both packages index and installed packages
apt-get -y -q update
apt-get -y -q dist-upgrade

# Install:
#   - strongSwan (with swanctl utilities and systemd interfacing)
#   - nftables (firewall)
#   - nginx (update server)
apt-get -y -q install \
    charon-systemd \
    nftables \
    nginx

echo " [*] Install the dummy IPsec PKI..."
install -v -o 0 -g 0 -m 0644 "/vagrant/pki/root-ca.cert.pem" "/etc/swanctl/x509ca/root-ca.cert.pem"
install -v -o 0 -g 0 -m 0644 "/vagrant/pki/server.cert.pem"  "/etc/swanctl/x509/server.cert.pem"
install -v -o 0 -g 0 -m 0600 "/vagrant/pki/server.key.pem"   "/etc/swanctl/private/server.key.pem"

echo " [*] Install the dummy IPsec PKI..."
install -v -o 0 -g 0 -m 0644 "/vagrant/strongswan/office_net.conf" "/etc/swanctl/conf.d/office_net.conf"

echo " [*] Create strongSwan user..."
install -v -o 0 -g 0 -m 755 -d "/etc/sysusers.d"
install -v -o 0 -g 0 -m 644 "/vagrant/strongswan/sysusers.conf" "/etc/sysusers.d/strongswan.conf"
systemd-sysusers strongswan.conf

echo " [*] Install strongSwan unit drop-in..."
install -v -o 0 -g 0 -m 755 -d "/etc/systemd/system/strongswan.service.d"
install -v -o 0 -g 0 -m 644 "/vagrant/strongswan/security.conf" \
    "/etc/systemd/system/strongswan.service.d/security.conf"

echo " [*] Update strongSwan configuration..."
sed -i \
    's|# socket = unix://${piddir}/|socket = unix:///run/ipsec/|g' \
    "/etc/strongswan.d/swanctl.conf" \
    "/etc/strongswan.d/charon/vici.conf"
chown -R root:ipsec \
    "/etc/strongswan.conf" \
    "/etc/strongswan.d" \
    "/etc/swanctl"
chmod -R ug+rX \
    "/etc/strongswan.conf" \
    "/etc/strongswan.d" \
    "/etc/swanctl"
plugins=(
    "aesni.conf" "agent.conf" "bypass-lan.conf" "connmark.conf" "counters.conf"
    "dnskey.conf" "eap-mschapv2.conf" "fips-prf.conf" "gcm.conf" "gmp.conf"
    "md5.conf" "mgf1.conf" "pgp.conf" "rc2.conf" "sha1.conf" "sshkey.conf"
    "xauth-generic.conf" "xcbc.conf"
)
for p in "${plugins[@]}"; do
    sed -i 's/load = yes/# load = yes/g' "/etc/strongswan.d/charon/${p}"
done

echo " [*] Install nftables rules..."
install -v -o 0 -g 0 -m 0600 "/vagrant/nft/apply.nft" "/etc/nftables.conf"
install -v -o 0 -g 0 -m 0600 "/vagrant/nft.ipsec0/rules.nft" "/etc/nftables.ipsec0.conf"

echo " [*] Enable nftables..."
systemctl enable --now nftables.service

echo " [*] Install Network namespace & XFRM interface unit..."
install -v -o 0 -g 0 -m 644 "/vagrant/strongswan/netns@.service" "/etc/systemd/system/netns@.service"
systemctl daemon-reload
systemctl enable --now netns@ipsec0.service

echo " [*] Restart strongSwan service..."
systemctl daemon-reload
systemctl restart strongswan.service

echo " [*] Install nginx configuration for updates..."
for f in "update.clip-os.org.conf" "update.clip-os.org-key.pem" "update.clip-os.org.pem"; do
    install -v -o 0 -g 0 -m 0644 "/vagrant/nginx/${f}" "/etc/nginx/conf.d/${f}"
done

echo " [*] Install nginx unit drop-in..."
install -v -o 0 -g 0 -m 755 -d "/etc/systemd/system/nginx.service.d"
install -v -o 0 -g 0 -m 644 "/vagrant/ipsec0.conf" \
    "/etc/systemd/system/nginx.service.d/ipsec0.conf"

echo " [*] Restart nginx service..."
systemctl daemon-reload
systemctl restart nginx.service

echo " [*] Done"

# vim: set ts=4 sts=4 sw=4 et ft=sh:
