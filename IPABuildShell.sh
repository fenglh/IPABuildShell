#!/bin/bash
#--------------------------------------------
# 版本：2.0.0
# 功能：
#		1.显示Build Settings 签名配置
#		2.获取git版本数量，并自动更改build号为版本数量号
#		3.日志文本log.txt输出
#		4.支持可以配置的签名、授权文件等
#		5.支持workplace、多个scheme
#		6.校验构建后的ipa的bundle Id、签名、支持最低iOS版本、arm体系等等
#		7.构建前清理缓存,防止xib更改没有被重新编译
#		8.备份历史打包ipa以及log.txt
#		9.可更改OC代码，自动配置服务器测试环境or生产环境
#		10.格式化输出ipa包名称：name_time_开发环境_企业分发_1.0.0(168).ipa
#		11.设置手动签名
# 作者：
#		fenglh	2016/03/06
# 备注：
#		1.security 命令会报警告,忽略即可:security: SecPolicySetValue: One or more parameters passed to a function were not valid.
#		2.支持Xcode8.0及以上版本（8.0前没有测试过）
#--------------------------------------------
#
# 版本：2.1.0
# 优化：
#		1.去掉可配置签名、授权文件，并修改为自动匹配签名和授权文件！
# 作者：
#		fenglh	2016/03/06
#
#
#

#--------------------------------------------
	# 没有任何修饰符参数 : 原生参数
	# <>  : 占位参数
	# []  : 可选组合
	# ()  : 必选组合
	# |   : 互斥参数
	# ... : 可重复指定前一个参数
	# --  : 标记后续参数类型
#--------------------------------------------


#####################可配置项目#####################

##个人账号：请把个人账号App的BundleId 配置在这里
bundleIdsForPersion=(cn.com.bluemoon.bluehouse, cn.com.bluemoon.wash)
##企业账号：请把企业账号App的BundleId 配置在这里
bundleIdsForEnterprise=(cn.com.bluemoon.oa, cn.com.bluemoon.sfa, cn.com.bluemoon.moonangel.inhouse)

#####################################################


##
devCodeSignIdentityForPersion="iPhone Developer: chao li (4PD2B29433)"
disCodeSignIdentityForPersion="iPhone Distribution: Blue Moon (China) Co., Ltd. (R6L6VZZQ6L)"

devCodeSignIdentityForEnterprise="iPhone Developer: Li Chao (BTTHBUB23E)"
disCodeSignIdentityForEnterprise="iPhone Distribution: Blue Moon ( China ) Co., Ltd."


##环境变量，必须添加，在遇到有中文字符的xcode project时，会报错，貌似没用，暂时留在这里
export LANG=zh_CN.UTF-8

tmpLogFile=/tmp/`date +"%Y%m%d%H%M%S"`.txt
plistBuddy="/usr/libexec/PlistBuddy"
xcodebuild="/usr/bin/xcodebuild"
security="/usr/bin/security"
codesign="/usr/bin/codesign"
ruby="/usr/bin/ruby"
lipo="/usr/bin/lipo"
##默认分发渠道是内部测试
channel='debug'
verbose=true
productionEnvironment=true
debugConfiguration=false
declare -a targetNames
environmentConfigureFileName="BMNetworkingConfiguration.h"


##设置命令快捷方式
function setAliasShortCut
{
	bashProfile=$HOME/.bash_profile
	if [[ ! -f $bashProfile ]]; then
		touch $bashProfile
	fi
	currentShellDir="$( cd "$( dirname "$0"  )" && pwd  )/`basename "$0"`"
	aliasString="alias gn=\"$currentShellDir -g\""
	grep "$aliasString" $bashProfile
	if [[ $? -ne 0 ]]; then
		echo $aliasString > $bashProfile
	fi

}

function usage
{
	setAliasShortCut

	echo "  -p <Xcode Project File>: 指定Xcode project."
	echo "  -g: 获取git版本数量，并自动更改build号为版本数量号，快捷命令:gn (请先在终端执行：source $bashProfile)"
	echo "  -l: 列举可用的codeSign identity."
	echo "  -x: 脚本执行调试模式."
	echo "  -d: 设置debug模式，默认release模式."
	echo "  -t: 设置为测试(开发)环境，默认为生产环境."
	echo "  -c <debug|appstore|enterprise>: 分发渠道：debug内部分发，appstore商店分发，enterprise企业分发"
	echo "  -h: 帮助."
}

