#!/bin/bash
set -ex

INSTALL_DIR="/opt/"

install_app() {
  local remote_tarball="$1/$2"
  local local_tarball="${INSTALL_DIR}/$2"
  local binary="${INSTALL_DIR}/$3"

  # setup `curl` and `wget` silent options if we're running on Jenkins
  local curl_opts="-L"
  local wget_opts=""

  curl_opts="--progress-bar ${curl_opts}"
  wget_opts="--progress=bar:force ${wget_opts}"

  if [ -z "$3" -o ! -f "$binary" ]; then
    # check if we already have the tarball
    # check if we have curl installed
    # download application
    [ ! -f "${local_tarball}" ] && [ $(command -v curl) ] && \
      echo "exec: curl ${curl_opts} ${remote_tarball}" 1>&2 && \
      curl ${curl_opts} "${remote_tarball}" > "${local_tarball}"
    # if the file still doesn't exist, lets try `wget` and cross our fingers
    [ ! -f "${local_tarball}" ] && [ $(command -v wget) ] && \
      echo "exec: wget ${wget_opts} ${remote_tarball}" 1>&2 && \
      wget ${wget_opts} -O "${local_tarball}" "${remote_tarball}"
    # if both were unsuccessful, exit
    [ ! -f "${local_tarball}" ] && \
      echo -n "ERROR: Cannot download $2 with cURL or wget; " && \
      echo "please install manually and try again." && \
      exit 2
    cd "${INSTALL_DIR}" && tar -xzf "$2"
    sudo rm -rf "$local_tarball"
  fi
}

install_mvn() {
  local MVN_VERSION=${M_VERSION:-'2.6.1'}
  MVN_BIN="$(command -v mvn)"
  if [ "$MVN_BIN" ]; then
    local MVN_DETECTED_VERSION="$(mvn --version | head -n1 | awk '{print $3}')"
  fi
  if [ $(version $MVN_DETECTED_VERSION) -lt $(version $MVN_VERSION) ]; then
    local APACHE_MIRROR=${APACHE_MIRROR:-'https://www.apache.org/dyn/closer.lua?action=download&filename='}

    if [ $(command -v curl) ]; then
      local TEST_MIRROR_URL="${APACHE_MIRROR}/maven/maven-3/${MVN_VERSION}/binaries/apache-maven-${MVN_VERSION}-bin.tar.gz"
      if ! curl -L --output /dev/null --silent --head --fail "$TEST_MIRROR_URL" ; then
        # Fall back to archive.apache.org for older Maven
        echo "Falling back to archive.apache.org to download Maven"
        APACHE_MIRROR="https://archive.apache.org/dist"
      fi
    fi

    install_app \
      "${APACHE_MIRROR}/maven/maven-3/${MVN_VERSION}/binaries" \
      "apache-maven-${MVN_VERSION}-bin.tar.gz" \
      "apache-maven-${MVN_VERSION}/bin/mvn"

    MVN_BIN="${INSTALL_DIR}/apache-maven-${MVN_VERSION}/bin/mvn"
	
    sudo wget -O "${INSTALL_DIR}/apache-maven-${MVN_VERSION}/conf/settings.xml" https://mirrors.huaweicloud.com/v1/configurations/maven
  else
    sudo wget -O /etc/maven/settings.xml https://mirrors.huaweicloud.com/v1/configurations/maven
  fi
}

rewrite_apt() {    
  local BACKUP_APT_PATH="/etc/apt/sources.list.bak"
  local TAGET_APT_PATH="/etc/apt/sources.list"
  
  if [ -f "$BACKUP_APT_PATH" ]; then
    echo "The sources had been updated to Huawei."
    exit 0
  fi
  
  if [ ! -f "$TAGET_APT_PATH" ]; then
    echo "Can't find $TAGET_APT_PATH"
    exit 1
  fi
  
  CURRENT_VERSION=`lsb_release -c | awk '{print $2}'`
  
  sudo mv $TAGET_APT_PATH $BACKUP_APT_PATH
  
  if [ "$CURRENT_VERSION" = "xenial" ]
  then
    wget -O /etc/apt/sources.list https://repo.huaweicloud.com/repository/conf/Ubuntu-Ports-bionic.list
  else
    echo "Not support version $CURRENT_VERSION"
    sudo mv $BACKUP_APT_PATH $TAGET_APT_PATH
    exit 1
  fi
  
  sudo apt-get update
}

rewrite_dockerhub_source() {
  sudo mkdir -p /etc/docker
  sudo tee /etc/docker/daemon.json <<- 'EOF'
{
    "registry-mirrors": ["https://6816a425cd5c462ead2499d4b76c02c9.mirror.swr.myhuaweicloud.com"]
}
EOF
  sudo systemctl daemon-reload
  sudo systemctl restart docker
}

rewrite_apt
install_mvn
rewrite_dockerhub_source
