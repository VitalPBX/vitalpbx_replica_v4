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
if [ ! -d "/home/sync/var/spool/asterisk/sqlite3_temp" ] ;then
	mkdir -p /home/sync/var/spool/asterisk/sqlite3_temp
fi
ssh root@$ip_standby [[ ! -d /home/sync/var/spool/asterisk/sqlite3_temp ]] && ssh root@$ip_standby "mkdir -p /home/sync/var/spool/asterisk/sqlite3_temp" || echo "Path exist";

if [ ! -d "/etc/lsyncd" ] ;then
	mkdir /etc/lsyncd
fi
if [ ! -d "/var/log/lsyncd" ] ;then
	mkdir /var/log/lsyncd
	touch /var/log/lsyncd/lsyncd.{log,status}
fi

cat > /etc/lsyncd/lsyncd.conf.lua << EOF
----
-- User configuration file for lsyncd.
--
-- Simple example for default rsync.
--
settings {
		logfile    = "/var/log/lsyncd/lsyncd.log",
		statusFile = "/var/log/lsyncd/lsyncd.status",
		statusInterval = 20,
		nodaemon   = false,
		insist = true,
}
sync {
		default.rsyncssh,
		source = "/var/spool/asterisk/monitor",
		host = "$ip_standby",
		targetdir = "/var/spool/asterisk/monitor",
		rsync = {
				owner = true,
				group = true
		}
}
sync {
		default.rsyncssh,
		source = "/var/lib/asterisk/",
		host = "$ip_standby",
		targetdir = "/var/lib/asterisk/",
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
		default.rsyncssh,
		source = "/usr/share/vitxi/backend/",
		host = "$ip_standby",
		targetdir = "/usr/share/vitxi/backend/",
		rsync = {
				binary = "/usr/bin/rsync",
				owner = true,
				group = true,
				archive = "true",
				_extra = {
						"--include=.env",
						"--exclude=*"
						}
				}
}
sync {
		default.rsyncssh,
		source = "/usr/share/vitxi/backend/storage/",
		host = "$ip_standby",
		targetdir = "/usr/share/vitxi/backend/storage/",
		rsync = {
				owner = true,
				group = true
		}
}
sync {
		default.rsyncssh,
		source = "/var/lib/vitxi/",
		host = "$ip_standby",
		targetdir = "/var/lib/vitxi/",
		rsync = {
				binary = "/usr/bin/rsync",
				owner = true,
				group = true,
				archive = "true",
				_extra = {
						"--include=wizard.conf",
						"--exclude=*"
						}
				}
}
sync {
		default.rsync,
		source="/var/lib/asterisk/",
		host = "$ip_standby",
		targetdir = "/home/sync/var/spool/asterisk/sqlite3_temp/",
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
		default.rsyncssh,
		source = "/var/lib/asterisk/agi-bin/",
		host = "$ip_standby",
		targetdir = "/var/lib/asterisk/agi-bin/",
		rsync = {
				owner = true,
				group = true
		}
}
sync {
		default.rsyncssh,
		source = "/var/lib/asterisk/priv-callerintros/",
		host = "$ip_standby",
		targetdir = "/var/lib/asterisk/priv-callerintros",
		rsync = {
				owner = true,
				group = true
		}
}
sync {
		default.rsyncssh,
		source = "/var/lib/asterisk/sounds/",
		host = "$ip_standby",
		targetdir = "/var/lib/asterisk/sounds/",
		rsync = {
				owner = true,
				group = true
		}
}
sync {
		default.rsyncssh,
		source = "/var/lib/vitalpbx",
		host = "$ip_standby",
		targetdir = "/var/lib/vitalpbx",
		rsync = {
				binary = "/usr/bin/rsync",
				owner = true,
				group = true,			
				archive = "true",
				_extra = {
						"--exclude=*.lic",
						"--exclude=*.dat",
						"--exclude=dbsetup-done",
						"--exclude=cache"
						}
				}
}
sync {
		default.rsyncssh,
		source = "/etc/asterisk",
		host = "$ip_standby",
		targetdir = "/etc/asterisk",
		rsync = {
				owner = true,
				group = true
		}
}
EOF
systemctl enable lsyncd.service
systemctl start lsyncd.service

echo -e "*** Done Step 4 ***"
echo -e "4"	> step.txt

create_mariadb_replica:
echo -e "************************************************************"
echo -e "*                Create MariaDB replica                    *"
echo -e "************************************************************"
#Remove anonymous user from MySQL
mysql -uroot -e "DELETE FROM mysql.user WHERE User='';"
#Configuration of the First Master Server (Master)
cat > /etc/mysql/mariadb.conf.d/50-server.cnf << EOF
#
# These groups are read by MariaDB server.
# Use it for options that only the server (but not clients) should see

