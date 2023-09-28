#!/bin/bash
# This code is the property of VitalPBX LLC Company
# License: Proprietary
# Date: 28-Sep-2023
# VitalPBX Replica with MariaDB Replica and Lsync
#
set -e
function jumpto
{
    label=$start
    cmd=$(sed -n "/$label:/{:a;n;p;ba};" $0 | grep -v ':$')
    eval "$cmd"
    exit
}

echo -e "\n"
echo -e "************************************************************"
echo -e "*       Welcome to the VitalPBX Replicay installation      *"
echo -e "*                All options are mandatory                 *"
echo -e "************************************************************"

filename="config.txt"
if [ -f $filename ]; then
	echo -e "config file"
	n=1
	while read line; do
		case $n in
			1)
				ip_master=$line
  			;;
			2)
				ip_standby=$line
  			;;
		esac
		n=$((n+1))
	done < $filename
	echo -e "IP Server 1.............. > $ip_master"	
	echo -e "IP Server 2.............. > $ip_standby"
fi

while [[ $ip_master == '' ]]
do
    read -p "IP Server 1............. > " ip_master 
done 

while [[ $ip_standby == '' ]]
do
    read -p "IP Server 2............. > " ip_standby 
done

echo -e "************************************************************"
echo -e "*                   Check Information                      *"
echo -e "*        Make sure you have internet on both servers       *"
echo -e "************************************************************"
while [[ $veryfy_info != yes && $veryfy_info != no ]]
do
    read -p "Are you sure to continue with this settings? (yes,no) > " veryfy_info 
done

if [ "$veryfy_info" = yes ] ;then
	echo -e "************************************************************"
	echo -e "*                Starting to run the scripts               *"
	echo -e "************************************************************"
else
    	exit;
fi

cat > config.txt << EOF
$ip_master
$ip_standby
EOF


start="rename_tenant_id_in_server2"
case $step in
	1)
		start="rename_tenant_id_in_server2"
  	;;
	2)
		start="configuring_firewall"
  	;;
	3)
		start="create_lsyncd_config_file"
  	;;
	4)
		start="create_mariadb_replica"
	;;
esac
jumpto $start
echo -e "*** Done Step 1 ***"
echo -e "1"	> step.txt

rename_tenant_id_in_server2:
echo -e "************************************************************"
echo -e "*                Remove Tenant in Server 2                 *"
echo -e "************************************************************"
remote_tenant_id=`ssh root@$ip_standby "ls /var/lib/vitalpbx/static/"`
ssh root@$ip_standby "rm -rf /var/lib/vitalpbx/static/$remote_tenant_id"
echo -e "*** Done Step 2 ***"
echo -e "2"	> step.txt

configuring_firewall:
echo -e "************************************************************"
echo -e "*             Configuring Temporal Firewall                *"
echo -e "************************************************************"
#Create temporal Firewall Rules in Server 1 and 2
firewall-cmd --permanent --zone=public --add-port=3306/tcp
firewall-cmd --reload
ssh root@$ip_standby "firewall-cmd --permanent --zone=public --add-port=3306/tcp"
ssh root@$ip_standby "firewall-cmd --reload"

echo -e "************************************************************"
echo -e "*             Configuring Permanent Firewall               *"
echo -e "*   Creating Firewall Services in VitalPBX in Server 1     *"
echo -e "************************************************************"
mysql -uroot ombutel -e "INSERT INTO ombu_firewall_services (name, protocol, port) VALUES ('MariaDB Client', 'tcp', '3306')"
echo -e "************************************************************"
echo -e "*             Configuring Permanent Firewall               *"
echo -e "*     Creating Firewall Rules in VitalPBX in Server 1      *"
echo -e "************************************************************"
last_index=$(mysql -uroot ombutel -e "SELECT MAX(\`index\`) AS Consecutive FROM ombu_firewall_rules"  | awk 'NR==2')
last_index=$last_index+1
service_id=$(mysql -uroot ombutel -e "select firewall_service_id from ombu_firewall_services where name = 'MariaDB Client'" | awk 'NR==2')
mysql -uroot ombutel -e "INSERT INTO ombu_firewall_rules (firewall_service_id, source, action, \`index\`) VALUES ($service_id, '$ip_master', 'accept', $last_index)"
last_index=$last_index+1
mysql -uroot ombutel -e "INSERT INTO ombu_firewall_rules (firewall_service_id, source, action, \`index\`) VALUES ($service_id, '$ip_standby', 'accept', $last_index)"
mysql -uroot ombutel -e "INSERT INTO ombu_firewall_whitelist (host, description, \`default\`) VALUES ('$ip_master', 'Server 1 IP', 'no')"
mysql -uroot ombutel -e "INSERT INTO ombu_firewall_whitelist (host, description, \`default\`) VALUES ('$ip_standby', 'Server 2 IP', 'no')"
echo -e "*** Done Step 3 ***"
echo -e "3"	> step.txt

