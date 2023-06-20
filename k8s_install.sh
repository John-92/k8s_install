#！/bin/bash
LOG_PATH=/root/k8s/k8s.log
INSTALL_DIR=/root/k8s

k8s_yumconfigAndInstall(){
    # 配置kubernetes的阿里云yum源
      cat <<EOF > /etc/yum.repos.d/kubernetes.repo
      [kubernetes]
      name=Kubernetes
      baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64
      enabled=1
      gpgcheck=1
      #repo_gpgcheck=1
      repo_gpgcheck=0
      gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF
      #安装指定版本kubelet、kubeadm、kubectl
      #1.kubelet 在群集中所有节点上运行的核心组件, 用来执行如启动pods和containers等操作。
      #2.kubeadm 引导启动k8s集群的命令行工具，用于初始化 Cluster。
      #3.kubectl 是 Kubernetes 命令行工具。通过 kubectl 可以部署和管理应用，查看各种资源，创建、删除和更新各种组件
      #唯独kubelet-1.17.0的版本不能控制？？kubelet会作为其他两个组件的依赖而被安装,1、对kubelet进行降版本yum -y downgrade kubelet-1.17.0 2、分两次安装，先装kubelet-1.17.0，再装其他两个组件
      #downgrade、install与kubelet-1.17.0只能加一个空格
      #yum -y downgrade kubelet-1.17.0
      yum -y install kubelet-1.17.0
      yum -y install kubeadm-1.17.0 kubectl-1.17.0
      systemctl enable kubelet
      #将kubelet 所需的 cgroup 驱动改成systemd,master和node上都要配置,这个操作不是幂等的
      sed -i '/KUBELET_EXTRA_ARGS/s/KUBELET_EXTRA_ARGS=/&--cgroup-driver=systemd/' /etc/sysconfig/kubelet
	  
	  
	  #因为cni1.0+版本都没有flannel命令，需要自行下载,放到cni插件目录/opt/cni/bin/flannel
	  for i in `seq 3`
      do
        wget https://github.com/containernetworking/plugins/releases/download/v0.8.6/cni-plugins-linux-amd64-v0.8.6.tgz
        [ $? -eq 0 ] && echo "下载成功" && break
      done
       [ $? -ne 0 ] && echo "下载不成功" && exit 1
	   mkdir cni
	   tar -zxvf cni-plugins-linux-amd64-v0.8.6.tgz -C cni
	   if [ `hostname` == "master" ];then
	       ansible k8s -m copy -a "src=cni/flannel dest=/opt/cni/bin/"
	   fi
	   chmod +x /opt/cni/bin/flannel
      echo "第一步"
      [ `kubelet --version |awk '{print $2}'` == "v1.17.0" ]  && \
     	  echo "###########安装成功##########" ||  \
		  echo "----------没有安装成功-----" >>${LOG_PATH}
}


docker_acc(){
    #docker配置修改和镜像加速--配置阿里云镜像加速器：
    [ ! -d /etc/docker ] && mkdir /etc/docker
    #EOF之间开头和结尾必须顶格,且EOF后面不能有任何空格
      #"registry-mirrors": ["https://uyah70su.mirror.aliyuncs.com"]
    cat > /etc/docker/daemon.json <<EOF
    {
    "ipv6": true,
    "fixed-cidr-v6": "2001:db8:1::/64",

    "exec-opts": ["native.cgroupdriver=systemd"],
    "log-driver": "json-file",
    "log-opts": {
      "max-size": "100m"
    },
    "storage-driver": "overlay2",
    "storage-opts": [
    "overlay2.override_kernel_check=true"
    ],
    "registry-mirrors": ["https://8q1ili75.mirror.aliyuncs.com"]
   }
EOF
    systemctl daemon-reload
    systemctl restart docker
    #将systemd去除空格
	echo "第二步"
    DockerCgroupdriver=`docker info|grep "Cgroup Driver"| awk -F ':' '{gsub(/^\s+|\s+$/,"",$2);print $2}'`
    [ "$DockerCgroupdriver" == "systemd" ] && \
	    echo "###########docker配置成功修改和镜像加速########" || \
    	echo "--------docker配置没修改成功-----"  >> ${LOG_PATH}
}


 
#在线镜像下载并安装
image_download(){
        # 为Docker配置一下私有源
        sed -i '/registry-mirrors/i"insecure-registries":["k8s.gcr.io", "gcr.io", "quay.io"],' /etc/docker/daemon.json
        systemctl restart docker
		#master和node下载的镜像可以不同
        image_aliyun=(kube-apiserver-amd64:v1.17.1 kube-controller-manager-amd64:v1.17.1 kube-scheduler-amd64:v1.17.1 kube-proxy-amd64:v1.17.1 pause-amd64:3.1 etcd-amd64:3.4.3-0 coredns:1.6.5)
        for image in ${image_aliyun[@]}
        do  
           docker pull registry.cn-hangzhou.aliyuncs.com/google_containers/$image  
           docker tag  registry.cn-hangzhou.aliyuncs.com/google_containers/$image k8s.gcr.io/${image/-amd64/}  
           docker rmi registry.cn-hangzhou.aliyuncs.com/google_containers/$image
        done
		echo "第三步"
        [ `docker images|grep kube-apiserver|wc -l` -ne 0 ]&& \
		  echo "#################镜像下载完成#################" || \
		  echo "-------------镜像下载未成功-----------" >> ${LOG_PATH}
}


