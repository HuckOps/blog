---
title: 基于K8s的LNMP架构（HPA）
tags:
    - 容器技术
categories: 云计算
date: 2021-09-04 23:58:34


---

# LNMP

LNMP架构是常见的Web全栈架构，目前许多网站都使用了该种方法进行开发。对于常见的传统架构，服务器可靠性不是很高，Nginx、PHP或者MySQL任意一个中间件发生故障都可能导致生产环境Web页面崩溃。或者PHP网站在发生高并发时，如果使用传统架构的单节点可能会服务器性能不足，不足以支持过高的并发量，所以将LNMP迁移到k8s架构上会解决以上问题。

# 架构设计

## MySQL

MySQL是一种有状态服务，MySQL在某些情况下如果发生故障性退出可能会出现服务无法再次启动的情况，所以数据库一般都不会被创建到容器中，通常都是将数据库使用一个物理节点进行运行的。

本实例是使用k8s对LNMP进行全架构迁移，所以将数据库生成到k8s容器中。数据库中存放的是重要的业务数据，无论在任何时候都要保证数据不丢失。对于k8s的pod，其文件具有易失性，如果在pod发生故障的时候会重新生成pod，原pod中的文件将不会被保存。理论上来说，可以使用pod的hostPath进行本地存储，但是通常k8s集群都是多台主机运行的，数据库副本也通常是飘移的，当数据库副本被调度到其他节点的时候原数据将不会被保留。所以这里可以使用一个外部文件存储StorageClass生成PVC进行动态挂载，MySQL调度到其他节点时也可以读取到数据文件。

从上边描述可以看出，如果数据库发生故障的时候可能会影响业务，但是对于k8s来说，使用MySQL做主从幅值和读写分离是比较麻烦的，所以在使用Deployment的时候不宜生成多副本。本处只生成一个副本进行测试。

## PHP和Nginx

在LNMP架构中，Nginx作为前端和反向代理服务器。当Nginx接收到请求时，如果是静态文件请求，则Nginx直接进行响应。当请求为php请求时，nginx将请求转发给php后端服务进行逻辑处理。

从上边原理可见得，lnmp请求处理是由两部分构成的，也并非所有请求都要经过这两个环节，所以可能会出现两个环节的负载/请求量不同的情况。在使用k8s做lnmp架构时，可以将nginx和php进行分离，分别使用多副本动态调度，以应对不同环节的不同负载状况。

# 配置文件
## PVC声明

本实例已经事先声明了Cephfs的StorageClass，故本处不再赘述。直接使用声明好的SC进行PVC申请声明。
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name:  mysql
  namespace: dz
spec:
  resources:
    requests:
      storage: 5Gi
  accessModes:
    - ReadWriteMany
  storageClassName: ceph

---

apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name:  dz
  namespace: dz
spec:
  resources:
    requests:
      storage: 5Gi
  accessModes:
    - ReadWriteMany
  storageClassName: ceph
```
mysql PVC作为mysql的文件存储PVC，主要存储数据库生成的文件以及其他数据库产生的数据文件。前边有提及到不使用容器生成数据库的原因，还有一个较大的原因是使用网络存储，无论是网络延迟还是存储网络掉线都可能会影响数据库的服务稳定性。本处使用的权限符可以是ReadWriteOnce，这样只可被一个容器进行挂载，也可以满足mysql单副本的要求。

dz PVC用来存放php程序。php程序的前后端通常都是不分离的，php程序中有很大一部分都是静态资源，所以这个PVC要被设置成ReadWriteMany，用以挂载到多个容器上，实现nginx和php的文件共享。

## MySQL资源声明
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
  namespace: dz
spec:
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:5.6
        resources:
          limits:
            memory: "512Mi"
            cpu: "500m"
        ports:
        - containerPort: 3306
        livenessProbe:
          tcpSocket:
            port: 3306
          initialDelaySeconds: 90
          periodSeconds: 10
        env:
          - name: MYSQL_ROOT_PASSWORD
            value: sjh080815
        volumeMounts:
          - mountPath: /var/lib/mysql
            name: mysql-pvc
      volumes:
        - name: mysql-pvc
          persistentVolumeClaim:
              claimName: mysql
              
---

apiVersion: v1
kind: Service
metadata:
  name: mysql
  namespace: dz
spec:
  selector:
    app: mysql
  ports:
  - name: mysql
    port: 3306
    targetPort: 3306 
```
创建一个单副本的MySQL Deployment，将前边创建的pvc挂载给pod，并且创建一个3306端口的监听。因为数据库初始化过程是比较缓慢的，所以创建生存探针的时候将initialDelaySeconds时间设置较长，若90秒内端口还未正常工作，控制器将会删除这个pod重新生成。90秒后如果正常运行即每10s进行一次端口探测，若不存在就重生pod。