# this is read by the standalone daemon and embedded servers
[server]

# this is only for the mysqld standalone daemon
[mysqld]

#
# * Replica Settings
#

server_id=1
log-basename=master
log-bin
binlog-format=row

#
# * Basic Settings
#

user                    = mysql
pid-file                = /run/mysqld/mysqld.pid
basedir                 = /usr
datadir                 = /var/lib/mysql
tmpdir                  = /tmp
lc-messages-dir         = /usr/share/mysql
lc-messages             = en_US
skip-external-locking

# Broken reverse DNS slows down connections considerably and name resolve is
# safe to skip if there are no "host by domain name" access grants
#skip-name-resolve

# Instead of skip-networking the default is now to listen only on
# localhost which is more compatible and is not less secure.
#bind-address            = 0.0.0.0

#
# * Fine Tuning
#

#key_buffer_size        = 128M
#max_allowed_packet     = 1G
#thread_stack           = 192K
#thread_cache_size      = 8
# This replaces the startup script and checks MyISAM tables if needed
# the first time they are touched
#myisam_recover_options = BACKUP
#max_connections        = 100
#table_cache            = 64

#
# * Logging and Replication
#

# Both location gets rotated by the cronjob.
# Be aware that this log type is a performance killer.
# Recommend only changing this at runtime for short testing periods if needed!
#general_log_file       = /var/log/mysql/mysql.log
#general_log            = 1

# When running under systemd, error logging goes via stdout/stderr to journald
# and when running legacy init error logging goes to syslog due to
# /etc/mysql/conf.d/mariadb.conf.d/50-mysqld_safe.cnf
# Enable this if you want to have error logging into a separate file
#log_error = /var/log/mysql/error.log
# Enable the slow query log to see queries with especially long duration
#slow_query_log_file    = /var/log/mysql/mariadb-slow.log
#long_query_time        = 10
#log_slow_verbosity     = query_plan,explain
#log-queries-not-using-indexes
#min_examined_row_limit = 1000

# The following can be used as easy to replay backup logs or for replication.
# note: if you are setting up a replication slave, see README.Debian about
#       other settings you may need to change.
#server-id              = 1
#log_bin                = /var/log/mysql/mysql-bin.log
expire_logs_days        = 10
#max_binlog_size        = 100M

#
# * SSL/TLS
#

# For documentation, please read
# https://mariadb.com/kb/en/securing-connections-for-client-and-server/
#ssl-ca = /etc/mysql/cacert.pem
#ssl-cert = /etc/mysql/server-cert.pem
#ssl-key = /etc/mysql/server-key.pem
#require-secure-transport = on

#
# * Character sets
#

# MySQL/MariaDB default is Latin1, but in Debian we rather default to the full
# utf8 4-byte character set. See also client.cnf
character-set-server  = utf8mb4
collation-server      = utf8mb4_general_ci

#
# * InnoDB
#

# InnoDB is enabled by default with a 10MB datafile in /var/lib/mysql/.
# Read the manual for more InnoDB related options. There are many!
# Most important is to give InnoDB 80 % of the system RAM for buffer use:
# https://mariadb.com/kb/en/innodb-system-variables/#innodb_buffer_pool_size
#innodb_buffer_pool_size = 8G

# this is only for embedded server
[embedded]

# This group is only read by MariaDB servers, not by MySQL.
# If you use the same .cnf file for MySQL and MariaDB,
# you can put MariaDB-only options here
[mariadb]
log-bin
server_id=1
log-basename=master
binlog-format=mixed

# This group is only read by MariaDB-10.5 servers.
# If you use the same .cnf file for MariaDB of different versions,
# use this group for options that older servers don't understand
[mariadb-10.5]
EOF
systemctl restart mariadb

#Create a new user on the Master
mysql -uroot -e "CREATE USER 'vitalpbx_replica' @'%' IDENTIFIED BY 'vitalpbx_replica';"
mysql -uroot -e "GRANT REPLICATION SLAVE ON *.* TO 'vitalpbx_replica'@'$ip_standby' IDENTIFIED BY 'vitalpbx_replica';"
mysql -uroot -e "FLUSH PRIVILEGES;"

#Get bin_log on Master-1
file_server_1=`mysql -uroot -e "show master status" | awk 'NR==2 {print $1}'`
position_server_1=`mysql -uroot -e "show master status" | awk 'NR==2 {print $2}'`

#Once the data has been copied, you can release the lock on the master by running UNLOCK TABLES
mysql -uroot -e "UNLOCK TABLES;"

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

