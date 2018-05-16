---
layout: "post"
title: "readme"
date: "2018-05-04 11:55"
---
IPABuildShell
==

`IPABuildShell` 一个轻量级 iOS 快速自动打包工具，在你电脑已经导入证书签名的前提下，最简单的只需要一键`./IPABuildShell.sh` 就能生成IPA。当然，如果你需要更多的功能，详见帮助`-h | --help`

```

fenglihaideMacBook-Pro: fenglihai$ /Users/itx/IPABuildShell/IPABuildShell.sh -h

Usage:autoMathSign.sh -[abcdptx] [--enable-bitcode YES/NO] [--auto-buildversion YES/NO] ...
可选项：
  -a | --archs 	<armv7|arm64|armv7 arm64> 指定构建架构集，例如：-a 'armv7'或者 -a 'arm64' 或者 -a 'armv7 arm64' 等
  -b | --bundle-id bundleId 设置Bundle Id
  -c | --channel <development|app-store|enterprise> 指定分发渠道，development 内部分发，app-store商店分发，enterprise企业分发
  -d | --provision-dir dir 指定授权文件目录，默认会在~/Library/MobileDevice/Provisioning Profiles 中寻找
  -p | --keychain-password passoword 指定访问证书时解锁钥匙串的密码，即开机密码
  -t | --configration-type  <Debug|Release> Debug 调试模式, Release 发布模式
  -h | --help 帮助.
  -x 脚本执行调试模式.
  --enable-bitcode <YES/NO> 是否开启BitCode.
  --auto-buildversion <YES/NO> 是否自动修改构建版本号（设置为当前项目的git版本数量）
```

功能
==

- <font color=#006400 size=3>自动匹配描述文件(Provisioning Profile)</font>
- <font color=#006400 size=3>自动匹配签名身份(Code Signing Identity)</font>
- 允许指定授权文件目录,脚本将只在该目录匹配授权文件
- 支持Xcode `8.0`至`9.3`
- 支持ipa签名方式：development、app-store、enterprise，即内部分发、商店分发、企业分发
- 支持workplace、cocoapod
- 自动关闭BitCode，并可配置开关
- 可配置自动修改内部版本号(Build Version)
- 可配置修改接口生产环境和开发环境
- 可配置指定新的Bundle Id
- 可配置指定构建Debug、Release模式
- 可指定构建的Architcture(arm64、armv7)
- 自动格式化IPA名称，例如: `MyApp_20170321_222303_开发环境_企业分发_2.1.0(67).ipa`、`MyApp_20170321_222403_生产环境_商店分发_2.1.0(68).ipa` (注1)
- 自动修复8.3以下版本的Xcode打包缺失XcentFile文件
- 自动校验ipa签名
- 格式化日志输出



注1：

 IPA分发途径，支持常用的3种：

    - 内部测试：用于给我们内部人员测试使用的，用户通过使用“同步助手”、“APP助手”等工具安装
    - 商店分发：用于提交到商店审核，用户通过在App Store下载安装
    - 企业分发：用于部署到服务器，用户通过扫描二维码或使用浏览器点击链接下载安装

安装
==

1. #### IPABuildShell.sh 下载到本地,并赋予可执行权限
  `chmod +x /路径/IPABuildShell.sh `
2. #### 安装xcpretty（可选）
  `sudo gem install xcpretty`

  用来格式化xcodebuild输出日志，建议安装


使用
==





  打开终端，`cd`到工程目录，执行下面命令开始构建你的ipa

  ```
  /脚本目录/IPABuildShell.sh
  ```
