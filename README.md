<body>
<h2>Zabbix server and client review environment</h2>
This files <code>install.sh</code> and <code>Vagrantfile</code> are using for deployment of ready test environment. It consists of one Zabbix server and two Zabbix clients, running on CentOS 6.8. The number of client can be easy corrected by editing of <code>Vagrantfile</code>. Please check <code>Vagrantfile</code> for collisions of IP addresses and ports what might be already provided to other processes on your host system. By default there are used guest IPs 192.168.33.211, 192.168.33.212 and 192.168.33.213 and ports 2311, 2312, 2313 forwarded to host from guest port 22 (SSH) and 2380 from 80 of the first guest which act as server. You can change the template of guests name in <code>Vagrantfile</code> (the “hostname” variable). In deploying process downloads JSON processor <b>jq</b> for parsing of JSON Zabbix API requests https://stedolan.github.io/jq/ <br>
First of all, you have to install this software: <br>
•	Oracle Virtualbox with extension pack (use default installation folder) <br>
•	Vagrant (don’t use to install folder with symbols other that latin) <br>
•	Vagrant plugin <b>vagrant-hosts</b> (required, run in CLI <code>vagrant plugin install vagrant-hosts)</code> <br>
•	Vagrant plugin <b>sahara</b> (recommended, run in CLI <code>vagrant plugin install sahara)</code> <br>
•	Vagrant plugin <b>vagrant-vbguest</b> (recommended, run in CLI <code>vagrant plugin install vagrant-vbguest)</code> <br>
Before continue make sure that your host computer has enough disk space (check settings of virtualbox) and RAM for guests. Copy this files to folder, where the guest’s settings will be placed (it will not consume a lot of disk space). Then in CLI go to this folder and run <code>vagrant up</code>. After several minutes Zabbix server main page will be accessible by address http://localhost:2380/zabbix in your browser with two connected to it clients. That’s all! <br>
<strong>Never run system software upgrade on the guest systems, it will destroy it</strong> <br>
</body>
