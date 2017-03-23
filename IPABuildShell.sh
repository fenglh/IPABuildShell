#!/bin/bash
#--------------------------------------------
# 功能：
#		1.显示Build Settings 签名配置
#		2.获取git版本数量，并自动更改build号为版本数量号
#		3.日志文本log.txt输出
#		4.支持可以配置的签名、授权文件等
#		5.支持workplace、多个scheme
#		6.校验构建后的ipa的bundle Id、签名方式、支持最低iOS版本、arm体系等等
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

#--------------------------------------------
	# 没有任何修饰符参数 : 原生参数
	# <>  : 占位参数
	# []  : 可选组合
	# ()  : 必选组合
	# |   : 互斥参数
	# ... : 可重复指定前一个参数
	# --  : 标记后续参数类型
#--------------------------------------------


tmpLogFile=/tmp/`date +"%Y%m%d%H%M%S"`.txt
plistBuddy="/usr/libexec/PlistBuddy"
xcodebuild="/usr/bin/xcodebuild"
security="/usr/bin/security"
codesign="/usr/bin/codesign"
verbose=false
productionEnvironment=true
debugConfiguration=false
declare -a targetNames
environmentConfigureFileName="BMNetworkingConfiguration.h"



function usage
{
	echo "  -p <Xcode Project File>: 指定Xcode project."
	echo "  -f <Profile>: 指定授权文件."
	echo "  -s <codeSign identify>: 指定签名，使用-l 参数列举可用签名."
	echo "  -g: 获取git版本数量，并自动更改build号为版本数量号."
	echo "  -l: 列举可用的codeSign identify."
	echo "  -x: 脚本执行调试模式."
	echo "  -d: 设置debug模式，默认release模式."
	echo "  -t: 设置为测试(开发)环境，默认为生产环境."
	echo "  -s: 显示有效的签名."
	echo "  -h: 帮助."
  	echo "  -v: 输出详细信息."
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
	echo "当前版本数量:$gitVersionCount"
}


