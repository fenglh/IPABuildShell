---
layout: "post"
title: "readme"
date: "2018-04-20 16:25"
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
- 支持Xcode `8.0`至`9.3`
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
- 格式化xcodebuild编译过程日志输出
- 日志输出颜色区分


注1：

 IPA分发途径，支持常用的3种：

    - 内部测试：用于给我们内部人员测试使用的，用户通过使用“同步助手”、“APP助手”等工具安装
    - 商店分发：用于提交到商店审核，用户通过在App Store下载安装
    - 企业分发：用于部署到服务器，用户通过扫描二维码或使用浏览器点击链接下载安装

安装
==

1. ##### 安装Xcodeproj

  `[sudo] gem install xcodeproj`

2. ##### 检查是否安装成功

  ` xcodeproj --help`

3. ##### 安装xcpretty（可选）
  `gem install xcpretty`

  用来格式化xcodebuild输出日志，建议安装

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
  - Enterprise （可选，注3）
    - devCodeSignIdentity 填写你的企业开发者账号的**开发环境签名身份**
    - disCodeSignIdentity 填写你的企业开发者账号的**生产环境签名身份**
    - bundleIdentifiers 填写你的企业开发者账号应用的**bundle identifier**

    ![  config.plist](https://raw.githubusercontent.com/aa335418265/images/master/ipabuildshell_1.png)

  注2:

    在项目中，为了方便统一修改接口的**正式/测试环境**，所以我们在指定文件**BMNetworkingConfguration.h**中定义了一个全局变量作为**正式/测试环境**的开关!
  
    ![  config.plist](https://raw.githubusercontent.com/aa335418265/images/master/ipabuildshell_4.png)

  注3：

  如果没有企业开发者账号可以忽略此配置。

2. #### 添加描述文件

  拷贝描述授权文件(`xxx.mobileprovision`)拷贝添加到`MobileProvisionFile`目录。


3. ##### 构建ipa

  打开终端，`cd`到工程目录，执行下面命令开始构建你的ipa

  ```
  /脚本目录/IPABuildShell.sh -c development
  ```

  ![](http://ozhqm0ga1.bkt.clouddn.com/2c78165d78800abb14bb17c389e95d95.png)
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
===

  配合Jenkins，通过在Jenkins中添加Shell的方式来完成IPA构建，那么打包的事情就可以交给测试的同学自己去构建了......


  ![ 打包](https://raw.githubusercontent.com/aa335418265/images/master/ipabuildshell_5.png)

  ![打包](https://raw.githubusercontent.com/aa335418265/images/master/ipabuildshell_6.png)


最后
==
如果本工具对你有帮助，麻烦Star一个！谢谢！

也欢迎各位提出给项目提出任何意见和建议。
```
# ----------------------------------------------------------------------
# author:       冯立海
# email:        335418265@qq.com
# ----------------------------------------------------------------------
```



### 版本更新日志

```
#--------------------------------------------
# 2016/03/06
#
# 版本：1.0.0
# 功能：
#		1.显示Build Settings 签名配置
#		2.获取git版本数量，并自动更改build号为版本数量号
#		3.日志文本log.txt输出
#		4.自动匹配签名和授权文件
#		5.支持workplace、多个scheme
#		6.校验构建后的ipa的bundle Id、签名、支持最低iOS版本、arm体系等等
#		7.构建前清理缓存,防止xib更改没有被重新编译
#		8.备份历史打包ipa以及log.txt
#		9.可更改OC代码，自动配置服务器测试环境or生产环境
#		10.格式化输出ipa包名称：name_time_开发环境_企业分发_1.0.0(168).ipa

# 备注：
#		1.security 命令会报警告,忽略即可:security: SecPolicySetValue: One or more parameters passed to a function were not valid.
#		2.支持Xcode8.0及以上版本（8.0前没有测试过）
#--------------------------------------------
# 2016/03/08
#
# 版本：2.0.0
# 优化：
#		1.去掉可配置签名、授权文件，并修改为自动匹配签名和授权文件！
#
#--------------------------------------------
# 2016/04/01
#
# 版本：2.0.1
# 优化：
#		为了节省打包时间，在打开发环境的包时，只打armv7
#		profileType==development 时，设置archs=armv7 （向下兼容） ，否则archs为默认值：arm64 和armv7。
#
#--------------------------------------------
# 2017/08/05
#
# 版本：2.0.2
# 优化：兼容xcode8.3以上版本
# xcode 8.3之后使用-exportFormat导出IPA会报错 xcodebuild: error: invalid option '-exportFormat',改成使用-exportOptionsPlist
# Available options: app-store, ad-hoc, package, enterprise, development, and developer-id.
# 当前用到：app-store ,ad-hoc, enterprise, development
#
#--------------------------------------------
# 版本：2.0.3
# 2018/03/12
#
# 优化：对授权文件mobiprovision有效期检测，授权文件有效期小于90天，强制打包失败！
#
#--------------------------------------------
# 2018/03/22
# 版本：2.0.4
# 优化：默认构建ipa支持armch 为 arm64。（因iOS 11强制禁用32位）
#
#--------------------------------------------
# 2018/04/12
# 版本：2.0.5
# 优化：
# 1. 增加一个“修改Bundle Id”功能。如-b com.xxx.xx。
# 2. 优化一些代码
#
#--------------------------------------------
# 2018/04/19
# 版本：2.0.6
# 1. 优化build函数代码。
# 2. 增加xcpretty 来格式化日志输出
# 3. 支持xcode9（8.0~9.3）
#
#--------------------------------------------
```