![](http://ozhqm0ga1.bkt.clouddn.com/8199e1d7a213105433b557c291876294.png)
![](http://ozhqm0ga1.bkt.clouddn.com/9dbfcf031faca442f1dcc30d1790cbb8.png)



user.xcconfig 文件说明
==

如果你觉得执行脚本时，经常要指定一些些固定的参数，那么你的可以在`user.xcconfig`配置这些参数：
```c++

//脚本全局参数配置文件(脚本参数优先于全局配置参数)


//keychain解锁密码，即PC开机密码。通常只有在第一次执行脚本时候需要。相当于脚本参数 -p | --keychain-password
UNLOCK_KEYCHAIN_PWD =

//构建模式：Debug/Release ；默认 Release。相当于脚本参数 -t | --configration-type
CONFIGRATION_TYPE=

//架构集 ：arm64/armv7/armv7 arm64 ；默认 arm64。相当于脚本参数 -a | --archs
ARCHS =

//是否启动bitcode ：YES/NO 关闭； 默认 NO。相当于脚本参数 --enable-bitcode
ENABLE_BITCODE =

//是否自动修改build version：YES/NO ；默认 NO （取当前项目git的版本数量作为build version ）。相当于脚本参数 --auto-buildversion
AUTO_BUILD_VERSION =

//授权文件目录，默认在~/Library/MobileDevice/Provisioning Profiles。相当于脚本参数 -d | --provision-dir
PROVISION_DIR=

//例如在AppDelegate.h 声明变量 static BOOL isProduction = NO;来控制接口的生产环境和开发环境
//指定配置接口生产环境的文件名。相当于脚本参数 --env-filename
API_ENV_FILE_NAME =
//指定配置接口生产环境的变量名。相当于脚本参数 --env-varname
API_ENV_VARNAME =
//指定配置接口生产环境的变量值：YES/NO 相当于脚本参数 --env-production
API_ENV_PRODUCTION =



```

最后
==
如果本工具对你有帮助，麻烦Star一个！谢谢！

欢迎大家给项目提出任何意见和建议，我会尽我所能为大家解决！
```
# ----------------------------------------------------------------------
# author:       冯立海
# email:        335418265@qq.com
# ----------------------------------------------------------------------
```



### 版本更新日志

```
#--------------------------------------------
# 2018/05/16
# 版本：3.0.0
# 1. 自动匹配授权文件和签名（移除config.plist配置）
# 2. 优化授权文件匹配算法，取有效期最长授权文件
# 3. 调整脚本参数,详见-h
# 4. 优化代码
# 5. 兼容长参数
# 6. 增加全局配置文件user.xcconfig
#--------------------------------------------
# 2018/05/04
# 版本：2.1.0
# 1. 移除使用xcodepro（xceditor.rb）,使用xcodebuild 的`-xcconfig `参数来实现签名等配置修改
# 2. 保持工程配置(project.pbxproj)文件不被修改
#--------------------------------------------
# 2018/04/19
# 版本：2.0.6
# 1. 优化build函数代码。
# 2. 增加xcpretty 来格式化日志输出
# 3. 支持xcode9（8.0~9.3）
#
#--------------------------------------------
# 2018/04/12
# 版本：2.0.5
# 优化：
# 1. 增加一个“修改Bundle Id”功能。如-b com.xxx.xx。
# 2. 优化一些代码
#
#--------------------------------------------
# 2018/03/22
# 版本：2.0.4
# 优化：默认构建ipa支持armch 为 arm64。（因iOS 11强制禁用32位）
#
#--------------------------------------------
# 版本：2.0.3
# 2018/03/12
#
# 优化：对授权文件mobiprovision有效期检测，授权文件有效期小于90天，强制打包失败！
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
# 2016/04/01
#
# 版本：2.0.1
# 优化：
#		为了节省打包时间，在打开发环境的包时，只打armv7
#		profileType==development 时，设置archs=armv7 （向下兼容） ，否则archs为默认值：arm64 和armv7。
#
#--------------------------------------------
# 2016/03/08
#
# 版本：2.0.0
# 优化：
#		1.去掉可配置签名、授权文件，并修改为自动匹配签名和授权文件！
#
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


```
