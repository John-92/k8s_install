#!/bin/bash
# DESC: 系统初始化设置:selinux,ulimit,firewalld,time_zone
config_file="/root/k8s/install.config"
LOG_PATH="/root/k8s/k8s.log"
INSTALL_DIR="/root/k8s/"
DOCKERVERSION=18.06.3

#下载常用软件
yum_regularSoftware(){
yum install -y wget vim gcc net-tools expect ipvsadm ipset ansible lrzsz telnet ntp git
}

#修改yum国内源--配置成阿里云，要先配置yum源，再安装软件
yum_config(){
    cd /etc/yum.repos.d/
    mv CentOS-Base.repo CentOS-Base.repo_bak
    #可能wegt无法安装,安装yum源和epel源
    #wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo
    curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo
    curl -o /etc/yum.repos.d/epel.repo http://mirrors.aliyun.com/repo/epel-7.repo
     yum clean all
     yum makecache    
}



#设置免密登录
login_withoutPasswd(){
    #生成非对称加密算法的公私钥
    if [ ! -e ~/.ssh/id_dsa ];then
       echo "id_dsa not exit"
       ssh-keygen -t dsa -P '' -f ~/.ssh/id_dsa
    fi
    cat ~/.ssh/id_dsa.pub >> ~/.ssh/authorized_keys
    services_info=`cat ${config_file} | awk '/service/,/^$/{if($0 !~ "^$|service")print}'`
    #shell中IFS指定换行符号，不然遇到空白符就会换行，是个坑
    IFS_OLD=$IFS
    IFS=$'\n'
    #将本机的公钥复制到所有远程机器的authorized_keys文件中
    for service_info in ${services_info}
      do
    {
    ip=`echo $service_info |awk '{print $1}'`
        user=`echo $service_info |awk '{print $2}'`
        password=`echo $service_info |awk '{print $3}'`
        host_name=`echo $service_info |awk '{print $4}'`
    ping -c1 -W1 $ip &> /dev/null
    if [ $? -eq 0  ];then
        echo "$host_name" >> ip.txt
           #调用expect,注意
EOF一定要顶格，后面也不能有空格
        /usr/bin/expect <<-EOF
        spawn ssh-copy-id ${user}@$host_name
        expect {
            "*yes/no*" { send "yes\r"; exp_continue }
            "*password:" { send "$password\r" }
        }
        expect eof
EOF
    fi
    #验证免密效果
       ssh $host_name "date"
    if [ $? -ne 0 ];then
    echo "???????????${host_name}没有实现免密设置???????????">>${LOG_PATH}
    #isChecked是标记，用于判断能否免密登录，如果被附值则说明设置失败
    isChecked=1
    fi
    }&
    done
    IFS=$IFS_OLD
    echo "免密设置完成"
   >> ${LOG_PATH} 
   
     #-z判断变量是否被附过值，附过值说明一定服务器没被设置免密
     [[  -z ${isChecked} ]]&&echo "#########免密设置成功############"||echo "***********免密设置不成功***********">>${LOG_PATH}
}

set_selinux(){
   echo "设置selinux"
   /usr/sbin/setenforce 0
   sleep 2
   /usr/sbin/setenforce 0
   sleep 2
   /usr/sbin/setenforce 0
   sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
   sed -i '/^SELINUX=/ s/enforcing/disabled/' /etc/selinux/config
   [ $? -eq 0 ] && echo "###############selinux 设置完成!###############" >> ${LOG_PATH}
}
# set ulimit
ulimit_config(){
   echo "设置ulimit"
   #这种方式一步到位？？
   #ulimit -SHn 65535
 cat >> /etc/security/limits.conf <<EOF
    * soft nproc 65535
    * hard nproc 65535
    * soft nofile 65535
    * hard nofile 65535
 #注意EOF一定要顶格
EOF
   [ $? -eq 0 ] && echo "###############ulimit 设置完成!###############" >> ${LOG_PATH}
}

# set firewalld
stop_firewalld(){
  systemctl stop firewalld
  systemctl disable firewalld
  echo "###############firewalld 设置完成\!###############" >> ${LOG_PATH}
}
#set time_zone
time_zone(){
   ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
   echo "###############time_zone 设置完成!###############" >> ${LOG_PATH}
}