create_lsyncd_config_file:
echo -e "************************************************************"
echo -e "*          Configure Sync in Server 1 and 2               *"
echo -e "************************************************************"
if [ ! -d "/var/spool/asterisk/monitor" ] ;then
	mkdir /var/spool/asterisk/monitor
fi
chown asterisk:asterisk /var/spool/asterisk/monitor

ssh root@$ip_standby [[ ! -d /var/spool/asterisk/monitor ]] && ssh root@$ip_standby "mkdir /var/spool/asterisk/monitor" || echo "Path exist";
ssh root@$ip_standby "chown asterisk:asterisk /var/spool/asterisk/monitor"

if [ ! -d "/home/sync/var/spool/asterisk/monitor_temp" ] ;then
	mkdir -p /home/sync/var/spool/asterisk/monitor_temp
fi
ssh root@$ip_standby [[ ! -d /home/sync/var/spool/asterisk/monitor_temp ]] && ssh root@$ip_standby "mkdir -p /home/sync/var/spool/asterisk/monitor_temp" || echo "Path exist";

if [ ! -d "/home/sync/var/lib/asterisk/agi-bin_temp" ] ;then
	mkdir -p /home/sync/var/lib/asterisk/agi-bin_temp
fi
ssh root@$ip_standby [[ ! -d /home/sync/var/lib/asterisk/agi-bin_temp ]] && ssh root@$ip_standby "mkdir -p /home/sync/var/lib/asterisk/agi-bin_temp" || echo "Path exist";

if [ ! -d "/home/sync/var/lib/asterisk/priv-callerintros_temp" ] ;then
	mkdir -p /home/sync/var/lib/asterisk/priv-callerintros_temp
fi
ssh root@$ip_standby [[ ! -d /home/sync/var/lib/asterisk/priv-callerintros_temp ]] && ssh root@$ip_standby "mkdir -p /home/sync/var/lib/asterisk/priv-callerintros_temp" || echo "Path exist";

if [ ! -d "/home/sync/var/lib/asterisk/sounds_temp" ] ;then
	mkdir -p /home/sync/var/lib/asterisk/sounds_temp
fi
ssh root@$ip_standby [[ ! -d /home/sync/var/lib/asterisk/sounds_temp ]] && ssh root@$ip_standby "mkdir -p /home/sync/var/lib/asterisk/sounds_temp" || echo "Path exist";

if [ ! -d "/home/sync/var/lib/vitalpbx_temp" ] ;then
	mkdir -p /home/sync/var/lib/vitalpbx_temp
fi
ssh root@$ip_standby [[ ! -d /home/sync/var/lib/vitalpbx_temp ]] && ssh root@$ip_standby "mkdir -p /home/sync/var/lib/vitalpbx_temp" || echo "Path exist";

if [ ! -d "/home/sync/var/spool/asterisk/sqlite3_temp" ] ;then
	mkdir -p /home/sync/var/spool/asterisk/sqlite3_temp
fi
ssh root@$ip_standby [[ ! -d /home/sync/var/spool/asterisk/sqlite3_temp ]] && ssh root@$ip_standby "mkdir -p /home/sync/var/spool/asterisk/sqlite3_temp" || echo "Path exist";

