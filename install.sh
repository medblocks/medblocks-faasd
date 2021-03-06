#!/bin/bash

export OWNER="openfaas"
export REPO="faasd"
export medblocksversion="master"

faasd_path="/var/lib/faasd"
medblocks_path="$faasd_path/medblocks"
faasd_user="1007"

if [ ! $medblocksversion ]; then
  echo "Finding medblocks-faasd latest version from GitHub"
  medblocksversion=$(curl -sI https://github.com/medblocks/medblocks-faasd/releases/latest | grep -i "location:" | awk -F"/" '{ printf "%s", $NF }' | tr -d '\r')
fi

if [ ! $medblocksversion ]; then
  echo "Failed while attempting to get medblocks-faasd latest version"
  exit 1
fi

echo "
            _ _   _         _       
_____ ___ _| | |_| |___ ___| |_ ___ 
|     | -_| . | . | | . |  _| '_|_ -|
|_|_|_|___|___|___|_|___|___|_,_|___|
  $medblocksversion

Thank you for trying out medblocks-faasd.
For more information and support, visit https://medblocks.org.
"
read -p "Domain name (for HTTPS. Press Enter to skip): " domain

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
  $SUDO curl -fSLs "https://raw.githubusercontent.com/medblocks/medblocks-faasd/${medblocksversion}/init.sql" --output "init.sql"
  $SUDO curl -fSLs "https://raw.githubusercontent.com/medblocks/medblocks-faasd/${medblocksversion}/wal.yml" --output "wal.yml"
  $SUDO curl -fSLs "https://raw.githubusercontent.com/medblocks/medblocks-faasd/${medblocksversion}/Caddyfile.template" --output "Caddyfile"
  $SUDO curl -fSLs "https://raw.githubusercontent.com/medblocks/medblocks-faasd/${medblocksversion}/faasd-docker-compose.yml" --output "docker-compose.yaml"
  $SUDO mkdir -p "$medblocks_path/caddy" "$medblocks_path/postgres"
  echo "Setting route for $domain in Caddyfile";
  $SUDO sed -i "s/example.com/$domain/g" "Caddyfile"
  
  echo "Writing $medblocks_path/postgres/init.sql"
  $SUDO cp "init.sql" "$medblocks_path/postgres/init.sql"
  echo "Writing $medblocks_path/postgres/wal.yml"
  $SUDO cp "wal.yml" "$medblocks_path/postgres/wal.yml"
}

medblocks_postinstall(){
  echo "Setting up faasd user"
  $SUDO groupadd --gid "$faasd_user" faasd
  $SUDO useradd --uid "$faasd_user" --system --no-create-home --gid "$faasd_user" faasd
  echo "Setting up directories for medblocks services"
  $SUDO mkdir -p "$medblocks_path/postgres/data" "$medblocks_path/postgres/run" "$medblocks_path/caddy/data" "$medblocks_path/caddy/config"
  echo "Changing ownership of directories"
  $SUDO chown -R "$faasd_user:$faasd_user" "$medblocks_path/postgres/data" "$medblocks_path/postgres/run" "$medblocks_path/caddy/data" "$medblocks_path/caddy/config"
}

setup_medblocks(){
  cd /tmp/faasd-${version}-installation
  echo "Setting up medblocks"
  copy_extra_files
  medblocks_postinstall
}

setup_faasd() {
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

}

install_faas_cli() {
  echo "Installing faas_cli"
  curl -sLS https://cli.openfaas.com | $SUDO sh
}

install_caddy() {
    arch=$(uname -m)
    case $arch in
    x86_64 | amd64)
      suffix="amd64"
      ;;
    aarch64)
      suffix=-arm64
      ;;
    armv7l)
      suffix=-armv7
      ;;
    *)
      echo "Unsupported architecture $arch"
      exit 1
      ;;
    esac
    curl -sSL "https://github.com/caddyserver/caddy/releases/download/v2.4.1/caddy_2.4.1_linux_${suffix}.tar.gz" | $SUDO tar -xvz -C /usr/bin/ caddy
    $SUDO curl -fSLs https://raw.githubusercontent.com/caddyserver/dist/master/init/caddy.service --output /etc/systemd/system/caddy.service
    
    
    
    $SUDO mkdir -p /etc/caddy
    $SUDO mkdir -p /var/lib/caddy
    
    if $(id caddy >/dev/null 2>&1); then
      echo "User caddy already exists."
    else
      $SUDO useradd --system --home /var/lib/caddy --shell /bin/false caddy
    fi
    echo "Writing /etc/caddy/Caddyfile";
    $SUDO cp "/tmp/faasd-${version}-installation/Caddyfile" "/etc/caddy/Caddyfile"
    $SUDO chown --recursive caddy:caddy /var/lib/caddy
    $SUDO chown --recursive caddy:caddy /etc/caddy

    $SUDO systemctl enable caddy
    $SUDO systemctl start caddy

}

verify_system
install_required_packages

$SUDO /sbin/sysctl -w net.ipv4.conf.all.forwarding=1
echo "net.ipv4.conf.all.forwarding=1" | $SUDO tee -a /etc/sysctl.conf

install_cni_plugins
install_containerd
# install_faas_cli
setup_faasd
setup_medblocks

echo "Installing medblocks-faasd"
$SUDO /usr/local/bin/faasd install
echo "Setting up Caddy"
install_caddy
echo "Setup done. It might take some time to pull all the containers. Check the status with the command above."