##获取scheme
function getSchemes
{
	##获取scheme，替换#号，是为了方便赋值给数组。scheme名字带有空格的时候例如：Copy of BlueMoonSFA，会被误分割成数组的元素。
	schemeList=(`$xcodebuild -project $xcodeProject -list | awk '/\Schemes/{s=$0~/Schemes/?1:0}s' | grep -v "Schemes:" | tr -s '\n'| tr -s ' ' '#'`)
	for (( i = 0; i < ${#schemeList[@]}; i++ )); do
		scheme=`echo ${schemeList[$i]} | tr -d '#'`
		schemes[$i]=$scheme
	done

	logit "获取到schemes，数量：${#schemes[@]}"
	for (( i = 0; i < ${#schemes[@]}; i++ )); do
		logit "${schemes[$i]}"
	done
}



function getAllTargets
{
	rootObject=`$plistBuddy -c "Print :rootObject" $projectFile`
	targetList=`$plistBuddy -c "Print :objects:${rootObject}:targets" $projectFile | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'` 
	targets=(`echo $targetList`);#括号用于初始化数组,例如arr=(1,2,3)
	##这里，只取第一个target,因为默认情况下xcode project 会有自动生成Tests 以及 UITests 两个target
	targets=(${targets[0]})
	logit "发现targets(id):$targets"
}



##获取BuildSetting 配置
function getBuildSettingsConfigure
{
	logit "======================获取配置Signing后的配置信息======================"
	for targetId in ${targets[@]}; do
		targetName=`$plistBuddy -c "Print :objects:$targetId:name" $projectFile`
		buildTargetNames=(${buildTargetNames[*]} $targetName)
		logit "target名字：$targetName"
		buildConfigurationListId=`$plistBuddy -c "Print :objects:$targetId:buildConfigurationList" $projectFile`
		logit "配置列表Id：$buildConfigurationListId"
		buildConfigurationList=`$plistBuddy -c "Print :objects:$buildConfigurationListId:buildConfigurations" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
		buildConfigurations=(`echo $buildConfigurationList`)
		logit "发现配置:$buildConfigurations"

		for configurationId in ${buildConfigurations[@]}; do

			configurationName=`$plistBuddy -c "Print :objects:$configurationId:name" "$projectFile"`
			logit "配置类型: $configurationName"
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
			logit "codeSignIdentity:$codeSignIdentity"
			logit "codeSignIdentitySDK:$codeSignIdentitySDK"
			logit "developmentTeam:$developmentTeam"
			logit "infoPlistFile:$infoPlistFile"
			logit "iphoneosDeploymentTarget:$iphoneosDeploymentTarget"
			logit "onlyActiveArch:$onlyActiveArch"
			logit "productBundleIdentifier:$productBundleIdentifier"
			logit "productName:$productName"
			logit "provisionProfileUuid:$provisionProfileUuid"
			logit "provisionProfileName:$provisionProfileName"

			logit "=============================="
		done
	done
}


function getNewProfileUuid
{

	newProfileUuid=`$plistBuddy -c 'Print :UUID' /dev/stdin <<< $($security cms -D -i "$newProfile" )`
	newProfileName=`$plistBuddy -c 'Print :Name' /dev/stdin <<< $($security cms -D -i "$newProfile" )`
	newTeamId=`$plistBuddy -c 'Print :Entitlements:com.apple.developer.team-identifier' /dev/stdin <<< $($security cms -D -i "$newProfile" )`
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
	haveKey=`security cms -D -i "$profile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//' | grep ProvisionedDevices`
	if [[ $? -eq 0 ]]; then
		getTaskAllow=`$plistBuddy -c 'Print :Entitlements:get-task-allow' /dev/stdin <<< $($security cms -D -i "$profile" ) `
		if [[ $getTaskAllow == true ]]; then
			profileType='debug'
		else
			profileType='ad-hoc'
		fi
	else
		provisionsAllDevices=`$plistBuddy -c 'Print :ProvisionsAllDevices' /dev/stdin <<< $($security cms -D -i "$profile" ) `
		if [[ $provisionsAllDevices == true ]]; then
			profileType='enterprise'
		else
			profileType='appstore'
		fi
	fi

	logit "授权文件类型:$profileType"
	if [[ "$haveKey" != '' ]]; then
		logit "$provisionedDevices"
	fi
	
}


##设置build号
function setBuildVersion
{
	$plistBuddy -c "Set :CFBundleVersion $gitVersionCount" $infoPlistFile
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
	getEnvirionment

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


##这里忽略旧版本xcode没有
function setProfile
{
	for configurationId in ${buildConfigurations[@]}; do
		configurationName=`$plistBuddy -c "Print :objects:$configurationId:name" "$projectFile"`
		if [[ "$provisionProfileName" != "$newProfileName" ]]; then
			$plistBuddy -c "Set :objects:$configurationId:buildSettings:PROVISIONING_PROFILE_SPECIFIER $newProfileName" "$projectFile"
			logit "设置授权文件SPECIFIER${configurationName} PROVISIONING_PROFILE_SPECIFIER：$provisionProfileName --> $newProfileName"
		fi

		if [[ "$provisionProfileUuid" != "$newProfileUuid" ]]; then
			$plistBuddy -c "Set :objects:$configurationId:buildSettings:PROVISIONING_PROFILE $newProfileUuid" "$projectFile"
			logit "设置授权文件${configurationName} PROVISIONING_PROFILE：$provisionProfileUuid --> $newProfileUuid"
		fi

	done
}

##设置签名
function setCodeSign
{
	for configurationId in ${buildConfigurations[@]}; do
		configurationName=`$plistBuddy -c "Print :objects:$configurationId:name" "$projectFile"`
		##设置CODE_SIGN_IDENTITY
		if [[ "$codeSignIdentity" != "$newCodeSign" ]]; then
			$plistBuddy -c "Set :objects:$configurationId:buildSettings:CODE_SIGN_IDENTITY $newCodeSign" "$projectFile"
			if [[ $? -eq 0 ]]; then
				logit "设置签名${configurationName} CODE_SIGN_IDENTITY: $codeSignIdentity --> $newCodeSign"
			else
				echo "设置签名${configurationName} CODE_SIGN_IDENTITY 失败!"
				exit 1
			fi

			
		fi
		##设置CODE_SIGN_IDENTITY[sdk=iphoneos*]
		if [[ "$codeSignIdentitySDK" != "$newCodeSign" ]]; then
			$plistBuddy -c "Set :objects:$configurationId:buildSettings:CODE_SIGN_IDENTITY[sdk=iphoneos*] $newCodeSign" "$projectFile"
			if [[ $? -eq 0 ]]; then
				logit "更改签名配置${configurationName} CODE_SIGN_IDENTITY[sdk=iphoneos*]: $codeSignIdentitySDK --> $newCodeSign"
			else
				echo "更改签名配置${configurationName} CODE_SIGN_IDENTITY[sdk=iphoneos*] 失败!"
				exit 1
			fi
			
		fi
		##设置teamId
		if [[ "$developmentTeam" != "$newTeamId" ]]; then
			$plistBuddy -c "Set :objects:$configurationId:buildSettings:DEVELOPMENT_TEAM $newTeamId" "$projectFile"
			if [[ $? -eq 0 ]]; then
				logit "更改签名配置${configurationName} DEVELOPMENT_TEAM: $developmentTeam --> $newTeamId"
			else
				echo "更改签名配置${configurationName} DEVELOPMENT_TEAM 失败!"
				exit 1
			fi
			
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
			$xcodebuild archive -workspace $xcworkspace -scheme ${buildTargetNames[$i]} -archivePath $archivePath -configuration $configuration build  ONLY_ACTIVE_ARCH=NO
		else
			$xcodebuild archive						 	-scheme ${buildTargetNames[$i]} -archivePath $archivePath -configuration $configuration build  ONLY_ACTIVE_ARCH=NO
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
		checkIPA
		renameAndBackup

	done
}



##构建完成，检查App
function checkIPA
{

	##解压强制覆盖，并不输出日志
	unzip -o $exprotPath -d /tmp/ >/dev/null 2>&1
	appName=`basename $exprotPath .ipa`

	app=/tmp/Payload/${appName}.app

	logit "============================="
	if [[ -d $app ]]; then
		infoPlistFile=${app}/Info.plist
		mobileProvisionFile=${app}/embedded.mobileprovision

		appName=`$plistBuddy -c "Print :CFBundleName" $infoPlistFile`
		appBundleId=`$plistBuddy -c "print :CFBundleIdentifier" "$infoPlistFile"`
		appVersion=`$plistBuddy -c "Print :CFBundleShortVersionString" $infoPlistFile`
		appBuildVersion=`$plistBuddy -c "Print :CFBundleVersion" $infoPlistFile`
		appMobileProvisionName=`$plistBuddy -c 'Print :Name' /dev/stdin <<< $($security cms -D -i "$mobileProvisionFile" )`
		appMobileProvisionCreationDate=`$plistBuddy -c 'Print :CreationDate' /dev/stdin <<< $($security cms -D -i "$mobileProvisionFile" )`
		appMobileProvisionExpirationDate=`$plistBuddy -c 'Print :ExpirationDate' /dev/stdin <<< $($security cms -D -i "$mobileProvisionFile" )`
		appCodeSignIdenfifier=`$codesign --display -r- $app | cut -d "\"" -f 4`


		logit "名字:$appName"
		logit "配置环境kBMIsTestEnvironment:$currentEnvironmentValue"
		logit "bundle identify:$appBundleId"
		logit "版本:$appVersion"
		logit "build:$appBuildVersion"
		logit "签名:$appCodeSignIdenfifier"
		logit "授权文件:${appMobileProvisionName}.mobileprovision"
		logit "授权文件创建时间:$appMobileProvisionCreationDate"
		logit "授权文件过期时间:$appMobileProvisionExpirationDate"
		getProfileType $mobileProvisionFile
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
	name=${appName}_${date}_${environmentName}_${profileTypeName}_${appVersion}\($appBuildVersion\)
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
	ruby ${rbDir}/xcocdeModify.rb "$xcodeProject" $newProfileUuid "$newProfileName" "$newCodeSign"  "$newTeamId"
	if [[ $? -ne 0 ]]; then
		echo "xcocdeModify.rb 修改配置失败！！"
		exit 1
	fi
	logit "========================配置完成========================"
}


while getopts p:f:s:xvhgtl option; do
  case "${option}" in
  	g) getGitVersionCount;exit;;
    p) xcodeProject=${OPTARG};;
	f) newProfile=${OPTARG};;
	s) newCodeSign=${OPTARG};;
	t) productionEnvironment=false;;
	l) showUsableCodeSign;exit;;
    x) set -x;;
	d) debugConfiguration=true;;
    v) verbose=true;;
    h | help) usage; exit;;
	* ) usage;exit;;
  esac
done


#允许访问证书
security unlock-keychain -p "123456" "$HOME/Library/Keychains/login.keychain"


checkForProjectFile
checkIsExistWorkplace
checkEnvironmentConfigureFile
getEnvirionment
getAllTargets
getCodeSigningStyle
setEnvironment

if [[ -f $newProfile ]]; then
	getNewProfileUuid
fi

configureSigningByRuby
getBuildSettingsConfigure


build



##所有的Set方法，目前都被屏蔽掉。因为当使用PlistBuddy修改工程配置时，会导致工程对中文解析出错！！！