cat > /etc/lsyncd.conf << EOF
----
-- User configuration file for lsyncd.
--
-- Simple example for default rsync.
--
settings {
		logfile    = "/var/log/lsyncd/lsyncd.log",
		statusFile = "/var/log/lsyncd/lsyncd-status.log",
		statusInterval = 20,
		nodaemon   = true,
		insist = true,
}
sync {
		default.rsync,
		source="/var/spool/asterisk/monitor",
		target="$ip_standby:/var/spool/asterisk/monitor",
		delete = 'running',
                --delay = 5,
		rsync={
                		-- timeout = 3000,
                		update = true,
                		_extra={"--temp-dir=/home/sync/var/spool/asterisk/monitor_temp/"},
                		times = true,
                		archive = true,
                		compress = true,
                		perms = true,
                		acls = true,
                		owner = true,
				group = true
		}
}
sync {
		default.rsync,
		source="/var/lib/asterisk/",
		target="$ip_standby:/home/sync/var/spool/asterisk/sqlite3_temp/",
		rsync = {
				binary = "/usr/bin/rsync",
				owner = true,
				group = true,
				archive = "true",
				_extra = {
						"--include=astdb.sqlite3",
						"--exclude=*"
						}
				}
}
sync {
		default.rsync,
		source="/var/lib/asterisk/agi-bin/",
		target="$ip_standby:/var/lib/asterisk/agi-bin/",
		delete = 'running',
                --delay = 5,
		rsync={
                		-- timeout = 3000,
                		update = true,
                		_extra={"--temp-dir=/home/sync/var/lib/asterisk/agi-bin_temp/"},
                		times = true,
                		archive = true,
                		compress = true,
                		perms = true,
                		acls = true,
                		owner = true,
				group = true
		}
}
sync {
		default.rsync,
		source="/var/lib/asterisk/priv-callerintros/",
		target="$ip_standby:/var/lib/asterisk/priv-callerintros",
		delete = 'running',
                --delay = 5,
		rsync={
                		-- timeout = 3000,
                		update = true,
                		_extra={"--temp-dir=/home/sync/var/lib/asterisk/priv-callerintros_temp/"},
                		times = true,
                		archive = true,
                		compress = true,
                		perms = true,
                		acls = true,
                		owner = true,
				group = true
		}
}
sync {
		default.rsync,
		source="/var/lib/asterisk/sounds/",
		target="$ip_standby:/var/lib/asterisk/sounds/",
		delete = 'running',
                --delay = 5,
		rsync={
                		-- timeout = 3000,
                		update = true,
                		_extra={"--temp-dir=/home/sync/var/lib/asterisk/sounds_temp/"},
                		times = true,
                		archive = true,
                		compress = true,
                		perms = true,
                		acls = true,
                		owner = true,
				group = true
		}
}
sync {
		default.rsync,
		source="/var/lib/vitalpbx",
		target="$ip_standby:/var/lib/vitalpbx",
		delete = 'running',
                --delay = 5,
		rsync = {
		                -- timeout = 3000,
                		update = true,
				binary = "/usr/bin/rsync",
				_extra = {      "--temp-dir=/home/sync/var/lib/vitalpbx_temp/",
						"--exclude=*.lic",
						"--exclude=*.dat",
						"--exclude=dbsetup-done",
						"--exclude=cache"
						},
                		times = true,
                		archive = true,
                		compress = true,
                		perms = true,
                		acls = true,
                		owner = true,
				group = true
		}
}
EOF
cat > /tmp/lsyncd.conf << EOF
----
-- User configuration file for lsyncd.
--
-- Simple example for default rsync.
--
settings {
		logfile    = "/var/log/lsyncd/lsyncd.log",
		statusFile = "/var/log/lsyncd/lsyncd-status.log",
		statusInterval = 20,
		nodaemon   = true,
		insist = true,
}
sync {
		default.rsync,
		source="/var/spool/asterisk/monitor",
		target="$ip_master:/var/spool/asterisk/monitor",
		delete = 'running',
                --delay = 5,
		rsync={
                		-- timeout = 3000,
                		update = true,
                		_extra={"--temp-dir=/home/sync/var/spool/asterisk/monitor_temp/"},
                		times = true,
                		archive = true,
                		compress = true,
                		perms = true,
                		acls = true,
                		owner = true,
				group = true
		}
}
sync {
		default.rsync,
		source="/var/lib/asterisk/",
		target="$ip_master:/home/sync/var/spool/asterisk/sqlite3_temp/",
		rsync = {
				binary = "/usr/bin/rsync",
				owner = true,
				group = true,
				archive = "true",
				_extra = {
						"--include=astdb.sqlite3",
						"--exclude=*"
						}
				}
}
sync {
		default.rsync,
		source="/var/lib/asterisk/agi-bin/",
		target="$ip_master:/var/lib/asterisk/agi-bin/",
		delete = 'running',
                --delay = 5,
		rsync={
                		-- timeout = 3000,
                		update = true,
                		_extra={"--temp-dir=/home/sync/var/lib/asterisk/agi-bin_temp/"},
                		times = true,
                		archive = true,
                		compress = true,
                		perms = true,
                		acls = true,
                		owner = true,
				group = true
		}
}
sync {
		default.rsync,
		source="/var/lib/asterisk/priv-callerintros/",
		target="$ip_master:/var/lib/asterisk/priv-callerintros",
		delete = 'running',
                --delay = 5,
		rsync={
                		-- timeout = 3000,
                		update = true,
                		_extra={"--temp-dir=/home/sync/var/lib/asterisk/priv-callerintros_temp/"},
                		times = true,
                		archive = true,
                		compress = true,
                		perms = true,
                		acls = true,
                		owner = true,
				group = true
		}
}
sync {
		default.rsync,
		source="/var/lib/asterisk/sounds/",
		target="$ip_master:/var/lib/asterisk/sounds/",
		delete = 'running',
                --delay = 5,
		rsync={
                		-- timeout = 3000,
                		update = true,
                		_extra={"--temp-dir=/home/sync/var/lib/asterisk/sounds_temp/"},
                		times = true,
                		archive = true,
                		compress = true,
                		perms = true,
                		acls = true,
                		owner = true,
				group = true
		}
}
sync {
		default.rsync,
		source="/var/lib/vitalpbx",
		target="$ip_master:/var/lib/vitalpbx",
		delete = 'running',
                --delay = 5,
		rsync = {
		                -- timeout = 3000,
                		update = true,
				binary = "/usr/bin/rsync",
				_extra = {      "--temp-dir=/home/sync/var/lib/vitalpbx_temp/",
						"--exclude=*.lic",
						"--exclude=*.dat",
						"--exclude=dbsetup-done",
						"--exclude=cache"
						},
                		times = true,
                		archive = true,
                		compress = true,
                		perms = true,
                		acls = true,
                		owner = true,
				group = true
		}
}
EOF
scp /tmp/lsyncd.conf root@$ip_standby:/etc/lsyncd.conf
systemctl enable lsyncd.service
ssh root@$ip_standby "systemctl enable lsyncd.service"
systemctl start lsyncd.service
ssh root@$ip_standby "systemctl start lsyncd.service"