#set hostname
hostname_set(){
    echo "开始配置host"
    #ip_addrs=`ip a|grep inet|grep -v 127.0.0.1|grep -v inet6|awk '{print $2}'|tr -d "addr:"|cut -d "/" -f1`
    #获取ens33网卡的ip
    ip_addrs=`ifconfig ens33 |grep -E "inet\W" |awk '{print $2}'`
    for ip_addr in  $ip_addrs
    do
        #install.config是安装配置文件
        #选择ip到最近一个空行之间的内容，并去除ip和空行的内容
        config_ips=`cat ${config_file} | awk '/ip/,/^$/{if($0 !~ "^$|ip"  )print}' |cut -d " " -f1`
        for config_ip in ${config_ips}
        do
          if [ $ip_addr == $config_ip ];then
          role=`cat ${config_file} | awk '/ip/,/^$/{if($0 !~ "^$|ip"  )print}' |grep ${ip_addr} |cut -d " " -f2`
         #设置主机名
          centos_version=`cat /etc/redhat-release|sed -r 's/.* ([0-9]+)\..*/\1/'`
            if [ ${centos_version} -eq 6 ]; then
               echo $role >> /etc/sysconfig/network
            fi
             #  centos-7:
             if [ ${centos_version} -eq 7 ]; then
               /usr/bin/hostnamectl set-hostname  $role
             fi
            fi
          done
     done
     #配置主机名查询静态表,当hosts已经配置时就不再配置,将没有添加的配置添加进去？？
     needAddHosts=`cat ${config_file} | awk '/ip/,/^$/{if($0 !~ "^$|ip"  )print}'`
     #不是完全匹配也会有返回值
     amount=`grep "$needAddHosts" /etc/hosts | wc -l`
     needAddHostAmount=`echo "$needAddHosts" |wc -l`
     if [ $amount != $needAddHostAmount ];then
        echo "将配置添加到hosts文件中"
        cat ${config_file} | awk '/ip/,/^$/{if($0 !~ "^$|ip"  )print}' >> /etc/hosts
        if [ $? -eq 0 ];then
           echo "hostname has configured successfully"
        else
           echo "some mistakes during configuring"
           exit 1
        fi
     else
         echo "已经添加到hosts文件中"
     fi
     echo "###############主机配置完成###############"   >> ${LOG_PATH}                 
}

ntp_install(){
    echo "installing ntp"
    #精确匹配是否已经成功安装ntp与ntpdate，-w是精确匹配，如果是包含字符串中包含ntp的则不会被匹配到，比如fontpackages，-E是扩展正则，|是扩展正则
    ntp_amount=`rpm -qa |grep -Ew "(ntp|ntpdate)" |wc -l`
    if [ ${ntp_amount} -lt 2 ];then
    echo "??????????ntp尚未安装?????????" >> ${LOG_PATH}
    else    
    #启动ntp
    /usr/bin/systemctl start ntpd
    /usr/bin/systemctl enable ntpd
    #同步时间对准锚点
    #注意命令要写绝对路径,先通过whereis ntpdate去找可执行命令所在位置
    crontab <<-EOF
    0 */1 * * * /usr/sbin/ntpdate ntp5.aliyun.com
EOF
  fi
    echo "###############时间同步配置并成功安装################" >> ${LOG_PATH}
}


swap_shutdown(){
    swap_amount=`free -m |awk '/Swap/{print $2}'`
    if [ $swap_amount -ne 0 ];then
    #临时关闭磁盘分区swap
    swapoff -a
    #swapoff /dev/centos/swap
    #修改配置文件 - /etc/fstab
    sed -ri  /swap/'s/^(.*)$/#\1/g' /etc/fstab 
    fi
    [ `free -m |awk '/Swap/{print $2}'` -eq 0 ] && echo "######永久关闭磁盘分区swap#######"|| echo "无法关闭磁盘分区swap" >> ${LOG_PATH}
    
}

#RHEL / CentOS 7上的一些用户报告了由于iptables被绕过而导致流量路由不正确的问题。创建/etc/sysctl.d/k8s.conf文件，
iptables_config(){
cat <<EOF >  /etc/sysctl.d/k8s.conf
vm.swappiness = 0
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
#使配置生效
modprobe br_netfilter
#让内核参数生效
sysctl -p /etc/sysctl.d/k8s.conf
modules=`lsmod | grep br_netfilter |wc -l` && if [ $modules -ne 0 ];then echo "##########br_netfilter模块安装完成############" >> ${LOG_PATH} ;else echo "##########br_netfilter模块安装失败############" >> ${LOG_PATH} ; fi
}

start_ipvs(){
      #添加需要加载的模块
      cat > /etc/sysconfig/modules/ipvs.modules <<EOF
      #!/bin/bash
       modprobe -- ip_vs
       modprobe -- ip_vs_rr
       modprobe -- ip_vs_wrr
       modprobe -- ip_vs_sh
       modprobe -- nf_conntrack_ipv4
EOF
      #授权、执行、检查模块是否执行
      chmod 755 /etc/sysconfig/modules/ipvs.modules && bash /etc/sysconfig/modules/ipvs.modules && lsmod | grep -e ip_vs_* 
      if [ $? -eq 0 ];then echo "#############ipvs加载完成################";else echo "*******没有加载完成********";fi
 
}


