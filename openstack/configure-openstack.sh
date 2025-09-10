#!/bin/bash


set -xe

export KUBECONFIG=~/kub-poc.kubeconfig

helm osh wait-for-pods openstack

source ~/openstack-client/bin/activate

rand_suffix=$(dd of=/tmp/rand if=/dev/random bs=1M count=1 && md5sum /tmp/rand | awk '{print $1}')

openstack --os-cloud openstack_helm quota set --ram 262144
openstack --os-cloud openstack_helm quota set --cores 200
openstack --os-cloud openstack_helm flavor create --ram 32768 --disk 40 --vcpus 16 m1.sylva
openstack --os-cloud openstack_helm key create sylva > sylva.pem

openstack --os-cloud openstack_helm net show private || openstack --os-cloud openstack_helm net create private
openstack --os-cloud openstack_helm subnet show private || openstack --os-cloud openstack_helm subnet create private --network private --subnet-range 10.5.0.0/24 --dns-nameserver 8.8.8.8
openstack --os-cloud openstack_helm router create router
openstack --os-cloud openstack_helm router add subnet router private

openstack --os-cloud openstack_helm net create public --external --provider-network-type flat --provider-physical-network public
openstack --os-cloud openstack_helm subnet create public --network public --subnet-range 192.168.56.0/24 --no-dhcp --allocation-pool start=192.168.56.189,end=192.168.56.200

openstack --os-cloud openstack_helm router set --external-gateway public router

openstack --os-cloud openstack_helm security group rule create default --protocol udp
openstack --os-cloud openstack_helm security group rule create default --protocol tcp
openstack --os-cloud openstack_helm security group rule create default --protocol icmp
openstack --os-cloud openstack_helm security group rule create default --protocol udp --egress
openstack --os-cloud openstack_helm security group rule create default --protocol tcp --egress
openstack --os-cloud openstack_helm security group rule create default --protocol icmp --egress

openstack --os-cloud openstack_helm server create --image 'Cirros 0.6.2 64-bit' --flavor m1.tiny --network private --boot-from-volume 1 cirros-$rand_suffix

[ -f noble-server-cloudimg-amd64.img ] || \
  wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

openstack --os-cloud openstack_helm image create ubuntu-noble --disk-format qcow2 --container-format bare --file noble-server-cloudimg-amd64.img
openstack --os-cloud openstack_helm server create --image 'ubuntu-noble' --flavor m1.sylva --network private ubuntu-sylva --key sylva

[ -f flatcar_production_openstack_image.img ] || \
  wget https://alpha.release.flatcar-linux.net/amd64-usr/current/flatcar_production_openstack_image.img

openstack --os-cloud openstack_helm image create flatcar-alpha --disk-format qcow2 --container-format bare --file flatcar_production_openstack_image.img
openstack --os-cloud openstack_helm server create --image 'flatcar-alpha' --flavor m1.sylva --network private flatcar-alpha --key sylva

openstack --os-cloud openstack_helm floating ip create --floating-ip-address 192.168.56.192 --subnet public public
openstack --os-cloud openstack_helm server add floating ip ubuntu-sylva 192.168.56.192

openstack --os-cloud openstack_helm floating ip create --floating-ip-address 192.168.56.195 --subnet public public
openstack --os-cloud openstack_helm server add floating ip flatcar-alpha 192.168.56.195


until openstack --os-cloud openstack_helm console log show cirros-$rand_suffix | grep -i gocubsgo; do sleep 1 && echo 'Trying again'; done

until nc -w5 -z -v 192.168.56.192 22; do sleep 1; done;
until nc -w5 -z -v 192.168.56.195 22; do sleep 1; done;
# chmod 600 sylva.pem
# ssh -i sylva.pem ubuntu@192.168.56.192