echo -e "*** Done Step 4 ***"
echo -e "4"	> step.txt

create_mariadb_replica:
echo -e "************************************************************"
echo -e "*                Create MariaDB replica                    *"
echo -e "************************************************************"
#Remove anonymous user from MySQL
mysql -uroot -e "DELETE FROM mysql.user WHERE User='';"
#Configuration of the First Master Server (Master-1)
cat > /etc/my.cnf.d/vitalpbx.cnf << EOF
[mysqld]
server-id=1
log-bin=mysql-bin
report_host = master1
innodb_buffer_pool_size = 64M
innodb_flush_log_at_trx_commit = 2
innodb_log_file_size = 64M
innodb_log_buffer_size = 64M
bulk_insert_buffer_size = 64M
max_allowed_packet = 64M
EOF
systemctl restart mariadb
#Create a new user on the Master-1
mysql -uroot -e "GRANT REPLICATION SLAVE ON *.* to vitalpbx_replica@'%' IDENTIFIED BY 'vitalpbx_replica';"
mysql -uroot -e "FLUSH PRIVILEGES;"
mysql -uroot -e "FLUSH TABLES WITH READ LOCK;"
#Get bin_log on Master-1
file_server_1=`mysql -uroot -e "show master status" | awk 'NR==2 {print $1}'`
position_server_1=`mysql -uroot -e "show master status" | awk 'NR==2 {print $2}'`

#Now on the Master-1 server, do a dump of the database MySQL and import it to Master-2
mysqldump -u root --all-databases > all_databases.sql
scp all_databases.sql root@$ip_standby:/tmp/all_databases.sql
cat > /tmp/mysqldump.sh << EOF
#!/bin/bash
mysql mysql -u root <  /tmp/all_databases.sql 
EOF
scp /tmp/mysqldump.sh root@$ip_standby:/tmp/mysqldump.sh
ssh root@$ip_standby "chmod +x /tmp/mysqldump.sh"
ssh root@$ip_standby "/tmp/./mysqldump.sh"