##显示可用的签名
function showUsableCodeSign
{
	#先输出签名，再将输出的结果空格' '替换成'#',并赋值给数组。（因为数组的分隔符是空格' '）
	signList=(`$security find-identity -p codesigning -v | awk -F '"' '{print $2}' | tr -s '\n' | tr -s ' ' '#'`)
	for (( i = 0; i < ${#signList[@]}; i++ )); do
		usableCodeSign=`echo ${signList[$i]} | tr '#' ' '`
		usableCodeSignList[$i]=$usableCodeSign
	done
	#打印签名
	for (( i = 0; i < ${#usableCodeSignList[@]}; i++ )); do
		echo "${usableCodeSignList[$i]}"
	done
}

function logit() {
  if [ $verbose == true ]; then
  	echo "	>> $@"
  fi
  echo "	>> $@" >> $tmpLogFile
}

function logitVerbose
{
	echo "	>> $@"
	echo "	>> $@" >> $tmpLogFile
}

##检查xcode project
function checkForProjectFile
{

	##如果没有指定xcode项目，那么自行在当前目录寻找
	if [[ "$xcodeProject" == '' ]]; then
		pwd=`pwd`
		xcodeProject=`find "$pwd" -maxdepth 1  -type d -name "*.xcodeproj"`
	fi

	projectExtension=`basename "$xcodeProject" | cut -d'.' -f2`
	if [[ "$projectExtension" != "xcodeproj" ]]; then	
		echo "Xcode project 应该带有.xcodeproj文件扩展，.${projectExtension}不是一个Xcode project扩展！"
		exit 1
	else
		projectFile="$xcodeProject/project.pbxproj"
		if [[ ! -f "$projectFile" ]]; then
			echo "项目文件:$projectFile 不存在"
			exit 1;
		fi
		logit "发现pbxproj:$projectFile"
	fi


}

##检查是否存在workplace,当前只能通过遍历的方法来查找
function checkIsExistWorkplace
{
	xcworkspace=`find "$xcodeProject/.." -maxdepth 1  -type d -name "*.xcworkspace"`
	if [[ -d "$xcworkspace" ]]; then
		isExistXcWorkspace=true
		logit "发现xcworkspace:$xcworkspace"
	else
		isExistXcWorkspace=false;
	fi
}


##检查配置文件
function checkEnvironmentConfigureFile
{
	environmentConfigureFile=`find "$xcodeProject/.." -maxdepth 5 -path "./.Trash" -prune -o -type f -name "$environmentConfigureFileName" -print| head -n 1`
	if [[ ! -f "$environmentConfigureFile" ]]; then
		haveConfigureEnvironment=false;
		logit "环境配置文件${environmentConfigureFileName}不存在！"
	else
		haveConfigureEnvironment=true;
		logit "发现环境配置文件:${environmentConfigureFile}"
	fi
}

function getEnvirionment
{
	if [[ $haveConfigureEnvironment == true ]]; then
		environmentValue=$(grep "kBMIsTestEnvironment" "$environmentConfigureFile" | grep -v '^//' | cut -d ";" -f 1 | cut -d "=" -f 2 | sed 's/^[ \t]*//g' | sed 's/[ \t]*$//g')
		currentEnvironmentValue=$environmentValue
		logit "当前配置环境kBMIsTestEnvironment:$currentEnvironmentValue"
	fi
	

}


##获取git版本数量
function getGitVersionCount
{
	gitVersionCount=`git -C "$xcodeProject" rev-list HEAD | wc -l | grep -o "[^ ]\+\( \+[^ ]\+\)*"`
	logit "当前版本数量:$gitVersionCount"
}

##根据授权文件，自动匹配授权文件和签名身份

function autoMatchProvisionFile
{
	##授权文件默认放置在和脚本同一个目录下的MobileProvisionFile 文件夹中
	mobileProvisionFileDir="$( cd "$( dirname "$0"  )" && pwd  )/MobileProvisionFile"
	if [[ ! -d "$mobileProvisionFileDir" ]]; then
		echo "授权文件目录${mobileProvisionFileDir}不存在！"
		exit 1
	fi

	matchMobileProvisionFile=''
	for file in ${mobileProvisionFileDir}/*.mobileprovision; do
		applicationIdentifier=`$plistBuddy -c 'Print :Entitlements:application-identifier' /dev/stdin <<< $($security cms -D -i "$file" 2>1 )`
		applicationIdentifier=${applicationIdentifier#*.}
		if [[ "$appBundleId" == "$applicationIdentifier" ]]; then
			getProfileType $file
			if [[ "$profileType" == "$channel" ]]; then
				matchMobileProvisionFile=$file
				logit "匹配到${applicationIdentifier}的${channel}分发渠道的授权文件:$file"
			fi
		fi
	done

	if [[ $matchMobileProvisionFile == '' ]]; then
		echo "无法匹配BundleId=${applicationIdentifier}的${channel}分发渠道的授权文件"
	fi

}

function autoMatchCodeSignIdentity
{
	
	matchCodeSignIdentity=''
	if [[ "${bundleIdsForPersion[@]}" =~ "$appBundleId" ]]; then
		if [[ "$channel" == 'debug' ]]; then
			matchCodeSignIdentity=$devCodeSignIdentityForPersion
		elif [[ "$channel" == 'appstore' ]]; then
			matchCodeSignIdentity==$disCodeSignIdentityForPersion
		fi
	elif [[ "${bundleIdsForEnterprise[@]}" =~ "$appBundleId" ]]; then
		if [[ "$channel" == 'debug' ]]; then
			matchCodeSignIdentity=$devCodeSignIdentityForEnterprise
		elif [[ "$channel" == 'enterprise' ]]; then
			matchCodeSignIdentity=$disCodeSignIdentityForEnterprise
		fi
	else
		echo "无法匹配$BundleId={appBundleId}的应用的签名，请检查是否是个新的应用!"
		exit 1
	fi
	logit "匹配到${applicationIdentifier}的签名:$matchCodeSignIdentity"
}

##这里只取第一个target
function getAllTargets
{
	rootObject=`$plistBuddy -c "Print :rootObject" $projectFile`
	targetList=`$plistBuddy -c "Print :objects:${rootObject}:targets" $projectFile | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'` 
	targets=(`echo $targetList`);#括号用于初始化数组,例如arr=(1,2,3)
	##这里，只取第一个target,因为默认情况下xcode project 会有自动生成Tests 以及 UITests 两个target
	targetId=${targets[0]}
	targetName=`$plistBuddy -c "Print :objects:$targetId:name" $projectFile`
	logit "target名字：$targetName"
	buildTargetNames=(${buildTargetNames[*]} $targetName)



}


function getAPPBundleId
{
	targetId=${targets[0]}
	buildConfigurationListId=`$plistBuddy -c "Print :objects:$targetId:buildConfigurationList" $projectFile`
	buildConfigurationList=`$plistBuddy -c "Print :objects:$buildConfigurationListId:buildConfigurations" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
	buildConfigurations=(`echo $buildConfigurationList`)
	##因为无论release 和 debug 配置中bundleId都是一致的，所以随便取一个即可
	configurationId=${buildConfigurations[0]}
	appBundleId=`$plistBuddy -c "Print :objects:$configurationId:buildSettings:PRODUCT_BUNDLE_IDENTIFIER" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
	logit "appBundleId:$appBundleId"

}



##获取BuildSetting 配置
function showBuildSetting
{
	logitVerbose "======================当前Build Setting 配置======================"

	targetId=${targets[0]}

	buildConfigurationListId=`$plistBuddy -c "Print :objects:$targetId:buildConfigurationList" $projectFile`
	logitVerbose "配置targetId：$buildConfigurationListId"
	buildConfigurationList=`$plistBuddy -c "Print :objects:$buildConfigurationListId:buildConfigurations" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
	buildConfigurations=(`echo $buildConfigurationList`)
	for configurationId in ${buildConfigurations[@]}; do

		configurationName=`$plistBuddy -c "Print :objects:$configurationId:name" "$projectFile"`
		logitVerbose "配置类型: $configurationName"
		# CODE_SIGN_ENTITLEMENTS 和 CODE_SIGN_RESOURCE_RULES_PATH 不一定存在，这里不做判断
		# codeSignEntitlements=`$plistBuddy -c "Print :objects:$configurationId:buildSettings:CODE_SIGN_ENTITLEMENTS" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
		# codeSignResourceRulePath=`$plistBuddy -c "Print :objects:$configurationId:buildSettings:CODE_SIGN_RESOURCE_RULES_PATH" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
		codeSignIdentity=`$plistBuddy -c "Print :objects:$configurationId:buildSettings:CODE_SIGN_IDENTITY" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
		codeSignIdentitySDK=`$plistBuddy -c "Print :objects:$configurationId:buildSettings:CODE_SIGN_IDENTITY[sdk=iphoneos*]" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
		developmentTeam=`$plistBuddy -c "Print :objects:$configurationId:buildSettings:DEVELOPMENT_TEAM" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
		infoPlistFile=`$plistBuddy -c "Print :objects:$configurationId:buildSettings:INFOPLIST_FILE" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
		iphoneosDeploymentTarget=`$plistBuddy -c "Print :objects:$configurationId:buildSettings:IPHONEOS_DEPLOYMENT_TARGET" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
		onlyActiveArch=`$plistBuddy -c "Print :objects:$configurationId:buildSettings:ONLY_ACTIVE_ARCH" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`			
		productBundleIdentifier=`$plistBuddy -c "Print :objects:$configurationId:buildSettings:PRODUCT_BUNDLE_IDENTIFIER" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
		productName=`$plistBuddy -c "Print :objects:$configurationId:buildSettings:PRODUCT_NAME" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
		provisionProfileUuid=`$plistBuddy -c "Print :objects:$configurationId:buildSettings:PROVISIONING_PROFILE" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
		provisionProfileName=`$plistBuddy -c "Print :objects:$configurationId:buildSettings:PROVISIONING_PROFILE_SPECIFIER" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`

		# logit "codeSignEntitlements:$codeSignEntitlements"
		# logit "codeSignResourceRulePath:$codeSignResourceRulePath"

		logitVerbose "developmentTeam:$developmentTeam"
		logitVerbose "infoPlistFile:$infoPlistFile"
		logitVerbose "iphoneosDeploymentTarget:$iphoneosDeploymentTarget"
		logitVerbose "onlyActiveArch:$onlyActiveArch"
		logitVerbose "BundleId:$productBundleIdentifier"
		logitVerbose "productName:$productName"
		logitVerbose "provisionProfileUuid:$provisionProfileUuid"
		logitVerbose "provisionProfileName:$provisionProfileName"
		logitVerbose "codeSignIdentity:$codeSignIdentity"
		logitVerbose "codeSignIdentitySDK:$codeSignIdentitySDK"
	done
}




function getNewProfileUuid
{

	newProfileUuid=`$plistBuddy -c 'Print :UUID' /dev/stdin <<< $($security cms -D -i "$matchMobileProvisionFile" 2>1)`
	newProfileName=`$plistBuddy -c 'Print :Name' /dev/stdin <<< $($security cms -D -i "$matchMobileProvisionFile" 2>1)`
	newTeamId=`$plistBuddy -c 'Print :Entitlements:com.apple.developer.team-identifier' /dev/stdin <<< $($security cms -D -i "$matchMobileProvisionFile" 2>1)`
	if [[ "$newProfileUuid" == '' ]]; then
		echo "newProfileUuid=$newProfileUuid, 获取参数配置Profile的uuid失败!"
		exit 1;
	fi
	if [[ "$newProfileName" == '' ]]; then
		echo "newProfileName=$newProfileName, 获取参数配置Profile的name失败!"
		exit 1;
	fi
	logit "发现授权文件参数配置:${newProfileName}, uuid：$newProfileUuid, teamId:$newTeamId"
}


##检查授权文件类型
function getProfileType
{
	profile=$1
	# provisionedDevices=`$plistBuddy -c 'Print :ProvisionedDevices' /dev/stdin <<< $($security cms -D -i "$profile"  ) | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
	##判断是否存在key:ProvisionedDevices
	haveKey=`$security cms -D -i "$profile" 2>1 | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//' | grep ProvisionedDevices`
	if [[ $? -eq 0 ]]; then
		getTaskAllow=`$plistBuddy -c 'Print :Entitlements:get-task-allow' /dev/stdin <<< $($security cms -D -i "$profile" 2>1) `
		if [[ $getTaskAllow == true ]]; then
			profileType='debug'
		else
			profileType='adhoc'
		fi
	else

		haveKeyProvisionsAllDevices=`$security cms -D -i "$profile" 2>1  | grep ProvisionsAllDevices`
		if [[ "$haveKeyProvisionsAllDevices" != '' ]]; then
			provisionsAllDevices=`$plistBuddy -c 'Print :ProvisionsAllDevices' /dev/stdin <<< $($security cms -D -i "$profile" 2>1) `
			if [[ $provisionsAllDevices == true ]]; then
				profileType='enterprise'
			else
				profileType='appstore'
			fi
		else
			profileType='appstore'
		fi
	fi
}

function setBuildVersion
{

	for targetId in ${targets[@]}; do
		buildConfigurationListId=`$plistBuddy -c "Print :objects:$targetId:buildConfigurationList" $projectFile`
		buildConfigurationList=`$plistBuddy -c "Print :objects:$buildConfigurationListId:buildConfigurations" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
		buildConfigurations=(`echo $buildConfigurationList`)
		for configurationId in ${buildConfigurations[@]}; do
			infoPlistFile=`$plistBuddy -c "Print :objects:$configurationId:buildSettings:INFOPLIST_FILE" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
		done
	done

	infoPlistFilePath=$xcodeProject/../$infoPlistFile
	if [[ -f "$infoPlistFilePath" ]]; then
		$plistBuddy -c "Set :CFBundleVersion $gitVersionCount" $infoPlistFilePath
		logit "设置Buil Version:${gitVersionCount}"
	else
		echo "${infoPlistFilePath}文件不存在，无法修改"
		exit 1
	fi

	
}



##设置生产环境或者开发环境
function setEnvironment
{

	if [[ $haveConfigureEnvironment == true ]]; then
		bakExtension=".bak"
		bakFile=${environmentConfigureFile}${bakExtension}
		if [[ $productionEnvironment == true ]]; then
			if [[ "$environmentValue" != "NO" ]]; then
				sed -i "$bakExtension" "/kBMIsTestEnvironment/s/YES/NO/" "$environmentConfigureFile" && rm -rf $bakFile
				logit "设置配置环境kBMIsTestEnvironment:NO"
			fi
		else
			if [[ "$environmentValue" != "YES" ]]; then
				sed -i "$bakExtension" "/kBMIsTestEnvironment/s/NO/YES/" "$environmentConfigureFile" && rm -rf $bakFile
				logit "设置配置环境kBMIsTestEnvironment:YES"
			fi
		fi
	fi
}

##设置NO,只打标准arch
function setOnlyActiveArch
{
	for configurationId in ${buildConfigurations[@]}; do
		configurationName=`$plistBuddy -c "Print :objects:$configurationId:name" "$projectFile"`
		onlyActiveArch=`$plistBuddy -c "Print :objects:$configurationId:buildSettings:ONLY_ACTIVE_ARCH" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`			
		if [[ "$onlyActiveArch" != "NO" ]]; then
			$plistBuddy -c "Set :objects:$configurationId:buildSettings:ONLY_ACTIVE_ARCH NO" "$projectFile"
			logit "设置${configurationName}模式的ONLY_ACTIVE_ARCH:NO"
		fi
		
	done
}


##设置手动签名,即不勾选：Xcode -> General -> Signing -> Automatically manage signning

##获取签名方式
function getCodeSigningStyle
{
	for targetId in ${targets[@]}; do
		targetName=`$plistBuddy -c "Print :objects:$targetId:name" $projectFile`
		##没有勾选过Automatically manage signning时，则不存在ProvisioningStyle
		signingStyle=`$plistBuddy -c "Print :objects:$rootObject:attributes:TargetAttributes:$targetId:ProvisioningStyle " "$projectFile"`
		logit "获取到target:${targetName}签名方式:$signingStyle"
	done
}

function setManulSigning
{
	for targetId in ${targets[@]}; do
		targetName=`$plistBuddy -c "Print :objects:$targetId:name" $projectFile`
		if [[ "$signingStyle" != "Manual" ]]; then
			##如果需要设置成自动签名,将Manual改成Automatic
			$plistBuddy -c "Set :objects:$rootObject:attributes:TargetAttributes:$targetId:ProvisioningStyle Manual" "$projectFile"
			logit "设置${targetName}的签名方式为:Manual"
		fi

	done
	
}



function build
{
	packageDir=$xcodeProject/../build/package

	if [[ $debugConfiguration == true ]]; then
		configuration="Debug"
	else
		configuration="Release"
	fi

	for (( i = 0; i < ${#buildTargetNames[@]}; i++ )); do

		archivePath=${packageDir}/${buildTargetNames[$i]}.xcarchive
		exprotPath=${packageDir}/${buildTargetNames[$i]}.ipa


		if [[ -d $archivePath ]]; then
			rm -rf $archivePath
		fi

		if [[ -f $exprotPath ]]; then
			rm -rf $exprotPath
		fi

		if [[ $isExistXcWorkspace == true ]]; then
			$xcodebuild archive -workspace $xcworkspace -scheme ${buildTargetNames[$i]} -archivePath $archivePath -configuration $configuration build  
		else
			$xcodebuild archive						 	-scheme ${buildTargetNames[$i]} -archivePath $archivePath -configuration $configuration build 
		fi
		# $cmd
		if [[ $? -ne 0 ]]; then
			echo "构建失败！构建命令：$cmd" 
			rm -rf ${packageDir}/*
			exit 1
		fi

		##导出ipa
		$xcodebuild -exportArchive -exportFormat IPA -archivePath $archivePath -exportPath $exprotPath 
		if [[ $? -eq 0 ]]; then
			logit "打包成功,IPA生成路径：$exprotPath"
		else
			logit "$xcodebuild -exportArchive -exportFormat IPA -archivePath $archivePath -exportPath $exprotPath 执行失败"
			exit 1
		fi
		repairXcentFile
		checkIPA
		renameAndBackup

	done
}

##在打企业包的时候：会报 archived-expanded-entitlements.xcent  文件缺失!这是xcode的bug
##链接：http://stackoverflow.com/questions/28589653/mac-os-x-build-server-missing-archived-expanded-entitlements-xcent-file-in-ipa
function repairXcentFile
{

	appName=`basename $exprotPath .ipa`
	xcentFile=${archivePath}/Products/Applications/${appName}.app/archived-expanded-entitlements.xcent
	if [[ -f "$xcentFile" ]]; then
		logit  "拷贝xcent文件：$xcentFile "
		unzip -o $exprotPath -d /$packageDir >/dev/null 2>&1
		app=${packageDir}/Payload/${appName}.app
		cp -af $xcentFile $app
		##压缩,并覆盖原有的ipa
		cd ${packageDir}  ##必须cd到此目录 ，否则zip会包含绝对路径
		zip -qry  $exprotPath Payload && rm -rf Payload
		cd -
	else
		echo "$xcentFile 文件不存在，修复Xcent文件失败!"
		exit 1
	fi

}

##构建完成，检查App
function checkIPA
{

	##解压强制覆盖，并不输出日志

	if [[ -d /tmp/Payload ]]; then
		rm -rf /tmp/Payload
	fi
	unzip -o $exprotPath -d /tmp/ >/dev/null 2>&1
	appName=`basename $exprotPath .ipa`
	app=/tmp/Payload/${appName}.app
	codesign --no-strict -v "$app"
	if [[ $? -ne 0 ]]; then
		echo "签名检查：签名校验不通过！"
		exit 1;
	fi
	logit ""
	logit "==============签名检查：签名校验通过！==============="
	if [[ -d $app ]]; then
		infoPlistFile=${app}/Info.plist
		mobileProvisionFile=${app}/embedded.mobileprovision

		appShowingName=`$plistBuddy -c "Print :CFBundleName" $infoPlistFile`
		appBundleId=`$plistBuddy -c "print :CFBundleIdentifier" "$infoPlistFile"`
		appVersion=`$plistBuddy -c "Print :CFBundleShortVersionString" $infoPlistFile`
		appBuildVersion=`$plistBuddy -c "Print :CFBundleVersion" $infoPlistFile`
		appMobileProvisionName=`$plistBuddy -c 'Print :Name' /dev/stdin <<< $($security cms -D -i "$mobileProvisionFile" 2>1)`
		appMobileProvisionCreationDate=`$plistBuddy -c 'Print :CreationDate' /dev/stdin <<< $($security cms -D -i "$mobileProvisionFile" 2>1)`
		appMobileProvisionExpirationDate=`$plistBuddy -c 'Print :ExpirationDate' /dev/stdin <<< $($security cms -D -i "$mobileProvisionFile" 2>1)`
		appCodeSignIdenfifier=`$codesign --display -r- $app | cut -d "\"" -f 4`
		#支持最小的iOS版本
		supportMinimumOSVersion=`$plistBuddy -c "print :MinimumOSVersion" "$infoPlistFile"`
		#支持的arch
		supportArchitectures=`$lipo -info $app/$appName | cut -d ":" -f 3`

		logit "名字:$appShowingName"
		getEnvirionment
		logit "配置环境kBMIsTestEnvironment:$currentEnvironmentValue"
		logit "bundle identify:$appBundleId"
		logit "版本:$appVersion"
		logit "build:$appBuildVersion"
		logit "支持最低iOS版本:$supportMinimumOSVersion"
		logit "支持的arch:$supportArchitectures"
		logit "签名:$appCodeSignIdenfifier"
		logit "授权文件:${appMobileProvisionName}.mobileprovision"
		logit "授权文件创建时间:$appMobileProvisionCreationDate"
		logit "授权文件过期时间:$appMobileProvisionExpirationDate"
		getProfileType $mobileProvisionFile
		logit "授权文件类型:$profileType"	

	else
		echo "解压失败！无法找到$app"
		exit 1
	fi
}

function renameAndBackup
{
	backupDir=~/Desktop/PackageLog
	backupHistoryDir=~/Desktop/PackageLog/history
	if [[ ! -d backupHistoryDir ]]; then
		mkdir -p $backupHistoryDir
	fi
	if [[ "$currentEnvironmentValue" == 'YES' ]]; then
		environmentName='开发环境'
	else
		environmentName='生产环境'
	fi

	if [[ "$profileType" == 'appstore' ]]; then
		profileTypeName='商店分发'
	elif [[ "$profileType" == 'enterprise' ]]; then
		profileTypeName='企业分发'
	else
		profileTypeName='内部测试'
	fi

	date=`date +"%Y%m%d_%H%M%S"`
	name=${appShowingName}_${date}_${environmentName}_${profileTypeName}_${appVersion}\($appBuildVersion\)
	ipaName=${name}.ipa
	textLogName=${name}.txt
	logit "ipa重命名并备份到：$backupDir/$ipaName"
	
	mv -f $backupDir/*.ipa  $backupHistoryDir
	mv -f $backupDir/*.txt  $backupHistoryDir
	cp -af $exprotPath $backupDir/$ipaName
	cp -af $tmpLogFile $backupDir/$textLogName
	
}

function configureSigningByRuby
{
	logit "========================配置Signing========================"
	rbDir="$( cd "$( dirname "$0"  )" && pwd  )"


	ruby ${rbDir}/xcocdeModify.rb "$xcodeProject" $newProfileUuid $newProfileName "$matchCodeSignIdentity"  $newTeamId

	if [[ $? -ne 0 ]]; then
		echo "xcocdeModify.rb 修改配置失败！！"
		exit 1
	fi
	


	logit "========================配置完成========================"
}


function loginKeychainAccess
{
	
	#允许访问证书
	$security unlock-keychain -p "asdfghjkl" "$HOME/Library/Keychains/login.keychain" 2>1
	if [[ $? -ne 0 ]]; then
		echo "security unlock-keychain 失败!请检查脚本配置密码是否正确"
		exit 1
	fi
	$security unlock-keychain -p "asdfghjkl" "$HOME/Library/Keychains/login.keychain-db" 2>1
		if [[ $? -ne 0 ]]; then
		echo "security unlock-keychain 失败!请检查脚本配置密码是否正确"
		exit 1
	fi
}



function checkChannel
{
	OPTARG=$1
	if [[ "$OPTARG" != "debug" ]] && [[ "$OPTARG" != "appstore" ]] && [[ "$OPTARG" != "enterprise" ]]; then
		echo "-c 参数不能配置值：$OPTARG"
		usage
		exit 1
	fi
	channel=${OPTARG}

}



while getopts p:c:xvhgtl option; do
  case "${option}" in
  	g) getGitVersionCount;exit;;
    p) xcodeProject=${OPTARG};;
	c) checkChannel ${OPTARG};;
	t) productionEnvironment=false;;
	l) showUsableCodeSign;exit;;
    x) set -x;;
	d) debugConfiguration=true;;
    v) verbose=true;;
    h | help) usage; exit;;
	* ) usage;exit;;
  esac
done





checkForProjectFile
checkIsExistWorkplace
checkEnvironmentConfigureFile

getEnvirionment
getAllTargets
getAPPBundleId
autoMatchProvisionFile
autoMatchCodeSignIdentity
getGitVersionCount
getCodeSigningStyle
setEnvironment
setBuildVersion
getNewProfileUuid
configureSigningByRuby
showBuildSetting




build



#所有的Set方法，目前都被屏蔽掉。因为当使用PlistBuddy修改工程配置时，会导致工程对中文解析出错！！！


