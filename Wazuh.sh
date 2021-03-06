#!/bin/bash

# first make executable with chmod +x filename.sh
# then run with ./filename.sh
# or automated with ./filename.sh --wazuhversion "wazuhversion#" --elkversion "elkversion#" --logstash_server "local"
# ./filename.sh -v wazuhversion -e elkversion -l logstashserver

# set default variables
wazuhversion="3.8.2"
elkversion="6.6.1"
logstash_server="local"

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
        -v | --wazuhversion )
            shift
            wazuhversion="$1"
            ;;
        -e | --elkversion )
            shift
            elkversion="$1"
            ;;
        -l | --logstash_server )
            shift
            logstash_server="$1"
            ;;
esac
    shift
done

# set more variables for download links
wazuhversion_major=`echo "$wazuhversion" | cut -d. -f-2`
wazuhversion_majormajor=`echo "$wazuhversion" | cut -d. -f-1`
elkversion_major=`echo "$elkversion" | cut -d. -f-2`
elkversion_majormajor=`echo "$elkversion" | cut -d. -f-1`

# install wazuh
if [ $os_family = debian ]; then

	# install dependencies
	apt -y install curl apt-transport-https lsb-release

	#create symlink for python if /usr/bin/python bath doesn't exist
	if [ ! -f /usr/bin/python ]; then ln -s /usr/bin/python3 /usr/bin/python; fi

	# Install GPG key
	curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | apt-key add -

	# add wazuh repository
	echo "deb https://packages.wazuh.com/${wazuhversion_majormajor}.x/apt/ stable main" > /etc/apt/sources.list.d/wazuh.list

	# update packages and install wazuh manager
	apt update
	apt -y install wazuh-manager

	# install NodeJS for wazuh api and then wazuh api
	curl -sL https://deb.nodesource.com/setup_8.x | bash -
	apt -y install nodejs wazuh-api
	
elif [ $os_family = fedora ]; then

	# add Wazuh repo for centos
	cat <<-EOF >/etc/yum.repos.d/wazuh.repo
	[wazuh_repo]
	gpgcheck=1
	gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
	enabled=1
	name=Wazuh repository
	baseurl=https://packages.wazuh.com/${wazuhversion_majormajor}.x/yum/
	protect=1
	EOF

	# Insall Wazuh Manager
	yum -y install wazuh-manager

	# Install NodeJS and Wazuh API (centos/rhel version 7 or higher)
	curl --silent --location https://rpm.nodesource.com/setup_8.x | bash -
	yum -y install nodejs wazuh-api

fi

# load wazuh template for elasticsearch after waiting 60 seconds
sleep 60
curl https://raw.githubusercontent.com/wazuh/wazuh/${wazuhversion_major}/extensions/elasticsearch/wazuh-elastic${elkversion_majormajor}-template-alerts.json | curl -XPUT 'http://localhost:9200/_template/wazuh' -H 'Content-Type: application/json' -d @-

if [ $logstash_server = local ]; then

	# add logstash user to ossec group
	usermod -a -G ossec logstash

	# download wazuh configuration for logstash (local, single host)
	curl -so /etc/logstash/conf.d/01-wazuh.conf https://raw.githubusercontent.com/wazuh/wazuh/${wazuhersion_major}/extensions/logstash/01-wazuh-local.conf

else

	# download wazuh configuration for logstash (remote logstash)
	curl -so /etc/logstash/conf.d/01-wazuh.conf https://raw.githubusercontent.com/wazuh/wazuh/${wazuhversion_major}/extensions/logstash/01-wazuh-remote.conf

	# install filebeat
	if [ $os_family = debian ]; then

		curl -s https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add -
		echo "deb https://artifacts.elastic.co/packages/${elkversion_majormajor}.x/apt stable main" | tee /etc/apt/sources.list.d/elastic-${elkversion_majormajor}.x.list
		apt-get update
        apt -y install filebeat=${elkversion}

	elif [ $os_family = fedora ]; then

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
		yum -y install filebeat-${elkversion}

	fi
    
    # download filebeat config and set server address/ip if specified
    if [[ ! -e /etc/filebeat/filebeat.yml ]]; then

    	curl -so /etc/filebeat/filebeat.yml https://raw.githubusercontent.com/wazuh/wazuh/${elkversion_major}/extensions/filebeat/filebeat.yml
		sed -i "s/YOUR_ELASTIC_SERVER_IP/$logstash_server/" /etc/filebeat/filebeat.yml

    fi

    systemctl daemon-reload
	systemctl enable filebeat.service
    systemctl start filebeat.service
	
fi

# ensure proper permissions for kibana app
if [[ -e /usr/share/kibana/bin/kibana-plugin ]]; then
	chown -R kibana:kibana /usr/share/kibana/optimize
	chown -R kibana:kibana /usr/share/kibana/plugins
fi

# remove previous version of kibana wazuh plugin if installed
if [[ -e /usr/share/kibana/plugins/wazuh ]]; then
	sudo -u kibana /usr/share/kibana/bin/kibana-plugin remove wazuh
	rm -rf /usr/share/kibana/optimize/bundles
fi

# increase Node.js heap memory and install Wazuh app plugin for kibana as kibana if kibana is installed
if [[ -e /usr/share/kibana/bin/kibana-plugin ]]; then
	export NODE_OPTIONS="--max-old-space-size=3072" && sudo -u kibana /usr/share/kibana/bin/kibana-plugin install https://packages.wazuh.com/wazuhapp/wazuhapp-${wazuhversion}_${elkversion}.zip
fi
