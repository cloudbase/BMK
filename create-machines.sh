#!/bin/bash

set -xe

install_dependencies() {
    which virsh || (apt update && apt install -y qemu-kvm libvirt-daemon-system)
    kvm-ok

    which pip || apt install -y python3-pip
    which ipmitool || apt install -y ipmitool
    which vbmc || apt install -y pkg-config libvirt-dev ipmitool && pip install --break-system-packages virtualbmc 
}

define_network() {
    virsh net-destroy default || true; virsh net-undefine default || true
    
    virsh net-define libvirt/tink_network.xml
    virsh net-autostart tink_network
    virsh net-start tink_network || true
}

prepare_iptables() {
    iptables -t nat -A POSTROUTING -s 192.168.56.0/24 ! -d 192.168.56.0/24 -p udp -j MASQUERADE --to-ports 1-65535
    iptables -t nat -A POSTROUTING -s 192.168.56.0/24 ! -d 192.168.56.0/24 -p icmp -j MASQUERADE
    iptables -t nat -A POSTROUTING -s 192.168.56.0/24 ! -d 192.168.56.0/24 -p tcp -j MASQUERADE --to-ports 1-65535
}

create_controller() {
    [ -f /var/lib/libvirt/images/controller-test.qcow2 ] || \
        wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img \
        -O /var/lib/libvirt/images/controller-test.qcow2
    qemu-img resize /var/lib/libvirt/images/controller-test.qcow2 +30G
    cp libvirt/cloud-init.iso /var/lib/libvirt/images/cloud-init.iso
    virsh define libvirt/controller.xml
}

create_machine() {
    virsh destroy $1 || true
    virsh undefine $1 || true
    qemu-img create -f qcow2 /var/lib/libvirt/images/$1.qcow2 100G
    qemu-img create -f qcow2 /var/lib/libvirt/images/$1-disk2.qcow2 200G
    virsh define libvirt/$1.xml
}

create_bmc_machine() {
    vbmc add $1 --port $2 --username admin --password admin
    vbmc show $1
    vbmc start $1
    ipmitool -I lanplus -U admin -P admin -H 127.0.0.1 -p $2 power status
}

main() {
    which virsh || install_dependencies
    define_network

    (iptables -S -t nat | grep -i '192.168.56.0/24') || prepare_iptables

    pkill -f vbmcd || true
    rm -rf ~/.vbmc/
    vbmcd

    create_controller || true

    create_machine machine1
    create_bmc_machine machine1 623

    create_machine machine2
    create_bmc_machine machine2 624

    create_machine machine3
    create_bmc_machine machine3 625

    # create_machine machine4
    # create_bmc_machine machine4 626
}

set -euxo pipefail
main
echo "ALL DONE!"
