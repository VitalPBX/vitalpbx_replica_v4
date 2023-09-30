VitalPBX Replica (Version 4)
=====
Sometimes it is necessary to have an exact copy of a VitalPBX server in another remote datacenter.<br>

For these we have created a script that performs this function automatically.<br>

The objective of this implementation is to guarantee that if something happens to the main server, the remote can continue with the work of the main server.<br>

Note:<br>
Because this is a deployment in two remote sites, it is not possible to have the automatic toggle facility as it is done in the High Availability configuration with the floating IP.<br>
The VitalPBX team does not provide support for systems in an HA environment because it is not possible to determine the environment where it has been installed.

## Example:<br>
![VitalPBX HA](https://github.com/VitalPBX/vitalpbx_replica_v4/blob/main/MasterSlaveVitalPBX4Replica.png)

-----------------
## Prerequisites
In order to install VitalPBX in replica, you need the following:<br>
a.- 2 IP addresses.<br>
b.- Install VitalPBX Version 4.0 in two servers with similar characteristics.<br>
c.- Lsyncd.

## Configurations
We will configure in each server the IP address and the host name. Go to the web interface to: <strong>Admin>System Settinngs>Network Settings</strong>.<br>
First change the Hostname, remember press the <strong>Check</strong> button.<br>
Disable the DHCP option and set these values<br>

| Name          | Master                 | Standby               |
| ------------- | ---------------------- | --------------------- |
| Hostname      | voip01.domain.com      | voip02.domain.com     |
| IP Address    | 192.168.10.61          | 192.168.10.62         |
| Netmask       | 255.255.255.0          | 255.255.255.0         |
| Gateway       | 192.168.10.1           | 192.168.10.1          |
| Primary DNS   | 8.8.8.8                | 8.8.8.8               |
| Secondary DNS | 8.8.4.4                | 8.8.4.4               |

## Install Dependencies
Install the necessary dependencies on both servers<br>
<pre>
[root@<strong>voip01.domain.com</strong> ~]# apt -y install wget lsyncd
</pre>

## Create authorization key for the Access between the two servers without credentials

Create key in Server <strong>1</strong>
<pre>
[root@server<strong>1</strong> ~]# ssh-keygen -f /root/.ssh/id_rsa -t rsa -N '' >/dev/null
[root@server<strong>1</strong> ~]# ssh-copy-id root@<strong>192.168.10.62</strong>
Are you sure you want to continue connecting (yes/no)? <strong>yes</strong>
root@192.168.10.62's password: <strong>(remote server root’s password)</strong>

Number of key(s) added: 1

Now try logging into the machine, with:   "ssh 'root@192.168.10.62'"
and check to make sure that only the key(s) you wanted were added. 

[root@server<strong>1</strong> ~]#
</pre>

## Script
Now copy and run the following script<br>
<pre>
[root@ vitalpbx<strong>1</strong> ~]# mkdir /usr/share/vitalpbx/replica
[root@ vitalpbx<strong>1</strong> ~]# cd /usr/share/vitalpbx/replica
[root@ vitalpbx<strong>1</strong> ~]# wget https://raw.githubusercontent.com/VitalPBX/vitalpbx_replica_v4/master/vpbxreplica.sh
[root@ vitalpbx<strong>1</strong> ~]# chmod +x vpbxreplica.sh
[root@ vitalpbx<strong>1</strong> ~]# ./vpbxreplica.sh

************************************************************
*  Welcome to the VitalPBX high availability installation  *
*                All options are mandatory                 *
************************************************************
IP Master................ > <strong>192.168.10.61</strong>
IP Standby............... > <strong>192.168.10.62</strong>
************************************************************
*                   Check Information                      *
*        Make sure you have internet on both servers       *
************************************************************
Are you sure to continue with this settings? (yes,no) > <strong>yes</strong>
</pre>

Then, to see the slave’s status, run the command below.
<pre>
[root@<strong>voip02.domain.com</strong> ~]# mysql -uroot -e "SHOW SLAVE STATUS\G;"
</pre>

If everything is correct you should see the following statuses in Yes
<pre>
Slave_IO_Running: Yes
Slave_SQL_Running: Yes
</pre>

## Note
If you want both servers to have the same settings in the Asterisk files and keep the changes in the Asterisk database (astdb.sqlite3), when starting the backup server run the following command in the console:<br>
<pre>
[root@server<strong>1-2</strong> ~]# vpbxstart
</pre>

