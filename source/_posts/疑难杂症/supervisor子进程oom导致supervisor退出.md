---
title: supervisor子进程oom导致supervisord进程退出问题排查
date: 2024-06-04 21:53:34
categories: 运维技术
---

# 背景

这个问题出自一个线上故障。uwsgi进程查询数据库内容过大导致进程oom，同时supervisord进程接收到一个退出信号后进行优雅退出。因为supervisord进程退出所以uwsgi进程没有被重新拉起导致业务故障。

# 架构说明

![1780764958822.png](https://s3.huckops.xyz/1780764958822.png)

本次故障主要涉及项目中心服，中心服用到的技术栈为python3.11+uwsgi+mysql+mongo+redis，中心服由两个进程构成。uwsgi作为中心服的api接口，也是用户访问的主业务入口，push服务是一个异步推送服务，主要为用户推送信令以及处理一些异步指令。这两个进程都由supervisor进程管理，supervisor以apt方式进行安装。

# 现场描述

uwsgi服务发布了新的版本，新增了评论检测功能（6月4号，历史原因，说不得）导致mongodb查询量剧增，查询结果超级大，之后uwsgi服务和push服务以及supervisor服务全部异常退出（不难想到是oom导致的进程被kill），nginx仍可正常进行服务，但用户访问报错500，errorlog报找不到uwsgi.sock(nginx反向代理到uwsgi的socket文件)，服务不可用。

# 故障恢复

hotfix线上查询问题并发新版，重新拉起supervisor发现uwsgi和push服务都能正常被拉起，故障恢复。

# 故障复盘

因为uwsgi新版本的原因导致mongodb查询量剧增，且返回的查询内容非常大，导致mongodb的shard和uwsgi双双因为oom异常退出，但是从既往经验来看，有几个比较大的疑点：
1. uwsgi发生oom，supervisor按道理应该不会退出，而是supervisor重新拉起uwsgi进程才对，为什么这里退出了？
2. 既然进程发生oom了，那么进程一定会被杀死，但是杀死的机制是什么，为什么连supervisor都会被杀死？难道是乱杀？那为什么所有机器的supervisor进程都是退出的？
3. uwsgi作为supervisor的子进程，子进程oom，到底是谁给的kill信号？内核？其他组件？会不会系统把子进程和父进程当同类一起杀掉？

# 故障排查

发生oom问题，最直接的排查方法就是检查内核日志，但是我们本次排查的主要目的是排斥supervisor也一起异常退出了。
通关检查内核日志发现以下一些相关的日志：

> 以下日志脱敏处理，去掉了前两列，时间都是Jun  3 20:08:04

```
kernel: [18504827.972952] Call Trace:
kernel: [18504827.972964]  dump_stack+0x6b/0x83
kernel: [18504827.972968]  dump_header+0x4a/0x1f4
kernel: [18504827.972971]  oom_kill_process.cold+0xb/0x10
kernel: [18504827.972978]  out_of_memory+0x1bd/0x4e0
kernel: [18504827.972982]  __alloc_pages_slowpath.constprop.0+0xbcc/0xc90
kernel: [18504827.972985]  __alloc_pages_nodemask+0x2de/0x310
kernel: [18504827.972989]  pagecache_get_page+0x175/0x390
kernel: [18504827.972991]  filemap_fault+0x6a2/0x900
kernel: [18504827.973019]  ext4_filemap_fault+0x2d/0x50 [ext4]
kernel: [18504827.973022]  __do_fault+0x34/0x170
kernel: [18504827.973024]  handle_mm_fault+0x124d/0x1c00
kernel: [18504827.973029]  do_user_addr_fault+0x1b8/0x400
kernel: [18504827.973032]  exc_page_fault+0x78/0x160
kernel: [18504827.973037]  ? asm_exc_page_fault+0x8/0x30
kernel: [18504827.973038]  asm_exc_page_fault+0x1e/0x30
kernel: [18504827.973041] RIP: 0033:0x560db0e3f8d1
...
kernel: [18504827.973163] Swap cache stats: add 0, delete 0, find 0/0
kernel: [18504827.973164] Free swap  = 0kB
kernel: [18504827.973165] Total swap = 0kB
kernel: [18504827.973166] 33458335 pages RAM
kernel: [18504827.973167] 0 pages HighMem/MovableOnly
kernel: [18504827.973167] 553944 pages reserved
kernel: [18504827.973168] 0 pages hwpoisoned
...
kernel: [18504827.973685] oom-kill:constraint=CONSTRAINT_NONE,nodemask=(null),cpuset=/,mems_allowed=0-1,global_oom,task_memcg=/system.slice/supervisor.service,task=uwsgi,pid=3861657,uid=52160
kernel: [18504827.973711] Out of memory: Killed process 3861657 (uwsgi) total-vm:49128384kB, anon-rss:15311648kB, file-rss:0kB, shmem-rss:58156kB, UID:52160 pgtables:31148kB oom_score_adj:0
```

从内核日志能看到uwsgi因为oom问题被内核kill掉，这个是符合预期的，但是没见到supervisor的退出日志，也就是说supervisor不是由内核kill掉的，所以kernel日志并不能排查出具体原因。

我们继续检查supervisor日志，看到这些：

```
2024-06-03 20:08:06,001 WARN received SIGTERM indicating exit request
...
2024-06-03 20:08:18,536 INFO waiting for cloud-game-push_04, cloud-game-push_05, cloud-game-push_06, cloud-game-push_07, cloud-game-push_00, cloud-game-push_01, cloud-game-push_02, cloud-game-push_03, cloud-game-push_08, cloud-game-push_09, cloud-game-logic-worker-2, cloud-game-logic-worker-5, cloud-game-logic-worker-10, cloud-game-logic-worker-16, cloud-game-logic-worker-17, cloud-game-logic-worker-14, cloud-game-logic-worker-15 to die
...
2024-06-03 20:08:38,745 WARN stopped: cloud-game-push_00 (terminated by SIGINT)
...
```

从日志可以看到，在uwsgi服务oom后的两秒supervisor收到了一个SIGTERM信号，supervisor服务开始进入退出流程。

奇怪了，如果是因为oom发生的kill理论上来说是由内核发出信号，应该内核会有日志记录，但是又没查到内核日志里有kill信号发出，查询陷入僵局。

# 故障复现

写一个简单的内存炸弹，模拟进程oom

```python
a = []
while True:
    a.append("test")
```

使用supervisor托管进程：

```ini
[program:test]
command=python3 /root/test.py
process_name=%(program_name)s
numprocs=1
```

观察到内存溢出时出现了同样的问题：

```
# supervisorctl stop all
unix:///var/run/supervisor.sock no such file
# dmesg -T
[Thu Jun  6 00:53:53 2024] oom-kill:constraint=CONSTRAINT_NONE,nodemask=(null),cpuset=/,mems_allowed=0,global_oom,task_memcg=/system.slice/supervisor.service,task=python3,pid=1823,uid=0
[Thu Jun  6 00:53:53 2024] Out of memory: Killed process 1823 (python3) total-vm:2665068kB, anon-rss:1624352kB, file-rss:4kB, shmem-rss:0kB, UID:0 pgtables:5104kB oom_score_adj:0
# cat supervisor/supervisord.log
2024-06-06 00:59:31,736 WARN exited: cat (terminated by SIGKILL; not expected)
2024-06-06 00:59:31,839 INFO spawned: 'cat' with pid 1916
2024-06-06 00:59:32,842 INFO success: cat entered RUNNING state, process has stayed up for > than 1 seconds (startsecs)
2024-06-06 01:00:09,418 WARN exited: cat (terminated by SIGKILL; not expected)
2024-06-06 01:00:09,486 INFO spawned: 'cat' with pid 1934
2024-06-06 01:00:10,170 INFO waiting for cat to die
2024-06-06 01:00:11,187 WARN stopped: cat (terminated by SIGTERM)
```

同样的溢出，同样的日志，同样的supervisor，同样的收到一个信号。

现在可以确定一个事情，跟系统环境应该时没关系的了，测试环境使用的时debian12，生产环境时debian10。

此时，我怀疑时supervisor版本原因，生产环境使用4.2.5版本，测试环境也是4.2.5，所以使用pip安装其他版本supervisor后手动拉起supervisor：

```shell
supervisord -c /etc/supervisor/supervisord.conf
```

这是奇怪的点就来了，测试进程挂了之后supervisor竟然还能正常运行：

```
root@debian:/var/log# supervisorctl status
cat                              RUNNING   pid 1983, uptime 0:00:41
root@debian:/var/log# supervisorctl status
cat                              STARTING
```

那就基本可以断定，supervisor进程异常退出应该和进程启动和托管方式有关了，那么，apt安装的supervisor时systemd服务托管的，难道时systemd服务导致的？

# 从supervisor的service文件入手

拿到supervisor的systemd配置文件：

```
[Unit]
Description=Supervisor process control system for UNIX
Documentation=http://supervisord.org
After=network.target

[Service]
ExecStart=/usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
ExecStop=/usr/bin/supervisorctl $OPTIONS shutdown
ExecReload=/usr/bin/supervisorctl -c /etc/supervisor/supervisord.conf $OPTIONS reload
KillMode=process
Restart=on-failure
RestartSec=50s

[Install]
WantedBy=multi-user.target
```
看起来没有什么奇怪的地方，那难道是有什么莫默认配置在作妖？查看systemd配置文档发现了几个奇怪的参数：
```
✓ ManagedOOMSwap=
✓ ManagedOOMMemoryPressure=
✓ ManagedOOMMemoryPressureLimit=
✓ ManagedOOMPreference=
✓ OOMPolicy=
```
看起来这些参数都是配置一些systemd的OOM控制，这里主要关注OOMPolicy，他的说明很有意思：

```
      <varlistentry>
        <term><varname>DefaultOOMPolicy=</varname></term>

        <listitem><para>Configure the default policy for reacting to processes being killed by the Linux
        Out-Of-Memory (OOM) killer or <command>systemd-oomd</command>. This may be used to pick a global default for the per-unit
        <varname>OOMPolicy=</varname> setting. See
        <citerefentry><refentrytitle>systemd.service</refentrytitle><manvolnum>5</manvolnum></citerefentry>
        for details. Note that this default is not used for services that have <varname>Delegate=</varname>
        turned on.</para>

        <xi:include href="version-info.xml" xpointer="v243"/></listitem>
      </varlistentry>
```
也就是说，supervisor没有配置OOMPolicy的话，一定是匹配到了默认值，检查systemd默认配置发现默认值:

```
# cat /etc/systemd/system.conf  | grep OOM
#DefaultOOMPolicy=stop
```

真相来了，直接莽一波去翻systemd代码，看到一个enum和一个函数：
```c
void unit_defaults_init(UnitDefaults *defaults, RuntimeScope scope) {
        assert(defaults);
        assert(scope >= 0);
        assert(scope < _RUNTIME_SCOPE_MAX);

        *defaults = (UnitDefaults) {
                .std_output = EXEC_OUTPUT_JOURNAL,
                .std_error = EXEC_OUTPUT_INHERIT,
                .restart_usec = DEFAULT_RESTART_USEC,
                .timeout_start_usec = manager_default_timeout(scope),
                .timeout_stop_usec = manager_default_timeout(scope),
                .timeout_abort_usec = manager_default_timeout(scope),
                .timeout_abort_set = false,
                .device_timeout_usec = manager_default_timeout(scope),
                .start_limit_interval = DEFAULT_START_LIMIT_INTERVAL,
                .start_limit_burst = DEFAULT_START_LIMIT_BURST,

                /* On 4.15+ with unified hierarchy, CPU accounting is essentially free as it doesn't require the CPU
                 * controller to be enabled, so the default is to enable it unless we got told otherwise. */
                .cpu_accounting = cpu_accounting_is_cheap(),
                .memory_accounting = MEMORY_ACCOUNTING_DEFAULT,
                .io_accounting = false,
                .blockio_accounting = false,
                .tasks_accounting = true,
                .ip_accounting = false,

                .tasks_max = DEFAULT_TASKS_MAX,
                .timer_accuracy_usec = 1 * USEC_PER_MINUTE,

                .memory_pressure_watch = CGROUP_PRESSURE_WATCH_AUTO,
                .memory_pressure_threshold_usec = MEMORY_PRESSURE_DEFAULT_THRESHOLD_USEC,

                .oom_policy = OOM_STOP,
                .oom_score_adjust_set = false,
        };
}
typedef enum OOMPolicy {
        OOM_CONTINUE,          /* The kernel or systemd-oomd kills the process it wants to kill, and that's it */
        OOM_STOP,              /* The kernel or systemd-oomd kills the process it wants to kill, and we stop the unit */
        OOM_KILL,              /* The kernel or systemd-oomd kills the process it wants to kill, and all others in the unit, and we stop the unit */
        _OOM_POLICY_MAX,
        _OOM_POLICY_INVALID = -EINVAL,
} OOMPolicy;
```

也就是说，默认状态下oom的策略被设置为stop，当Unit的子进程挂了的时候，整个Unit也会被kill掉。当业务进程oom的时候systemd-oomd和systemd并没有失能，systemd-oomd捕获到业务进程挂了之后按照oom策略向supervisor的Unit发去一个退出信号，所以当业务进程oom后的几秒钟supervisor也退出了（supervisor要等业务进程退出），所以上面日志所有时间和进程接收到的信号也就解释起来非常合理了。
