---
title: K8S代码生成器
date: 2021-09-12 10:42:01
tags:
    - 容器技术
categories: 云计算
---

```makefile
.PHONY: generated_files
generated_files: gen_prerelease_lifecycle gen_deepcopy gen_defaulter gen_conversion gen_openapi
```

generated_files文件定义了代码生成器，以上为k8s默认的几种代码生成器。

# Tags

代码生成器通过Tags识别要生成的代码和代码生成的方式。

## 全局tags

全局tags定义在doc.go中，对整个包中类型自动生成代码。


**占坑，后期填**