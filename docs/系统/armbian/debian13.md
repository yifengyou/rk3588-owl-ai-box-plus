# Armbian Debian 13 trixie

## 基础软件安装


```shell

apt-get update
apt-get install -y vim lrzsz tmux build-essential \
  command-not-found systemd-timesyncd lm-sensors net-tools \
  apt-file

ssh-keygen -t rsa
```


## 安装docker

```shell

curl -fsSL https://get.docker.com -o get-docker.sh
bash get-docker.sh

docker run hello-world
docker run -it --rm debian:12 /bin/bash


systemctl status docker

docker ps

```


## 安装kvm虚拟机


```shell

apt install -y qemu-kvm libvirt-daemon-system \
  libvirt-clients bridge-utils virtinst \
  qemu-efi-aarch64 ovmf qemu-utils ipxe-qemu

virt-install \
  --name my-vm \
  --memory 2048 \
  --vcpus 2 \
  --disk path=test.qcow2,size=20,format=qcow2,bus=virtio \
  --cdrom /tmp/123.iso \
  --osinfo generic \
  --graphics none \
  --console pty,target_type=serial \
  --accelerate
  

qemu-system-aarch64 \
  -m 2048 \
  -cpu host \
  -accel kvm \
  -drive file=/tmp/rootfs.qcow2,format=qcow2 \
  -netdev user,id=net0 -device virtio-net-device,netdev=net0 \
  -nographic
  
  
qemu-system-aarch64 \
  -M virt \
  -cpu host \
  -accel kvm \
  -m 512 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
  -drive file=test.img,format=qcow2 \
  -nographic \

```











