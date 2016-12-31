#!/bin/bash

HOSTNAME=$1		# Name of host, where the script is running currently
SERVERNAME=$2	# Hostname of Zabbix server

# Add Zabbix repository
rpm -ivh http://repo.zabbix.com/zabbix/2.0/rhel/6/x86_64/zabbix-release-2.0-1.el6.noarch.rpm

# Install needed software for Zabbix agent
yum -y -q install man zabbix zabbix-agent
makewhatis

# Setup correct local time (Moscow default)
rm /etc/localtime
ln -s /usr/share/zoneinfo/Europe/Moscow /etc/localtime

# Apply correct settings to the Zabbix agent
chkconfig zabbix-agent on
sed -i -e "s/Server=127.0.0.1/Server=${SERVERNAME}/g" -e "s/Hostname=Zabbix server/Hostname=${HOSTNAME}/g" /etc/zabbix/zabbix_agentd.conf
service zabbix-agent start

# Switch SE Linux to the permissive mode
setenforce Permissive
sed -i -e 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config

# Modify IPtables settings for monitored hosts
iptables -I INPUT 5 -p tcp -m state --state NEW -m tcp --dport 10050 -j ACCEPT
service iptables save
service iptables reload

# Using Zabbix API to add and modify hosts
# jq - Command-line JSON processor - needed for parcing of reply from Zabbix server
ZABBIX_USER="Admin"
ZABBIX_PASS="zabbix"
HOSTGROUPID="2"										# Group Linux servers
TEMPLATEID="10001"									# Template OS Linux
SERVERGROUPID="4"									# Group "Zabbix servers"
ZTEMPLATEID="10047"									# Template App Zabbix Server
API="http://"${SERVERNAME}"/zabbix/api_jsonrpc.php"	# URL to Zabbix API
TOKEN=""											# Using in API requests to authentificate
ZHOSTID=""											# HOSTID of Zabbix server, user to change its settings

# Function to get authorization token from Zabbix server
function get_token {
	TOKEN="$(curl -s -H 'Content-Type: application/json-rpc' -d "{\"jsonrpc\":\"2.0\", \"method\":\"user.login\", \"params\":{\"user\":\"${ZABBIX_USER}\", \"password\":\"${ZABBIX_PASS}\"}, \"id\":0}" ${API} | /home/vagrant/bin/jq-linux64 -r .result)"
	echo "Token = ${TOKEN}"
}

mkdir /home/vagrant/bin
cd /home/vagrant/bin
curl -L https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64 -o ./jq-linux64
chmod +x ./jq-linux64