创建一个Service，将pod生成一个endpoint后映射到cluster IP上，将容器的3306端口映射到cluster IP上。

## PHP资源声明
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: php
  namespace: dz
spec:
  selector:
    matchLabels:
      app: php
  template:
    metadata:
      labels:
        app: php

    spec:
      containers:
      - name: php
        image: registry.cn-hangzhou.aliyuncs.com/sjh080815/php-mysqli
        resources:
          limits:
            memory: "128Mi"
            cpu: "500m"
        ports:
        - containerPort: 9000
        livenessProbe:
          tcpSocket:
            port: 9000
          initialDelaySeconds: 20
          periodSeconds: 10
        volumeMounts:
          - name: php-static
            mountPath: /usr/share/nginx/html
      volumes:
        - name: php-static
          persistentVolumeClaim:
              claimName: dz

---

apiVersion: autoscaling/v1
kind: HorizontalPodAutoscaler
metadata:
  name: php
  namespace: dz
spec:
  maxReplicas: 5
  minReplicas: 2
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: php
  targetCPUUtilizationPercentage: 85



---

apiVersion: v1
kind: Service
metadata:
  name: php
  namespace: dz
spec:
  selector:
    app: php
  ports:
  - name: php
    port: 9000
    targetPort: 9000
```
生成一个php Deployment，挂载PVC到容器中，设置一个生存探针，防止容器发生故障。

创建一个HPA，以应对高并发场景。HPA扩展的依据是当CPU使用量超过85%，当容器的CPU使用量超过85%时，调度器创建新的pod。

创建一个Service，将php pod网络映射到cluster中。创建Service创建了endpoint，每当生成一个pod的时候，selector会自动选择出带有指定label的pod加入到endpoint中。

## Nginx资源声明
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
  namespace: dz
data:
  default.conf: |-
    server {
        listen 80;
        server_name localhost;
        root /usr/share/nginx/html;
        index index.html index.php;
 
        location ~ \.php$ {
            root /usr/local/nginx/html;
            fastcgi_pass php:9000;
            fastcgi_param SCRIPT_FILENAME /usr/share/nginx/html$fastcgi_script_name;
            include fastcgi_params;
            fastcgi_connect_timeout 60s;
            fastcgi_read_timeout 300s;
            fastcgi_send_timeout 300s;
        }
    }
---

apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: dz
spec:
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx
        resources:
          limits:
            memory: "128Mi"
            cpu: "500m"
        ports:
        - containerPort: 80
        livenessProbe:
            httpGet:
                path: /
                port: 80
            initialDelaySeconds: 20
            periodSeconds: 10
        volumeMounts:
          - name: php-static
            mountPath: /usr/share/nginx/html
          - name: config
            mountPath: /etc/nginx/conf.d/default.conf
            subPath: default.conf
      volumes:
        - name: php-static
          persistentVolumeClaim:
              claimName: dz
        - name: config
          configMap:
              name: nginx-config

---


apiVersion: autoscaling/v1
kind: HorizontalPodAutoscaler
metadata:
  name: nginx
  namespace: dz
spec:
  maxReplicas: 5
  minReplicas: 2
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: nginx
  targetCPUUtilizationPercentage: 85


---

apiVersion: v1
kind: Service
metadata:
  name: nginx
  namespace: dz
spec:
  selector:
    app: nginx
  ports:
  - name: nginx
    port: 80
    targetPort: 80 
```
创建一个nginx配置ConfigMap，在生成nginx Deployment的时候将ConfigMap中的数据以文件的方式进行挂载，创建livenessProbe探针检测80端口。

创建HPA和Service，原理和上边的php相同。

## Ingress配置
```yaml
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: dz
  namespace: dz
  labels:
      name: dz
spec:
  ingressClassName: nginx
  rules:
  - host: www.test.com
    http:
      paths:
      - pathType: ImplementationSpecific
        path: /
        backend:
            serviceName: nginx
            servicePort: 80
```
创建一个Ingress，将```www.test.com```解析指向nginx的Service中，访问时nginx被轮询，当单pod发生故障的时候对业务的影响会被降到最小。