#!/bin/bash
####
#网络基本配置，静态ip,dns等设置
#####
#机器初始化  $1 机器名   $2 机器内网静态IP   $3 机器网关IP
linux_netwok(){
gateway=$3
#修改机器名
hostnamectl set-hostname $1
#修改hosts
echo "$2 $1" >> /etc/hosts
cd /etc/sysconfig/network-scripts
#将此文件备份，否则一个网卡有多个ip
if [ -f /etc/sysconfig/network-scripts/ifcfg-ens33.dhcp ];then
mv ifcfg-ens33.dhcp bak-ens33.dhcp
fi

#修改静态地址
cp ifcfg-ens33 bakifcfg-ens33
sed -i 's/dhcp/static/' /etc/sysconfig/network-scripts/ifcfg-ens33
echo 'IPADDR='$2'' >> /etc/sysconfig/network-scripts/ifcfg-ens33
echo 'NETMASK=255.255.255.0' >> /etc/sysconfig/network-scripts/ifcfg-ens33
echo 'GATEWAY='${gateway:-192.168.52.2}'' >> /etc/sysconfig/network-scripts/ifcfg-ens33
echo 'DNS1=114.114.114.114' >> /etc/sysconfig/network-scripts/ifcfg-ens33
echo 'DNS2=8.8.8.8' >> /etc/sysconfig/network-scripts/ifcfg-ens33
#重启网络
systemctl restart network
#重新刷新网卡ip
ip addr flush dev ens33
ifdown ens33
ifup ens33

IPNUM=`ifconfig ens33 | grep  'inet\W' |wc -l`
if [ ${IPNUM} -gt 1 ];then
echo "继续重新刷新网卡" 
ip addr flush dev ens33
ifdown ens33
ifup ens33
fi
if [ `ifconfig ens33 | grep  'inet\W' |wc -l` -gt 1 ];then
     echo "网络配置有问题，请排查"
else
   echo "#########################网络初始化完成#########################"
fi
}

main(){
    read -p "请输入机器名" nodename
     read -p "请输入机器内网静态IP" ip_config
     read -p "请输入机器内网网关,如果不设置则默认为192.168.52.2" ip_gateway
      linux_netwok $nodename $ip_config $ip_gateway
}
main