if [ "${HOSTNAME}" == "${SERVERNAME}" ]; then
	# Install needed software for Zabbix server
	yum -y -q install zabbix-server-mysql zabbix-web-mysql mysql-server
	# Enabling services
	chkconfig mysqld on
	chkconfig zabbix-server on
	chkconfig httpd on
	# Enable UTF-8 codepage for MySQL server
	sed -i -e 's/\[mysqld\]/\[mysqld\]\ncharacter-set-server=utf8/g' /etc/my.cnf

	service mysqld start
	mysqladmin -u root password 'Qwerty123'		# Change password for root of DB

	# mysql_secure_installation answers:
	# 1. Password for root, generetes an error "Inappropriate ioctl for device", but works properly
	# 2. Change the root password? - n
	# 3. Remove anonymous users? - y
	# 4. Disallow root login remotely? - y
	# 5. Remove test database and access to it? - y
	# 6. Reload privilege tables now? - y

	mysql_secure_installation <<-EOF
		Qwerty123
		n
		y
		y
		y
		y
	EOF
	
	# Creating database for Zabbix
	mysql -uroot -pQwerty123 <<-EOF
		create database zabbix character set utf8 collate utf8_bin;
		grant all privileges on zabbix.* to zabbix@localhost identified by 'zabbix';
		flush privileges;
		quit
	EOF

	mysql -uzabbix -pzabbix zabbix < /usr/share/doc/zabbix-server-mysql-*/create/schema.sql
	mysql -uzabbix -pzabbix zabbix < /usr/share/doc/zabbix-server-mysql-*/create/images.sql
	mysql -uzabbix -pzabbix zabbix < /usr/share/doc/zabbix-server-mysql-*/create/data.sql
	service mysqld restart

	# Changing settings for Zabbix server
	sed -i -e 's/# DBHost=localhost/DBHost=localhost/g' -e 's/# DBPassword=/DBPassword=zabbix/g'  /etc/zabbix/zabbix_server.conf
	sed -i -e 's/post_max_size = 8M/post_max_size = 16M/g' -e 's/max_execution_time = 30/max_execution_time = 300/g' -e 's/max_input_time = 60/max_input_time = 300/g' -e 's/;date.timezone =/date.timezone = Europe\/Moscow/g' /etc/php.ini
	sed -i -e 's/# php_value date.timezone Europe\/Riga/php_value date.timezone Europe\/Moscow/g' /etc/httpd/conf.d/zabbix.conf

	# Add IPtables rules for Zabbix server
	iptables -I INPUT 5 -p tcp -m state --state NEW -m tcp --dport 80 -j ACCEPT
	iptables -I INPUT 6 -p tcp -m state --state NEW -m tcp --dport 10051 -j ACCEPT
	service iptables save
	service iptables reload

	# Making initial setup for Zabbix server
	service httpd start
	service zabbix-server start

	cat > /etc/zabbix/web/zabbix.conf.php <<-EOF
		<?php
		// Zabbix GUI configuration file
		global \$DB;

		\$DB['TYPE']     = 'MYSQL';
		\$DB['SERVER']   = 'localhost';
		\$DB['PORT']     = '0';
		\$DB['DATABASE'] = 'zabbix';
		\$DB['USER']     = 'zabbix';
		\$DB['PASSWORD'] = 'zabbix';

		// SCHEMA is relevant only for IBM_DB2 database
		\$DB['SCHEMA'] = '';

		\$ZBX_SERVER      = 'localhost';
		\$ZBX_SERVER_PORT = '10051';
		\$ZBX_SERVER_NAME = '';

		\$IMAGE_FORMAT_DEFAULT = IMAGE_FORMAT_PNG;
		?>
	EOF

	service httpd restart
	service zabbix-server restart
	
	# Login to server and get auth token
	get_token
	# Get ID of automatically created host on Zabbix server
	ZHOSTID="$(curl -s -H 'Content-Type: application/json-rpc' -d "{\"jsonrpc\":\"2.0\", \"method\":\"host.get\", \"params\":{\"output\":[\"hostid\"], \"filter\":{\"host\":[\"Zabbix server\"]}}, \"auth\":\"${TOKEN}\", \"id\": 1}" ${API} | /home/vagrant/bin/jq-linux64 -r '.result[0] .hostid')"
	# Delete this host, because it has wrong default settings
	curl -s -H 'Content-Type: application/json-rpc' -d "{\"jsonrpc\":\"2.0\", \"method\":\"host.delete\", \"params\":{\"hostid\":\"${ZHOSTID}\"}, \"auth\":\"${TOKEN}\", \"id\": 2}" ${API}
	# Create host with right settings
	curl -s -H 'Content-Type: application/json-rpc' -d "{\"jsonrpc\":\"2.0\", \"method\":\"host.create\", \"params\":{\"host\":\"${HOSTNAME}\", \"name\":\"Zabbix server\", \"interfaces\":[{\"type\":1, \"main\":1, \"useip\":0, \"ip\":\"\", \"dns\":\"${HOSTNAME}\", \"port\":\"10050\"}], \"groups\":[{\"groupid\":\"${SERVERGROUPID}\"}]}, \"auth\":\"${TOKEN}\", \"id\":3}" ${API}
	# Get ID of just created host
	ZHOSTID="$(curl -s -H 'Content-Type: application/json-rpc' -d "{\"jsonrpc\":\"2.0\", \"method\":\"host.get\", \"params\":{\"output\":[\"hostid\"], \"filter\":{\"host\":[\"${HOSTNAME}\"]}}, \"auth\":\"${TOKEN}\", \"id\": 4}" ${API} | /home/vagrant/bin/jq-linux64 -r '.result[0] .hostid')"
	# Add templates to host according to server role
	curl -s -H 'Content-Type: application/json-rpc' -d "{\"jsonrpc\":\"2.0\", \"method\":\"host.update\", \"params\":{\"hostid\":\"${ZHOSTID}\", \"templates\":[{\"templateid\":\"${ZTEMPLATEID}\"}, {\"templateid\":\"${TEMPLATEID}\"}]}, \"auth\":\"${TOKEN}\", \"id\":5}" ${API}
	# Logout
	curl -s -H 'Content-Type: application/json-rpc' -d "{\"jsonrpc\":\"2.0\", \"method\":\"user.logout\", \"params\":[], \"auth\":\"${TOKEN}\", \"id\": 6}" ${API}
else
	# Login to server and get auth token
	get_token
	# Create new host with needed settings
	curl -s -H 'Content-Type: application/json-rpc' -d "{\"jsonrpc\":\"2.0\", \"method\":\"host.create\", \"params\":{\"host\":\"${HOSTNAME}\", \"interfaces\":[{\"type\":1, \"main\":1, \"useip\":0, \"ip\":\"\", \"dns\":\"${HOSTNAME}\", \"port\":\"10050\"}], \"groups\":[{\"groupid\":\"${HOSTGROUPID}\"}], \"templates\":[{\"templateid\":\"${TEMPLATEID}\"}]}, \"auth\":\"${TOKEN}\", \"id\":1}" ${API}
	# Logout
	curl -s -H 'Content-Type: application/json-rpc' -d "{\"jsonrpc\":\"2.0\", \"method\":\"user.logout\", \"params\":[], \"auth\":\"${TOKEN}\", \"id\": 2}" ${API}
fi

exit 0