#Configuration of the Second Master Server (Replica)
cat > /tmp/50-server.cnf << EOF
#
# These groups are read by MariaDB server.
# Use it for options that only the server (but not clients) should see

# this is read by the standalone daemon and embedded servers
[server]

# this is only for the mysqld standalone daemon
[mysqld]

#
# * Replica Settings
#

server_id=2
log-basename=replica
log-bin
binlog-format=row
binlog-do-db=replica_db

#
# * Basic Settings
#

user                    = mysql
pid-file                = /run/mysqld/mysqld.pid
basedir                 = /usr
datadir                 = /var/lib/mysql
tmpdir                  = /tmp
lc-messages-dir         = /usr/share/mysql
lc-messages             = en_US
skip-external-locking

# Broken reverse DNS slows down connections considerably and name resolve is
# safe to skip if there are no "host by domain name" access grants
#skip-name-resolve

# Instead of skip-networking the default is now to listen only on
# localhost which is more compatible and is not less secure.
#bind-address            = 127.0.0.1

#
# * Fine Tuning
#

#key_buffer_size        = 128M
#max_allowed_packet     = 1G
#thread_stack           = 192K
#thread_cache_size      = 8
# This replaces the startup script and checks MyISAM tables if needed
# the first time they are touched
#myisam_recover_options = BACKUP
#max_connections        = 100
#table_cache            = 64

#
# * Logging and Replication
#

# Both location gets rotated by the cronjob.
# Be aware that this log type is a performance killer.
# Recommend only changing this at runtime for short testing periods if needed!
#general_log_file       = /var/log/mysql/mysql.log
#general_log            = 1

# When running under systemd, error logging goes via stdout/stderr to journald
# and when running legacy init error logging goes to syslog due to
# /etc/mysql/conf.d/mariadb.conf.d/50-mysqld_safe.cnf
# Enable this if you want to have error logging into a separate file
#log_error = /var/log/mysql/error.log
# Enable the slow query log to see queries with especially long duration
#slow_query_log_file    = /var/log/mysql/mariadb-slow.log
#long_query_time        = 10
#log_slow_verbosity     = query_plan,explain
#log-queries-not-using-indexes
#min_examined_row_limit = 1000

# The following can be used as easy to replay backup logs or for replication.
# note: if you are setting up a replication slave, see README.Debian about
#       other settings you may need to change.
#server-id              = 1
#log_bin                = /var/log/mysql/mysql-bin.log
expire_logs_days        = 10
#max_binlog_size        = 100M

#
# * SSL/TLS
#

# For documentation, please read
# https://mariadb.com/kb/en/securing-connections-for-client-and-server/
#ssl-ca = /etc/mysql/cacert.pem
#ssl-cert = /etc/mysql/server-cert.pem
#ssl-key = /etc/mysql/server-key.pem
#require-secure-transport = on

#
# * Character sets
#

# MySQL/MariaDB default is Latin1, but in Debian we rather default to the full
# utf8 4-byte character set. See also client.cnf
character-set-server  = utf8mb4
collation-server      = utf8mb4_general_ci

#
# * InnoDB
#

# InnoDB is enabled by default with a 10MB datafile in /var/lib/mysql/.
# Read the manual for more InnoDB related options. There are many!
# Most important is to give InnoDB 80 % of the system RAM for buffer use:
# https://mariadb.com/kb/en/innodb-system-variables/#innodb_buffer_pool_size
#innodb_buffer_pool_size = 8G

# this is only for embedded server
[embedded]

# This group is only read by MariaDB servers, not by MySQL.
# If you use the same .cnf file for MySQL and MariaDB,
# you can put MariaDB-only options here
[mariadb]

# This group is only read by MariaDB-10.5 servers.
# If you use the same .cnf file for MariaDB of different versions,
# use this group for options that older servers don't understand
[mariadb-10.5]
EOF

scp /tmp/50-server.cnf root@$ip_standby:/etc/mysql/mariadb.conf.d/50-server.cnf
ssh root@$ip_standby "systemctl restart mariadb"

#Create a new user on the Replica
cat > /tmp/grand.sh << EOF
#!/bin/bash
mysql -uroot -e "CHANGE MASTER TO MASTER_HOST='$ip_master', MASTER_USER='vitalpbx_replica', MASTER_PASSWORD='vitalpbx_replica', MASTER_LOG_FILE='$file_server_1', MASTER_LOG_POS=$position_server_1;"
mysql -uroot -e "START SLAVE;"
EOF
scp /tmp/grand.sh root@$ip_standby:/tmp/grand.sh
ssh root@$ip_standby "chmod +x /tmp/grand.sh"
ssh root@$ip_standby "/tmp/./grand.sh"
ssh root@$ip_standby "rm /tmp/grand.sh"
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
