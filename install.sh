#!/bin/bash

export OWNER="openfaas"
export REPO="faasd"

if [ ! $medblocksversion ]; then
  echo "Finding medblocks-faasd latest version from GitHub"
  medblocksversion=$(curl -sI https://github.com/medblocks/medblocks-faasd/releases/latest | grep -i "location:" | awk -F"/" '{ printf "%s", $NF }' | tr -d '\r')
fi

if [ ! $medblocksversion ]; then
  echo "Failed while attempting to get medblocks-faasd latest version"
  exit 1
fi

echo "
Thank you for trying out medblocks.
For more information and support, visit https://medblocks.org
            _ _   _         _       
_____ ___ _| | |_| |___ ___| |_ ___ 
|     | -_| . | . | | . |  _| '_|_ -|
|_|_|_|___|___|___|_|___|___|_,_|___|

$medblocksversion                          
"
read -p "Enter domain name (for HTTPS. Press Enter to skip): " domain

if [ ! $domain ]; then
echo "No domain name for HTTPS provided. Traffic will be served only from port 80."
domain=':80'
fi

version=""
echo "Finding openFaaS latest version from GitHub"
version=$(curl -sI https://github.com/$OWNER/$REPO/releases/latest | grep -i "location:" | awk -F"/" '{ printf "%s", $NF }' | tr -d '\r')
echo "$version"


if [ ! $version ]; then
  echo "Failed while attempting to get faasd latest version"
  exit 1
fi



SUDO=sudo
if [ "$(id -u)" -eq 0 ]; then
  SUDO=
fi

verify_system() {
  if ! [ -d /run/systemd ]; then
    fatal 'Can not find systemd to use as a process supervisor for faasd'
  fi
}

has_yum() {
  [ -n "$(command -v yum)" ]
}

has_apt_get() {
  [ -n "$(command -v apt-get)" ]
}

install_required_packages() {
  if $(has_apt_get); then
    $SUDO apt-get update -y
    $SUDO apt-get install -y curl runc bridge-utils
  elif $(has_yum); then
    $SUDO yum check-update -y
    $SUDO yum install -y curl runc
  else
    fatal "Could not find apt-get or yum. Cannot install dependencies on this OS."
    exit 1
  fi
}

install_cni_plugins() {
  cni_version=v0.8.5
  suffix=""
  arch=$(uname -m)
  case $arch in
  x86_64 | amd64)
    suffix=amd64
    ;;
  aarch64)
    suffix=arm64
    ;;
  arm*)
    suffix=arm
    ;;
  *)
    fatal "Unsupported architecture $arch"
    ;;
  esac

  $SUDO mkdir -p /opt/cni/bin
  curl -sSL https://github.com/containernetworking/plugins/releases/download/${cni_version}/cni-plugins-linux-${suffix}-${cni_version}.tgz | $SUDO tar -xvz -C /opt/cni/bin
}

install_containerd() {
  arch=$(uname -m)
  case $arch in
  x86_64 | amd64)
    curl -sLSf https://github.com/containerd/containerd/releases/download/v1.3.7/containerd-1.3.7-linux-amd64.tar.gz | $SUDO tar -xvz --strip-components=1 -C /usr/local/bin/
    ;;
  armv7l)
    curl -sSL https://github.com/alexellis/containerd-arm/releases/download/v1.3.5/containerd-1.3.5-linux-armhf.tar.gz | $SUDO tar -xvz --strip-components=1 -C /usr/local/bin/
    ;;
  aarch64)
    curl -sSL https://github.com/alexellis/containerd-arm/releases/download/v1.3.5/containerd-1.3.5-linux-arm64.tar.gz | $SUDO tar -xvz --strip-components=1 -C /usr/local/bin/
    ;;
  *)
    fatal "Unsupported architecture $arch"
    ;;
  esac

  $SUDO systemctl unmask containerd || :
  $SUDO curl -SLfs https://raw.githubusercontent.com/containerd/containerd/v1.3.5/containerd.service --output /etc/systemd/system/containerd.service
  $SUDO systemctl enable containerd
  $SUDO systemctl start containerd

  sleep 5
}

copy_extra_files(){
  faasd_path="/var/lib/faasd"
  $SUDO mkdir -p "$faasd_path"
  echo "Writing $faasd_path/Caddyfile";
  $SUDO sed "s/example.com/$domain/g" Caddyfile > "$faasd_path/Caddyfile"
  echo "Writing $faasd_path/init.sql"
  $SUDO cp "init.sql" "$faasd_path/init.sql"
  echo "Writing $faasd_path/wal.yml"
  $SUDO cp "wal.yml" "$faasd_path/wal.yml"
}

install_faasd() {
  arch=$(uname -m)
  case $arch in
  x86_64 | amd64)
    suffix=""
    ;;
  aarch64)
    suffix=-arm64
    ;;
  armv7l)
    suffix=-armhf
    ;;
  *)
    echo "Unsupported architecture $arch"
    exit 1
    ;;
  esac

  $SUDO curl -fSLs "https://github.com/openfaas/faasd/releases/download/${version}/faasd${suffix}" --output "/usr/local/bin/faasd"
  $SUDO chmod a+x "/usr/local/bin/faasd"

  mkdir -p /tmp/faasd-${version}-installation/hack
  cd /tmp/faasd-${version}-installation
  
  # Changed to medblocks-faasd docker-compose.yml
  # $SUDO curl -fSLs "https://raw.githubusercontent.com/openfaas/faasd/${version}/docker-compose.yaml" --output "docker-compose.yaml"

  echo "Setting up faasd"
  $SUDO curl -fSLs "https://raw.githubusercontent.com/openfaas/faasd/${version}/prometheus.yml" --output "prometheus.yml"
  $SUDO curl -fSLs "https://raw.githubusercontent.com/openfaas/faasd/${version}/resolv.conf" --output "resolv.conf"
  $SUDO curl -fSLs "https://raw.githubusercontent.com/openfaas/faasd/${version}/hack/faasd-provider.service" --output "hack/faasd-provider.service"
  $SUDO curl -fSLs "https://raw.githubusercontent.com/openfaas/faasd/${version}/hack/faasd.service" --output "hack/faasd.service"
  
  echo "Setting up medblocks-faasd"
  # write medblocks files
  $SUDO curl -fSLs "https://raw.githubusercontent.com/medblocks/medblocks-faasd/${medblocksversion}/init.sql" --output "init.sql"
  $SUDO curl -fSLs "https://raw.githubusercontent.com/medblocks/medblocks-faasd/${medblocksversion}/wal.yml" --output "wal.yml"
  $SUDO curl -fSLs "https://raw.githubusercontent.com/medblocks/medblocks-faasd/${medblocksversion}/Caddyfile" --output "Caddyfile"
  $SUDO curl -fSLs "https://raw.githubusercontent.com/medblocks/medblocks-faasd/${medblocksversion}/faasd-docker-compose.yml" --output "docker-compose.yaml"
  copy_extra_files
  
  $SUDO /usr/local/bin/faasd install
}

install_faas_cli() {
  curl -sLS https://cli.openfaas.com | $SUDO sh
}

verify_system
install_required_packages

$SUDO /sbin/sysctl -w net.ipv4.conf.all.forwarding=1
echo "net.ipv4.conf.all.forwarding=1" | $SUDO tee -a /etc/sysctl.conf

install_cni_plugins
install_containerd
install_faas_cli
install_faasd
# install_caddy