#Configuration of the Second Master Server (Master-2)
cat > /tmp/vitalpbx.cnf << EOF
[mysqld]
server-id = 2
log-bin=mysql-bin
report_host = master2
innodb_buffer_pool_size = 64M
innodb_flush_log_at_trx_commit = 2
innodb_log_file_size = 64M
innodb_log_buffer_size = 64M
bulk_insert_buffer_size = 64M
max_allowed_packet = 64M
EOF
scp /tmp/vitalpbx.cnf root@$ip_standby:/etc/my.cnf.d/vitalpbx.cnf
ssh root@$ip_standby "systemctl restart mariadb"
#Create a new user on the Master-2
cat > /tmp/grand.sh << EOF
#!/bin/bash
mysql -uroot -e "GRANT REPLICATION SLAVE ON *.* to vitalpbx_replica@'%' IDENTIFIED BY 'vitalpbx_replica';"
mysql -uroot -e "FLUSH PRIVILEGES;"
mysql -uroot -e "FLUSH TABLES WITH READ LOCK;"
EOF
scp /tmp/grand.sh root@$ip_standby:/tmp/grand.sh
ssh root@$ip_standby "chmod +x /tmp/grand.sh"
ssh root@$ip_standby "/tmp/./grand.sh"
#Get bin_log on Master-2
file_server_2=`ssh root@$ip_standby 'mysql -uroot -e "show master status;"' | awk 'NR==2 {print $1}'`
position_server_2=`ssh root@$ip_standby 'mysql -uroot -e "show master status;"' | awk 'NR==2 {print $2}'`
#Stop the slave, add Master-1 to the Master-2 and start slave
cat > /tmp/change.sh << EOF
#!/bin/bash
mysql -uroot -e "STOP SLAVE;"
mysql -uroot -e "CHANGE MASTER TO MASTER_HOST='$ip_master', MASTER_USER='vitalpbx_replica', MASTER_PASSWORD='vitalpbx_replica', MASTER_LOG_FILE='$file_server_1', MASTER_LOG_POS=$position_server_1;"
mysql -uroot -e "START SLAVE;"
EOF
scp /tmp/change.sh root@$ip_standby:/tmp/change.sh
ssh root@$ip_standby "chmod +x /tmp/change.sh"
ssh root@$ip_standby "/tmp/./change.sh"

#Connect to Master-1 and follow the same steps
mysql -uroot -e "STOP SLAVE;"
mysql -uroot -e "CHANGE MASTER TO MASTER_HOST='$ip_standby', MASTER_USER='vitalpbx_replica', MASTER_PASSWORD='vitalpbx_replica', MASTER_LOG_FILE='$file_server_2', MASTER_LOG_POS=$position_server_2;"
mysql -uroot -e "START SLAVE;"
echo -e "*** Done Step 5 ***"
echo -e "5"	> step.txt

echo -e "************************************************************"
echo -e "*     Create Scripts to copy SQLite Asterisk database      *"
echo -e "*          Stop Asterisk, copy asterisk database           *"
echo -e "*                and start Asterisk again                  *"
echo -e "************************************************************"
cat > /usr/local/bin/vpbxstart << EOF
#!/bin/bash
# This code is the property of VitalPBX LLC Company
# License: Proprietary
# Date: 25-Apr-2021
# Stop Asterisk, copy asterisk database and start Asterisk again
#
systemctl stop asterisk
/bin/cp -Rf /home/sync/var/spool/asterisk/sqlite3_temp/astdb.sqlite3 /var/lib/asterisk/astdb.sqlite3
systemctl start asterisk
EOF
chmod +x /usr/local/bin/vpbxstart
scp /usr/local/bin/vpbxstart root@$ip_standby:/usr/local/bin/vpbxstart
ssh root@$ip_standby 'chmod +x /usr/local/bin/vpbxstart'

vitalpbx_cluster_ok:
echo -e "************************************************************"
echo -e "*                VitalPBX Replica OK                       *"
echo -e "************************************************************"
