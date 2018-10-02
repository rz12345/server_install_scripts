#!/bin/bash

# first make executable with chmod +x filename.sh
# then run with ./filename.sh
# or automated with ./filename.sh --version "version#"
# ./filename.sh -v elkversion

# set default variables
elkversion="6.4.1"

# get os from system
os=`cat /etc/*release | grep ^ID= | cut -d= -f2 | sed 's/\"//g'`

# get os family from system
if [ $os = debian ] || [ $os = fedora ]; then
	os_family=$os
else
	os_family=`cat /etc/*release | grep ^ID_LIKE= | cut -d= -f2 | sed 's/\"//g' | cut -d' ' -f2`
fi

# Get script arguments for non-interactive mode
while [ "$1" != "" ]; do
    case $1 in
        -v | --elkversion )
            shift
            elkversion="$1"
            ;;
esac
    shift
done

# set more variables for download links
elkversion_major=`echo "$elkversion" | cut -d. -f-2`
elkversion_majormajor=`echo "$elkversion" | cut -d. -f-1`

# install wazuh
if [ $os_family = debian ]; then

	# install dependencies
	apt -y install curl apt-transport-https lsb-release

	# install JRE8
	if [ $os = debian ]; then
		echo "deb http://ppa.launchpad.net/webupd8team/java/ubuntu xenial main" | tee /etc/apt/sources.list.d/webupd8team-java.list
		echo "deb-src http://ppa.launchpad.net/webupd8team/java/ubuntu xenial main" | tee -a /etc/apt/sources.list.d/webupd8team-java.list
		apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys EEA14886	
        elif [ $os = ubuntu ]; then
    		add-apt-repository -y ppa:webupd8team/java
		echo oracle-java8-installer shared/accepted-oracle-license-v1-1 select true | /usr/bin/debconf-set-selections
  	fi
    # add elastic repository
    curl -s https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add -
    echo "deb https://artifacts.elastic.co/packages/${elkversion_majormajor}.x/apt stable main" | tee /etc/apt/sources.list.d/elastic-${elkversion_majormajor}.x.list
   
    # install oracle java8, elasticsearch, logstash, and kibana
    apt update
    apt -y install oracle-java8-installer elasticsearch=${elkversion} logstash=1:${elkversion}-1 kibana=${elkversion}

elif [ $os_family = fedora ]; then

	# install JRE8
	curl -Lo jre-8-linux-x64.rpm --header "Cookie: oraclelicense=accept-securebackup-cookie" "https://download.oracle.com/otn-pub/java/jdk/8u181-b13/96a7b8442fe848ef90c96a2fad6ed6d1/jre-8u181-linux-x64.rpm"
        yum -y install jre-8-linux-x64.rpm
        rm -f jre-8-linux-x64.rpm
    
	# add elk repository and GPG key
	rpm --import https://packages.elastic.co/GPG-KEY-elasticsearch
	
	cat <<-EOF >/etc/yum.repos.d/elastic.repo
	[elasticsearch-${elkversion_majormajor}.x]
	name=Elasticsearch repository for ${elkversion_majormajor}.x packages
	baseurl=https://artifacts.elastic.co/packages/${elkversion_majormajor}.x/yum
	gpgcheck=1
	gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
	enabled=1
	autorefresh=1
	type=rpm-md
	EOF

	# install elasticsearch, logstash, and kibana
	yum -y install elasticsearch-${elkversion} logstash-${elkversion} kibana-${elkversion}
fi

# enable elk services for systemd
systemctl daemon-reload
systemctl enable elasticsearch.service
systemctl start elasticsearch.service
systemctl enable logstash.service
systemctl start logstash.service
systemctl enable kibana.service
systemctl start kibana.service
