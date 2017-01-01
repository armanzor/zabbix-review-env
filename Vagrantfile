# -*- mode: ruby -*-
# vi: set ft=ruby :

hostname = "zabbix-t"
servername = "#{hostname}1"

# Please do not cancel numeration of hosts, it helps to add machines to Zabbix monitoring

nodes = [
	{
		:name => "#{hostname}1",
		:eth0 => "10.20.30.41",
		:port => "2311"
	} ,
	{
		:name => "#{hostname}2",
		:eth0 => "10.20.30.42",
		:port => "2312"
	},
	{
		:name => "#{hostname}3",
		:eth0 => "10.20.30.43",
		:port => "2313"
	}
]

Vagrant.configure("2") do |config|
	config.vm.box = "kaorimatz/centos-6.8-x86_64"
	nodes.each do |opts|
		config.vm.define opts[:name] do |config|
			config.vm.hostname = opts[:name]
			config.ssh.insert_key = false
			
			config.vm.provider "virtualbox" do |v|
				v.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
				v.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
				v.customize ["modifyvm", :id, "--name", opts[:name]]
				v.customize ["modifyvm", :id, "--macaddress1", "auto"]
			end

			config.vm.network :private_network, ip: opts[:eth0]
			config.vm.network :forwarded_port, guest: 22, host: opts[:port]
			config.vm.provision :hosts, :sync_hosts => true
			config.vm.provision :shell, :path => "install.sh", :args => "#{opts[:name]} #{servername}"
		end
	end
	config.vm.define "#{servername}" do |config|
		config.vm.network :forwarded_port, guest: 80, host: 2380
	end
end