#安装docker-ce,如果没有开启docker,则无法检查docker的版本
docker_ce_install(){
    if [ `rpm -qa |grep docker` ];then
    OlddockerVersion=`docker version |grep -A 2 'Server'|grep Version|tr -d ' '|awk -F '[:|-]' '{print $2}'`
    if [ $OlddockerVersion != "$DOCKERVERSION" ];then
    #卸载已有的docker
    yum remove -y docker-ce docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-selinux docker-engine-selinux docker-engine
    else
    echo "已经安装了$DOCKERVERSION版本的docker">>${LOG_PATH}
    #直接退出函数，注意shell的return只能是数字
    return 0
    fi
    fi
    #要http,不要https,或者--no-check-certificate
      wget -O /etc/yum.repos.d/docker-ce.repo http://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/centos/docker-ce.repo
    #安装指定版本的docker-ce
     #yum list docker-ce.x86_64 --showduplicates |sort -r  #检查是否有18.06.3.ce-3.el7 这一版本的docker
    yum -y install --setopt=obsoletes=0 docker-ce-18.06.3.ce-3.el7
    #备份docker.service文件
    cp /usr/lib/systemd/system/docker.service{,bak}
    sed -ri /-H/'s&(-H.*)&&' /usr/lib/systemd/system/docker.service
    dockerVersion=`docker version |grep -A 2 'Server'|grep Version|tr -d ' '|awk -F '[:|-]' '{print $2}'`
    
    [ $? -eq 0 ]&&echo "#######docker安装完成,docker版本:${dockerVersion}#########" || echo "docker没有安装成功##########" >>${LOG_PATH}
    systemctl start docker
    systemctl enable docker
}
##不是master不需要配置

ansible_config(){
    which ansible
    if [ $? -ne 0 ];then
      echo "？？？？？？？？？ansible 还没安装？？？？？？？？？？"
      exit 1
    fi
    cp /etc/ansible/ansible.cfg{,.bak}
    #对ansible加速配置,host_key_checking配置为禁用ssh key检查，log_path设置，ansible连接加速开启
    sed -ri '/host_key_checking/s%#(.*)%\1%g;/log_path/s%#(.*)%\1%;/accelerate_port/s%#(.*)%\1%' /etc/ansible/ansible.cfg
    #ansible添加主机列表
    cat ${config_file} | awk '/ansible-config/,/^$/{if($0 !~ "^$|ansible-config"  )print}'  > ${INSTALL_DIR}/ansibleHost
    line=`cat $INSTALL_DIR/ansibleHost |wc -l`
    #获取主机列表文件和需要配置文件的重复项,-d只显示重复的值（显示一次）,-D显示全部重复内容(重复几次显示几次)
    #whole_lines=`cat /etc/ansible/hosts ansibleHost |sort|uniq -d`
    #获取两个文件都有的内容，<表示第一个文件有，而第二个文件没有的内容，>则反过来，-y显示两个文件内容
    #whole_lines=`diff /etc/ansible/hosts ansibleHost  -y|grep -v "<"|wc -l`
    whole_lines=`diff /etc/ansible/hosts $INSTALL_DIR/ansibleHost |grep  ">"|wc -l`
   #如果数量相等关系(表示没有复制过去)，则需要配置
    #if [[ $whole_lines != $((2 * ${line})) ]];then
    if [[ $whole_lines ==  ${line} ]];then
       cat $INSTALL_DIR/ansibleHost >> /etc/ansible/hosts
    fi
    #whole_lines重新赋值，0表示已经复制过去
    whole_lines=`diff /etc/ansible/hosts $INSTALL_DIR/ansibleHost |grep  ">"|wc -l`
    if [[ $whole_lines ==  0 ]];then
       echo "########ansible配置成功########" >> ${LOG_PATH}
       #将配置文件分发到其他主机上，多个文件用命令行如何操作？
       #ansible all:\!192.168.52.134 -m copy -a "src=/root/k8s/ dest=/root/k8s/"
       
	    if [ `hostname` == "master" ];then
          ansible k8s -m copy -a "src=/root/k8s/ dest=/root/k8s/"
		fi
      
    else
         echo "******ansible配置失败*********">> ${LOG_PATH}
    fi
}



main(){
    #!和 -e需要有空格
  if [ ! -e $config_file ];then
   echo "no config_file"
   exit 1
  fi
   IP=`ifconfig ens33|awk '/inet\W/{print $2}'`
  echo "$IP $(date +"%Y-%m-%d %H:%M:%S")正在安装环境" >> ${LOG_PATH}
  
  yum_config
  yum_regularSoftware
  set_selinux
  ulimit_config
  stop_firewalld
  time_zone
  ntp_install
  hostname_set
  login_withoutPasswd
  swap_shutdown
  iptables_config
  start_ipvs
  docker_ce_install
  ansible_config
}

main