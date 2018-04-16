---
layout: "post"
title: "readme"
date: "2018-04-12 16:39"
---
IPABuildShell
==

`IPABuildShell` 一个Xcode projects 快速打包工具，`IPABuildShell` 主要使用bash脚本语言编写，通过执行脚本并简单的配置参数就能实现自动配置证书、授权描述文件等并完成IPA生成。

```

fenglihaideMacBook-Pro: fenglihai$ /Users/itx/IPABuildShell/IPABuildShell.sh -h

-p <Xcode Project File>: 指定Xcode project. 如果使用该参数，脚本会自动在当前目录查看Xcode Project 文件
-g: 获取当前项目git的版本数量
-l: 列举可用的codeSign identity.
-x: 脚本执行调试模式.
-b: 设置Bundle Id.
-d: 设置debug模式，默认release模式.
-t: 设置为测试(开发)环境，默认为生产环境.
-r <体系结构>,例如：-r 'armv7'或者 -r 'arm64' 或者 -r 'armv7 arm64' 等
-c <development|app-store|enterprise>: development 内部分发，app-store商店分发，enterprise企业分发
-h: 帮助.

```

功能
==
- 支持Xcode 8.0至8.3.2(其他版本还没试过)
- 支持ipa签名方式：development、app-store、enterprise，即内部分发、商店分发、企业分发
- 自动匹配描述文件(Provisioning Profile)
- 自动匹配签名身份(Code Signing Identity)
- 兼容`单工程`和`多工程`(Workplace)项目
- 只支持单个target
- 自动修改内部版本号(Build)
- 可配置（接口）生产环境和开发环境
- 可配置Bundle Id
- 可指定debug、release模式
- 可指定构建的Architcture(arm64、armv7)
- 自动格式化IPA名称，例如: `MyApp_20170321_222303_开发环境_企业分发_2.1.0(67).ipa`、`MyApp_20170321_222403_生产环境_商店分发_2.1.0(68).ipa` (注1)
- 自动修复企业分发ipa的XcentFile文件
- 自动校验ipa签名
- 同时支持个人开发者账号和企业开发者账号
- 日志输出以及备份每次打包的ipa以及日志


注1：
 IPA分发途径，支持常用的3种： 
    内部测试：用于给我们内部人员测试使用的，用户通过使用“同步助手”、“APP助手”等工具安装 
    商店分发：用于提交到商店审核，用户通过在App Store下载安装 
    企业分发：用户部署到服务器，用户通过扫描二维码或使用浏览器点击链接下载安装 

安装
==

1. ##### 安装Xcodeproj

  `[sudo] gem install xcodeproj`

2. ##### 检查是否安装成功

  ` xcodeproj --help`

使用
==

1. ##### 配置config.plist文件
  - LoginPwd 填写系统用户**密码** (可选，当keychains访问权限不足，则要用户密码解锁)
  - InterfaceEnvironmantConfig (可选，注2)
    - EnvironmentConfigFileName 填写你接口环境配置文件名
    - EnvironmentconfigVariableName 填写你接口环境配置文件里面的变量名
  - Individual
    - devCodeSignIdentity 填写你的个人开发者账号的**开发环境签名身份**
    - disCodeSignIdentity 填写你的个人开发者账号的**生产环境签名身份**
    - bundleIdentifiers 填写你的个人开发者账号应用的**bundle identifier**
  - Enterprise
    - devCodeSignIdentity 填写你的企业开发者账号的**开发环境签名身份**
    - disCodeSignIdentity 填写你的企业开发者账号的**生产环境签名身份**
    - bundleIdentifiers 填写你的企业开发者账号应用的**bundle identifier**


  - ![  config.plist](https://raw.githubusercontent.com/aa335418265/images/master/ipabuildshell_1.png)

  注2:

  在项目中，为了方便统一修改接口的**正式/测试(生产/开发)环境**，所以我们在指定文件**BMNetworkingConfguration.h**中定义了一个全局变量作为**正式/测试(生产/开发)环境**的开关!如果
  你的项目配置生产和开发环境方式和这里不同，请忽略该配置。![  config.plist](https://raw.githubusercontent.com/aa335418265/images/master/ipabuildshell_4.png)
  
默认情况下脚本打包是生产环境，也就是不带`-t`参数。


 
2. #### 添加描述文件

  将描述文件拷贝添加到`MobileProvisionFile`目录。
  脚本会根据工程的bundle identifier匹配到对应的授权文件并进行签名配置。

3. ##### 构建ipa

  打开终端，cd到工程目录执行下面命令开始构建你的ipa

  ```
  /脚本目录/IPABuildShell.sh -c development
  ```
![  打包](https://raw.githubusercontent.com/aa335418265/images/master/ipabuildshell_2.png)
![打包](https://raw.githubusercontent.com/aa335418265/images/master/ipabuildshell_3.png)

3. ##### 设置脚本快捷方式(可选)

  打开终端，将下面代码“**脚本目录**”替换成相应的路径，并执行。

  ```
  echo "alias IPABuildShell.sh=/脚本目录/IPABuildShell.sh" >> ~/.bash_profile
  source ~/.bash_profile

  ```

  检查是否配置成功

  ```
  IPABuildShell.sh -h
  ```
结合Jenkins神兵利器(略)
==

  配合Jenkins，通过在Jenkins中添加Shell的方式来完成IPA构建，那么可以实现真正的一键自动化打包。打包的事情就可以交给测试的同学自己去构建了......


  ![ 打包](https://raw.githubusercontent.com/aa335418265/images/master/ipabuildshell_5.png)

  ![打包](https://raw.githubusercontent.com/aa335418265/images/master/ipabuildshell_6.png)


^_^
==
各位大佬，如果觉得对你有帮助，高抬贵手star一下呗！

不愿意？

您别走，

听我说，

我有三个理由：

求求您了！

求求您了！

求求您了！