#前提systemctl enable kubelet.service???
#创建虚拟网络
master_install(){      
        kubeadm init \
         --apiserver-advertise-address=192.168.52.134 \
         --image-repository registry.aliyuncs.com/google_containers \
         --kubernetes-version v1.17.0 \
         --service-cidr=10.1.0.0/16 \
         --pod-network-cidr=10.244.0.0/16
         #初始化完后执行 
                                                                                                                                  
         mkdir  -p $HOME/.kube                                                                                                                                          
        sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config                                                                                                               
        sudo chown $(id -u):$(id -g) $HOME/.kube/config
		echo "第四步"
        [ $? -eq 0 ] && \
        		echo "########master 初始化完成#############"  >> ${LOG_PATH}
   
}

 distribute_Token(){
     #生成永不过期的token
       kubeadm token create --print-join-command --ttl=0 | grep 'kubeadm join' > ${INSTALL_DIR}/token.txt
	   
       #借助ansible将token分发给各个node主机
       ansible k8s -m copy -e "INSTALL_DIR=/root/k8s" -a "src={{INSTALL_DIR}}/token.txt dest={{INSTALL_DIR}}/token.txt"
	   echo "第五步"
 }

  


kubectl_config(){
    cat << EOF >> ~/.bashrc
    export KUBECONFIG=/etc/kubernetes/admin.conf
EOF
    source ~/.bashrc
    echo "第六步"

    
}


#添加网络插件 flannel
flannelPlugin_Install(){
#因为flannel有了变化，所以只能使用固定的kube-flannel.yml

              #注意这个网址不稳定，直接通过将本地文件复制过去 
             #如果存在已经修改好的yml，则直接跳过下载
           #if [  -f ${INSTALL_DIR}/kube-flannel.yml ];then
           #  for i in `seq 3`
           #  do
           #  wget https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
           #  [ $? -eq 0 ] && echo "下载成功" && break
           #  done
           #  [ $? -ne 0 ] && echo "下载不成功" && exit 1
          
           #  #image: jmgao1983/flannel:latest
           #  #sed -i 's#quay.io#quay-mirror.qiniu.com#g' ${INSTALL_DIR}/kube-flannel.yml    #替换仓库地址
           #  #将install-cni的镜像来源注释掉，换成新的镜像（jmgao1983/flannel,非官方）
           #  #yaml中多了一个空格导致出错
           #  sed -ri '/install-cni/,+2s/[[:blank:]]image/#&/g;/#[[:blank:]]image/p;/#[[:blank:]]image/s%#[[:blank:]]image.*%image: jmgao1983/flannel%g' ${INSTALL_DIR}/kube-flannel.yml
          #fi      
           #  #查看是否有网卡设置，如果没有，则插入网卡 - --iface=ens33 （注意在yaml中有位置要求）,先将上一行复制下来，然后再对复制的行进行修改
           #  if [  "`grep "iface=ens33" kube-flannel.yml`" == "" ];then
           #  sed -i '/kube-subnet-mgr/p;s/kube-subnet-mgr/iface=ens33/g' ${INSTALL_DIR}/kube-flannel.yml|grep -A 2 kube-subnet-mgr
           #  fi
     kubectl apply -f kube-flannel.yml
	 echo "第七步"
   [ `kubectl get pods -n kube-flannel |grep kube-flannel-ds|wc -l` -ne 0 ] && \
     echo "#########flannel安装成功#############"|| \
	 echo "---------flannel没有安装成功--------" >>${LOG_PATH}
}
#需要插入网卡 配置- --iface=ens192 （注意在yaml中有位置要求）
   #sed -n '/\/opt\/bin\/flanneld/{N;N;N;p}' kube-flannel.yml 
   
   #node节点需要添加到集群中
workNode_join(){
         if [ -f ${INSTALL_DIR}/token.txt ];then
            echo "开始加入加点-------------------->">> ${LOG_PATH}
            eval `cat ${INSTALL_DIR}/token.txt` >> ${LOG_PATH} 2>&1
            [ $? -eq 0 ] && \
			echo "###################成功加入节点#########" || \
       		echo "********加入节点有问题请排查******">> ${LOG_PATH}
         else
             echo "??????没有token文件，无法加入节点???????" >> ${LOG_PATH}
         fi
    }
   
main(){
    IP=`ifconfig ens33|awk '/inet\W/{print $2}'`
    echo "$IP于$(date +"%Y-%m-%d %H:%m")正在进行k8s组件的安装" >>${LOG_PATH}
    k8s_yumconfigAndInstall
    docker_acc
    image_download
    kubectl_config
    if [ `hostname` == "master" ];then
      master_install
      flannelPlugin_Install
      distribute_Token
    fi
    if [[ `hostname` =~ "slave" ]];then
    workNode_join
      
    fi
}

main