---
title: K8S源码构建
date: 2021-09-12 09:36:34
tags:
    - 容器技术
categories: 云计算
---

K8S是使用golang进行编写的，所以在运行的时候需要将golang代码转换成二进制，K8S代码的构建方式有三种，本地构建、容器环境构建和Bazel环境构建。

# 本地构建

和C++项目类似的，大型项目不可能使用命令行逐个进行```go build```，所以可以使用makefile的方法构建项目。

在k8s所有项目中，存在两个MakeFile文件：

* Makefile：描述项目的编译顺序、编译规则和输出。

* Makefile.generated_files： 描述代码生成逻辑。

## Makefile文件解析

```makefile
.PHONY: all
ifeq ($(PRINT_HELP),y)
all:
	@echo "$$ALL_HELP_INFO"
else
all: generated_files
	hack/make-rules/build.sh $(WHAT)
endif
```

这是执行```make all```的第一步，判断了是否为帮助输出，非帮助输出时，执行generated_files，用于代码生成，然后调用```hack/make-rules/build.sh```进行构建，参数```$(WHAT)```为欲构建的组件列表。

追溯到```hack/make-rules/build.sh```文件，其中调用的第一段函数是```kube::golang::build_binaries "$@"```，该段函数进行二进制构建，传入值即为上边说过的```$(WHAT)```。

调用链：

kube::golang::build_binaries -> kube::golang::host_platform(获取平台类型) -> kube::golang::get_physmem(判断内存是否达到标准) -> kube::golang::build_binaries_for_platform(构建指定平台的二进制) -> kube::golang::build_some_binaries(构建二进制) -> go install

# 容器构建

以下为```make release```的构建代码：

```makefile
.PHONY: release release-in-a-container
ifeq ($(PRINT_HELP),y)
release release-in-a-container:
	@echo "$$RELEASE_HELP_INFO"
else
release release-in-a-container: KUBE_BUILD_CONFORMANCE = y
release:
	build/release.sh
release-in-a-container:
	build/release-in-a-container.sh
endif
```

以下为```make quick-release```的构建代码：

```makefile
.PHONY: release-skip-tests quick-release
ifeq ($(PRINT_HELP),y)
release-skip-tests quick-release:
	@echo "$$RELEASE_SKIP_TESTS_HELP_INFO"
else
release-skip-tests quick-release: KUBE_RELEASE_RUN_TESTS = n
release-skip-tests quick-release: KUBE_FASTBUILD = true
release-skip-tests quick-release:
	build/release.sh
endif
```

可以看出，两种构建方式使用的家谱本是同一个，但是```quick-release```多了两个变量```KUBE_RELEASE_RUN_TESTS```和```KUBE_FASTBUILD```。

追溯到```build/release.sh```:

```shell
kube::build::verify_prereqs   #检查构建环境
kube::build::build_image    #构建镜像
kube::build::run_build_command make cross   #构建

if [[ $KUBE_RELEASE_RUN_TESTS =~ ^[yY]$ ]]; then  #是否进行检查/测试
  kube::build::run_build_command make test
  kube::build::run_build_command make test-integration
fi

kube::build::copy_output    #拷贝输出

kube::release::package_tarballs #打包
```

构建时会使用三个容器：

build： 进行构建工作的容器

data： 数据存储容器

sync：同步容器