#!/bin/bash

# ----------------------------------------------------------------------
# name:         IPABuildShell.sh
# version:      2.0.6
# createTime:   2018-04-20
# description:  iOS 自动打包
# author:       冯立海
# email:        335418265@qq.com
# github:       https://github.com/aa335418265/IPABuildShell
# ----------------------------------------------------------------------


backupDir=~/Desktop/PackageLog
backupHistoryDir=~/Desktop/PackageLog/history/
tmpLogFile=/tmp/`date +"%Y%m%d%H%M%S"`.txt
plistBuddy="/usr/libexec/PlistBuddy"
xcodebuild="/usr/bin/xcodebuild"
security="/usr/bin/security"
codesign="/usr/bin/codesign"
pod=`which pod`

ruby="/usr/bin/ruby"
lipo="/usr/bin/lipo"
currentShellDir="$( cd "$( dirname "$0"  )" && pwd  )"
##默认分发渠道是内部测试
channel='development'
verbose=true
productionEnvironment=true
debugConfiguration=false
arch='arm64'



##大于等于
function versionCompareGE() { test "$(echo "$@" | tr " " "\n" | sort -rn | head -n 1)" == "$1"; }

##初始化配置：bundle identifier 和 code signing identity

function errorExit(){
    endDateSeconds=`date +%s`
    logit "构建时长：$((${endDateSeconds}-${startDateSeconds})) 秒"
    echo -e "\033[31m \n++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++\033[0m"
    echo -e "\033[31m \t打包失败! 原因：$@ \033[0m"
    echo -e "\033[31m \n++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++\033[0m"
    exit 1
}

function logit() {
    if [ $verbose == true ]; then
        echo -e "\033[32m [IPABuildShell] \033[0m $@"
    fi
    echo "	>> $@" >> $tmpLogFile
}

function logitVerbose
{
    echo -e "\033[36m $@ \033[0m"

    echo "	>> $@" >> $tmpLogFile
}


function profileTypeToName
{
    profileType=$1
    if [[ "$profileType" == 'app-store' ]]; then
        profileTypeName='商店分发'
    elif [[ "$profileType" == 'enterprise' ]]; then
        profileTypeName='企业分发'
    else
        profileTypeName='内部测试'
    fi

}


function initConfiguration() {
	configPlist=$currentShellDir/config.plist
	if [ ! -f "$configPlist" ];then
			errorExit "找不到配置文件：$configPlist"
	fi

	environmentConfigFileName=`$plistBuddy -c 'Print :InterfaceEnvironmentConfig:EnvironmentConfigFileName' $configPlist`
	environmentConfigVariableName=`$plistBuddy -c 'Print :InterfaceEnvironmentConfig:EnvironmentConfigVariableName' $configPlist`
	loginPwd=`$plistBuddy -c 'Print :LoginPwd' $configPlist`
	devCodeSignIdentityForPersion=`$plistBuddy -c 'Print :Individual:devCodeSignIdentity' $configPlist`
	disCodeSignIdentityForPersion=`$plistBuddy -c 'Print :Individual:disCodeSignIdentity' $configPlist`
	devCodeSignIdentityForEnterprise=`$plistBuddy -c 'Print :Enterprise:devCodeSignIdentity' $configPlist`
	disCodeSignIdentityForEnterprise=`$plistBuddy -c 'Print :Enterprise:disCodeSignIdentity' $configPlist`
	bundleIdsForPersion=`$plistBuddy -c 'Print :Individual:bundleIdentifiers' $configPlist`
	bundleIdsForEnterprise=`$plistBuddy -c 'Print :Enterprise:bundleIdentifiers' $configPlist`
}
function clean
{
	if [[ -d "$backupDir" ]]; then
		for file in `ls $backupDir` ; do
		logit "【备份】备份上一次打包结果到History文件夹：$file"
		if [[ "$file" != 'History' ]]; then
			if [[ ! -f "$backupDir/$file" ]]; then
				continue;
			fi
			mv -f $backupDir/$file $backupHistoryDir
			if [[ $? -ne 0 ]]; then
				errorExit "备份历史文件失败!"
			fi
		fi
	done
	fi

}

##登录keychain授权
function loginKeychainAccess
{

	#允许访问证书
	$security unlock-keychain -p $loginPwd "$HOME/Library/Keychains/login.keychain" 2>/tmp/log.txt
	if [[ $? -ne 0 ]]; then
		errorExit "security unlock-keychain 失败!请检查脚本配置密码是否正确"

	fi
	$security unlock-keychain -p $loginPwd "$HOME/Library/Keychains/login.keychain-db" 2>/tmp/log.txt
		if [[ $? -ne 0 ]]; then
		errorExit "security unlock-keychain 失败!请检查脚本配置密码是否正确"

	fi
}

##xcode 8.3之后使用-exportFormat导出IPA会报错 xcodebuild: error: invalid option '-exportFormat',改成使用-exportOptionsPlist
function generateOptionsPlist
{
	teamId=$1
	method=$2
	appBundleId=$3
	profileName=$4
	plistfileContent="
	<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n
	<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n
	<plist version=\"1.0\">\n
	<dict>\n
	<key>teamID</key>\n
	<string>$teamId</string>\n
	<key>method</key>\n
	<string>$method</string>\n
	<key>provisioningProfiles</key>\n
    <dict>\n
        <key>$appBundleId</key>\n
        <string>$profileName</string>\n
    </dict>\n
	<key>compileBitcode</key>\n
	<false/>\n
	</dict>\n
	</plist>\n
	"
	echo -e $plistfileContent > /tmp/optionsplist.plist
}


###检查输入的分发渠道
function checkChannel
{
	OPTARG=$1
	if [[ "$OPTARG" != "development" ]] && [[ "$OPTARG" != "app-store" ]] && [[ "$OPTARG" != "enterprise" ]]; then
		logit "-c 参数不能配置值：$OPTARG"
		usage
		exit 1
	fi
	channel=${OPTARG}

}



##设置命令快捷方式
# function setAliasShortCut
# {
# 	bashProfile=$HOME/.bash_profile
# 	if [[ ! -f $bashProfile ]]; then
# 		touch $bashProfile
# 	fi
# 	shellFilePath="$currentShellDir/`basename "$0"`"
#
# 	aliasString="alias gn=\"$shellFilePath -g\""
# 	grep "$aliasString" $bashProfile
# 	if [[ $? -ne 0 ]]; then
# 		echo $aliasString >> $bashProfile
# 	fi
# }

function usage
{
	# setAliasShortCut
	echo ""
	echo "  -p <Xcode Project File>: 指定Xcode project. 否则，脚本会在当前执行目录中查找Xcode Project 文件"
	echo "  -g: 获取当前项目git的版本数量"
	echo "  -l: 列举可用的codeSign identity."
	echo "  -x: 脚本执行调试模式."
  	echo "  -b: 设置Bundle Id."
	echo "  -d: 设置debug模式，默认release模式."
	echo "  -t: 设置为测试(开发)环境，默认为生产环境."
	echo "  -c <development|app-store|enterprise>: development 内部分发，app-store商店分发，enterprise企业分发"
	echo "  -r <体系结构> 例如：-r 'armv7'或者 -r 'arm64' 或者 -r 'armv7 arm64' 等"
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
		logit "${usableCodeSignList[$i]}"
	done
}

function getXcodeVersion {
	xcodeVersion=`$xcodebuild -version | head -1 | cut -d " " -f 2`
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
		errorExit "Xcode project 应该带有.xcodeproj文件扩展，.${projectExtension}不是一个Xcode project扩展！"
	else
		projectFile="$xcodeProject/project.pbxproj"
		if [[ ! -f "$projectFile" ]]; then
			errorExit "项目文件:\"$projectFile\" 不存在"
		fi
		logit "【检查】发现pbxproj:\"$projectFile\""
	fi
}

##备份项目配置文件
# function backupProjectFile {
#   if [[ ! -f "$projectFile" ]]; then
#     errorExit "备份项目文件失败:\"$projectFile\" 不存在"
#   fi

#   ## 强制覆盖
#   bak="${projectFile}.bak"
#   cp -f "$projectFile" "$bak"
#   if [[ $? -eq 0 ]]; then
#     ## 对备份之前的项目文件做MD5
#     # projectFileMD5 = `md5 "$bak"`
#     logit "【备份】备份项目文件为：${bak}"
#   fi
# }

##恢复项目文件
# function recoverProjectFile {
#   bak="${projectFile}.bak"
#   # bakFileMD5 = `md5 "$bak"`
#   if [[  -f "$bak" ]] ; then
#       mv "$bak" "$projectFile"
#       if [[ $? -eq 0 ]]; then
#         logit "【还原】还原项目文件"
#       fi
#   fi
# }


##检查是否存在workplace,当前只能通过遍历的方法来查找
function checkIsExistWorkplace
{
	xcworkspace=`find "$xcodeProject/.." -maxdepth 1  -type d -name "*.xcworkspace"`
	if [[ -d "$xcworkspace" ]]; then
		isExistXcWorkspace=true
		logit "【检查】发现xcworkspace:$xcworkspace"
	else
		isExistXcWorkspace=false;
	fi
}

function  podInstall
{
	podfile=`find "$xcodeProject/.." -maxdepth 1  -type f -name "Podfile"`
	if [[ -f "$podfile" ]]; then
		logit "pod install"
		$pod install
	fi
}

##检查配置文件
function checkEnvironmentConfigureFile
{
	environmentConfigureFile=`find "$xcodeProject/.." -maxdepth 5 -path "./.Trash" -prune -o -type f -name "$environmentConfigFileName" -print| head -n 1`
	if [[ ! -f "$environmentConfigureFile" ]]; then
		haveConfigureEnvironment=false;
		#logit "接口环境配置文件${environmentConfigFileName}不存在,忽略接口生产/开发环境配置"
	else
		haveConfigureEnvironment=true;
		logit "【检查】发现接口环境配置文件:${environmentConfigureFile}"
	fi
}

function getEnvirionment
{
	if [[ $haveConfigureEnvironment == true ]]; then
		environmentValue=$(grep "$environmentConfigVariableName" "$environmentConfigureFile" | grep -v '^//' | cut -d ";" -f 1 | cut -d "=" -f 2 | sed 's/^[ \t]*//g' | sed 's/[ \t]*$//g')
		currentEnvironmentValue=$environmentValue
		logit "【接口环境配置】当前接口配置环境kBMIsTestEnvironment:$currentEnvironmentValue"
	fi


}


##获取git版本数量
function getGitVersionCount
{
	gitVersionCount=`git -C "$xcodeProject" rev-list HEAD | wc -l | grep -o "[^ ]\+\( \+[^ ]\+\)*"`
	logit "【版本数量】$gitVersionCount"
}

##根据授权文件，自动匹配授权文件和签名身份



##获取授权文件过期天数
function getProvisionfileExpirationDays
{
    mobileProvisionFile=$1

    ##切换到英文环境，不然无法转换成时间戳
    export LANG="en_US.UTF-8"
    ##获取授权文件的过期时间
    profileExpirationDate=`$plistBuddy -c 'Print :ExpirationDate' /dev/stdin <<< $($security cms -D -i "$mobileProvisionFile" 2>/tmp/log.txt)`
    profileExpirationTimestamp=`date -j -f "%a %b %d  %T %Z %Y" "$profileExpirationDate" "+%s"`
    nowTimestamp=`date +%s`
    r=$[profileExpirationTimestamp-nowTimestamp]
    expirationDays=$[r/60/60/24]
}

function autoMatchProvisionFile
{
	##授权文件默认放置在和脚本同一个目录下的MobileProvisionFile 文件夹中
	mobileProvisionFileDir="$( cd "$( dirname "$0"  )" && pwd  )/MobileProvisionFile"
	if [[ ! -d "$mobileProvisionFileDir" ]]; then
		errorExit "授权文件目录${mobileProvisionFileDir}不存在！"
	fi

	matchMobileProvisionFile=''
	for file in ${mobileProvisionFileDir}/*.mobileprovision; do
		applicationIdentifier=`$plistBuddy -c 'Print :Entitlements:application-identifier' /dev/stdin <<< $($security cms -D -i "$file" 2>/tmp/log.txt )`
		applicationIdentifier=${applicationIdentifier#*.}
		if [[ "$appBundleId" == "$applicationIdentifier" ]]; then
			getProfileType $file
			if [[ "$profileType" == "$channel" ]]; then
				matchMobileProvisionFile=$file
				logit "【授权文件】匹配到授权文件：${applicationIdentifier}，路径：$file"
                profileTypeToName "${channel}"
                logit "【授权文件】分发渠道：$profileTypeName"
				break
			fi
		fi
	done

	if [[ $matchMobileProvisionFile == '' ]]; then
        profileTypeToName "${channel}"
		errorExit "无法匹配${appBundleId} 分发渠道为【${profileTypeName}】的授权文件"
	fi

    ##企业分发，那么检查授权文件有效期
    if [[ "$channel" == 'enterprise' ]];then
        getProvisionfileExpirationDays "$matchMobileProvisionFile"
        logit "【授权文件】授权文件有效时长：${expirationDays} 天";
        if [[ $expirationDays -lt 0 ]];then
            profileExpirationDate=`$plistBuddy -c 'Print :ExpirationDate' /dev/stdin <<< $($security cms -D -i "$matchMobileProvisionFile" 2>/tmp/log.txt)`
            errorExit "授权文件已经过期, 请联系开发人员更换授权文件! 有效日期:${profileExpirationDate}, 过期天数：${expirationDays#-} 天"
        elif [[ $expirationDays -le 90 ]];then
            errorExit "授权文件即将过期, 请联系开发人员更换授权文件! 有效日期:${profileExpirationDate} ,剩余天数：${expirationDays} 天"
        fi
    fi


	##获取授权文件uuid、name、teamId
	profileUuid=`$plistBuddy -c 'Print :UUID' /dev/stdin <<< $($security cms -D -i "$matchMobileProvisionFile" 2>/tmp/log.txt)`
	profileName=`$plistBuddy -c 'Print :Name' /dev/stdin <<< $($security cms -D -i "$matchMobileProvisionFile" 2>/tmp/log.txt)`
	profileTeamId=`$plistBuddy -c 'Print :Entitlements:com.apple.developer.team-identifier' /dev/stdin <<< $($security cms -D -i "$matchMobileProvisionFile" 2>/tmp/log.txt)`
	if [[ "$profileUuid" == '' ]]; then
		errorExit "profileUuid=$profileUuid, 获取参数配置Profile的uuid失败!"
	fi
	if [[ "$profileName" == '' ]]; then
		errorExit "profileName=$profileName, 获取参数配置Profile的name失败!"
	fi
	logit "【授权文件】名字：${profileName}"
	logit "【授权文件】UUID：$profileUuid"
	logit "【授权文件】TeamId：$profileTeamId"

}

function autoMatchCodeSignIdentity
{

	matchCodeSignIdentity=''


	if [[ "$channel" == 'development' ]]; then
		##在个人账号中
		if [[ "${bundleIdsForPersion[@]}" =~ "$appBundleId" ]]; then
			matchCodeSignIdentity=$devCodeSignIdentityForPersion
		elif [[ "${bundleIdsForEnterprise[@]}" =~ "$appBundleId" ]]; then
			matchCodeSignIdentity=$devCodeSignIdentityForEnterprise
		else
			errorExit "${appBundleId}无法匹配分发方式为:${channel} 的签名"
		fi
	elif [[ "$channel" == 'app-store' ]]; then
		if [[ "${bundleIdsForPersion[@]}" =~ "$appBundleId" ]]; then
			matchCodeSignIdentity=$disCodeSignIdentityForPersion
		else
			errorExit "${appBundleId}无法匹配分发方式为:${channel} 的签名"
		fi
	elif [[ "$channel" == 'enterprise' ]]; then
		if [[ "${bundleIdsForEnterprise[@]}" =~ "$appBundleId" ]]; then
			matchCodeSignIdentity=$disCodeSignIdentityForEnterprise
		else
			errorExit "${appBundleId}无法匹配分发方式为:${channel} 的签名"
		fi
	fi

	logit "【签名】匹配到签名:$matchCodeSignIdentity"

}

##这里只取第一个target
function getFirstTargets
{
	rootObject=`$plistBuddy -c "Print :rootObject" "$projectFile"`
	targetList=`$plistBuddy -c "Print :objects:${rootObject}:targets" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
	targets=(`echo $targetList`);#括号用于初始化数组,例如arr=(1,2,3)
	##这里，只取第一个target,因为默认情况下xcode project 会有自动生成Tests 以及 UITests 两个target
	targetId=${targets[0]}
	targetName=`$plistBuddy -c "Print :objects:$targetId:name" "$projectFile"`
	logit "【APP】名字：$targetName"


}

#### 即release和debug 模式对应的id
function getConfigurationsIds() {
  buildConfigurationListId=`$plistBuddy -c "Print :objects:$targetId:buildConfigurationList" "$projectFile"`
  buildConfigurationList=`$plistBuddy -c "Print :objects:$buildConfigurationListId:buildConfigurations" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
  ##数组中存放的分别是release和debug对应的id
  buildConfigurations=(`echo $buildConfigurationList`)
}


## 根据debugConfiguration变量指定构建时的配置模式是Debug还是Release来获取对应的configurationId
## 在xcode项目的project.pbxproj配置文件中，Release模式和Debug模式下的配置是分别保存在不同地方的，所以这里先获取当前需要构建的模式
function getBuildConfigurationId() {

	if [[ $debugConfiguration == true ]]; then
		name="Debug"
	else
		name="Release"
	fi

	for id in ${buildConfigurations[@]}; do
		configurationName=`$plistBuddy -c "Print :objects:$id:name" "$projectFile"`
		if [[ "$configurationName" == "$name" ]]; then
			configurationId=$id
		fi
	done

	logit "【构建模式】构建模式:$name"

	
}

function getAPPBundleId
{
	##根据configurationId来获取Bundle Id
	appBundleId=`$plistBuddy -c "Print :objects:$configurationId:buildSettings:PRODUCT_BUNDLE_IDENTIFIER" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
	if [[ "$appBundleId" == '' ]]; then
		errorExit "获取APP Bundle Id 是失败!!!"
	fi
	logit "【APP】Bundle Id：$appBundleId"

}



##获取根据configurationId下的BuildSetting 配置
function showBuildSetting
{
	logitVerbose "======================查看当前Build Setting 配置======================"
	configurationName=`$plistBuddy -c "Print :objects:$configurationId:name" "$projectFile"`
	logit "【构建模式】(Debug/release): $configurationName"
	# CODE_SIGN_ENTITLEMENTS 和 CODE_SIGN_RESOURCE_RULES_PATH 不一定存在，这里不做判断
	# codeSignEntitlements=`$plistBuddy -c "Print :objects:$configurationId:buildSettings:CODE_SIGN_ENTITLEMENTS" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
	# codeSignResourceRulePath=`$plistBuddy -c "Print :objects:$configurationId:buildSettings:CODE_SIGN_RESOURCE_RULES_PATH" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
	codeSignIdentity=`$plistBuddy -c "Print :objects:$configurationId:buildSettings:CODE_SIGN_IDENTITY" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
	codeSignIdentitySDK=`$plistBuddy -c "Print :objects:$configurationId:buildSettings:CODE_SIGN_IDENTITY[sdk=iphoneos*]" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
	developmentTeam=`$plistBuddy -c "Print :objects:$configurationId:buildSettings:DEVELOPMENT_TEAM" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
	infoPlistFile=`$plistBuddy -c "Print :objects:$configurationId:buildSettings:INFOPLIST_FILE" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
	iphoneosDeploymentTarget=`$plistBuddy -c "Print :objects:$configurationId:buildSettings:IPHONEOS_DEPLOYMENT_TARGET" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
	# onlyActiveArch=`$plistBuddy -c "Print :objects:$configurationId:buildSettings:ONLY_ACTIVE_ARCH" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
	productBundleIdentifier=`$plistBuddy -c "Print :objects:$configurationId:buildSettings:PRODUCT_BUNDLE_IDENTIFIER" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
	productName=`$plistBuddy -c "Print :objects:$configurationId:buildSettings:PRODUCT_NAME" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
	provisionProfileUuid=`$plistBuddy -c "Print :objects:$configurationId:buildSettings:PROVISIONING_PROFILE" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
	provisionProfileName=`$plistBuddy -c "Print :objects:$configurationId:buildSettings:PROVISIONING_PROFILE_SPECIFIER" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`

	# logit "codeSignEntitlements:$codeSignEntitlements"
	# logit "codeSignResourceRulePath:$codeSignResourceRulePath"

	logit "【developmentTeam】:$developmentTeam"
	logit "【info Plist 文件】:$infoPlistFile"
	logit "【iphoneosDeploymentTarget】:$iphoneosDeploymentTarget"
	# logit "【onlyActiveArch】:$onlyActiveArch"
	logit "【BundleId】:$productBundleIdentifier"
	logit "【productName】:$productName"
	logit "【provisionProfileUuid】:$provisionProfileUuid"
	logit "【provisionProfileName】:$provisionProfileName"
	logit "【codeSignIdentity】:$codeSignIdentity"
	logit "【codeSignIdentitySDK】:$codeSignIdentitySDK"

}






##检查授权文件类型
function getProfileType
{
	profile=$1
	# provisionedDevices=`$plistBuddy -c 'Print :ProvisionedDevices' /dev/stdin <<< $($security cms -D -i "$profile"  ) | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
	##判断是否存在key:ProvisionedDevices
	haveKey=`$security cms -D -i "$profile" 2>/tmp/log.txt | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//' | grep ProvisionedDevices`
	if [[ $? -eq 0 ]]; then
		getTaskAllow=`$plistBuddy -c 'Print :Entitlements:get-task-allow' /dev/stdin <<< $($security cms -D -i "$profile" 2>/tmp/log.txt) `
		if [[ $getTaskAllow == true ]]; then
			profileType='development'
		else
			profileType='ad-hoc'
		fi
	else

		haveKeyProvisionsAllDevices=`$security cms -D -i "$profile" 2>/tmp/log.txt  | grep ProvisionsAllDevices`
		if [[ "$haveKeyProvisionsAllDevices" != '' ]]; then
			provisionsAllDevices=`$plistBuddy -c 'Print :ProvisionsAllDevices' /dev/stdin <<< $($security cms -D -i "$profile" 2>/tmp/log.txt) `
			if [[ $provisionsAllDevices == true ]]; then
				profileType='enterprise'
			else
				profileType='app-store'
			fi
		else
			profileType='app-store'
		fi
	fi
}

function setBundleId() {
  if [[ "$newBundleId" != '' ]] && [[ "$newBundleId" != "$appBundleId" ]]; then
  	## 设置configurationId下的bundle id
	  $plistBuddy -c "Set :objects:$configurationId:buildSettings:PRODUCT_BUNDLE_IDENTIFIER $newBundleId" "$projectFile"
	  if [[ $? -eq 0 ]]; then
	    appBundleId=$newBundleId;
	    logit "设置Bundle Id:$newBundleId"
	  else
	    errorExit "无法设置Bundle Id为:$newBundleId。"
	  fi

  fi
}

##设置build version
function setBuildVersion
{

  ##获取configurationId 下的Build Version

  infoPlistFile=`$plistBuddy -c "Print :objects:$configurationId:buildSettings:INFOPLIST_FILE" "$projectFile" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//'`
  ### 完整路径
	infoPlistFilePath="$xcodeProject"/../$infoPlistFile
	if [[ -f "$infoPlistFilePath" ]]; then
		$plistBuddy -c "Set :CFBundleVersion $gitVersionCount" "$infoPlistFilePath"
		logit "【Build Version】设置Buil Version:${gitVersionCount}"
	else
		errorExit "${infoPlistFilePath}文件不存在，无法修改"
	fi


}

##配置证书身份和授权文件
function configureSigningByRuby
{
	logitVerbose "========================配置签名身份和描述文件========================"
	rbDir="$( cd "$( dirname "$0"  )" && pwd  )"
	ruby ${rbDir}/xceditor.rb "$xcodeProject" $profileUuid $profileName "$matchCodeSignIdentity"  $profileTeamId
	if [[ $? -ne 0 ]]; then
		errorExit "xceditor.rb 修改配置失败！！"
	fi
}


##设置生产环境或者
function setEnvironment
{
	if [[ $haveConfigureEnvironment == true ]]; then
		bakExtension=".bak"
		bakFile=${environmentConfigureFile}${bakExtension}
		if [[ $productionEnvironment == true ]]; then
			if [[ "$currentEnvironmentValue" != "NO" ]]; then
				sed -i "$bakExtension" "/kBMIsTestEnvironment/s/YES/NO/" "$environmentConfigureFile" && rm -rf $bakFile
				logit "设置配置环境kBMIsTestEnvironment:NO"
			fi
		else
			if [[ "$currentEnvironmentValue" != "YES" ]]; then
				sed -i "$bakExtension" "/kBMIsTestEnvironment/s/NO/YES/" "$environmentConfigureFile" && rm -rf $bakFile
				logit "设置配置环境kBMIsTestEnvironment:YES"
			fi
		fi
	fi
}



function setDisableBitCode {

	## 设置configurationId下的BitCode配置
	ENABLE_BITCODE=`$plistBuddy -c "Print :objects:$configurationId:buildSettings:ENABLE_BITCODE" "$projectFile" `
	if [[ "$ENABLE_BITCODE" == "YES" ]]; then
	    $plistBuddy -c "Set :objects:$configurationId:buildSettings:ENABLE_BITCODE NO" "$projectFile"
	    logit "【BitCode】设置Enable Bitcode ：NO"
	fi
}

##设置手动签名,即不勾选：Xcode -> General -> Signing -> Automatically manage signning
function setManulSigning
{

	##在General 中的“Automatically manage sign”选项
	ProvisioningStyle=`$plistBuddy -c "Print :objects:$rootObject:attributes:TargetAttributes:$targetId:ProvisioningStyle " "$projectFile"`
	logit "【签名方式】General 中签名方式:$ProvisioningStyle"
	if [[ "$ProvisioningStyle" != "Manual" ]]; then
		##如果需要设置成自动签名,将Manual改成Automatic
		$plistBuddy -c "Set :objects:$rootObject:attributes:TargetAttributes:$targetId:ProvisioningStyle Manual" "$projectFile"
		logit "【签名方式】设置签名方式为:Manual"
	fi

	##在Setting 中的“Code Signing Style”选项
	if  versionCompareGE "$xcodeVersion" "9.0"; then
		## 这里必须对Release 和Debug 同时进行设置，不然会签名失败
		for id in ${buildConfigurations[@]}; do

			## 设置configurationId下的签名
			configurationName=`$plistBuddy -c "Print :objects:$id:name" "$projectFile"`
			CODE_SIGN_STYLE=`$plistBuddy -c "Print :objects:$id:buildSettings:CODE_SIGN_STYLE" "$projectFile" `
			if [[ $? -ne 0 ]]; then
				## 表示不存在，则添加
				logit "签名方式】添加CODE_SIGN_STYLE"
				$plistBuddy -c "Add :objects:$id:buildSettings:CODE_SIGN_STYLE string Manual" "$projectFile"
			fi
			logit "【签名方式】Setting 中${configurationName} 模式下的签名方式:$CODE_SIGN_STYLE"
			if [[ "$CODE_SIGN_STYLE" != "Manual" ]]; then
				##如果需要设置成自动签名,将Manual改成Automatic
				$plistBuddy -c "Set :objects:$id:buildSettings:CODE_SIGN_STYLE Manual" "$projectFile"
				logit "【签名方式】设置Setting 中${configurationName} 模式下的签名方式为:Manual"
			fi

		done


	fi

}


###开始构建
function build
{
	logit "开始构建IPA..."
	packageDir="$xcodeProject"/../build/package
	rm -rf "$packageDir"/*
	if [[ $debugConfiguration == true ]]; then
		configuration="Debug"
	else
		configuration="Release"
	fi

	archivePath="${packageDir}"/$targetName.xcarchive
	exprotPath="${packageDir}"/$targetName.ipa


	if [[ -d "$archivePath" ]]; then
		rm -rf "$archivePath"
	fi

	if [[ -f "$exprotPath" ]]; then
		rm -rf "$exprotPath"
	fi


	##组装xcodebuild 构建需要的参数
	cmd="$xcodebuild archive"
	if [[ $isExistXcWorkspace == true ]]; then
		cmd="$cmd"" -workspace \"$xcworkspace\""
	fi
	cmd="$cmd"" -scheme $targetName -archivePath \"$archivePath\" -configuration $configuration clean build"

	if [[ "$profileType" == "development" ]]; then
		cmd="$cmd"" ARCHS=\"$arch\""
	fi

	##判断是否安装xcpretty
	if which xcpretty  >/dev/null 2>&1 ;then
		cmd="$cmd"" | xcpretty -c "
	fi
	##set -o pipefail 为了获取到管道前一个命令xcodebuild的执行结果，否则$?一直都会是0
	eval "set -o pipefail && $cmd"

	if [[ $? -ne 0 ]]; then
		rm -rf "${packageDir}"/*
		errorExit "命令：${cmd} 执行失败!"
	fi



	##获取当前xcodebuild版本



	cmd="$xcodebuild -exportArchive"
	## > 8.3
	if versionCompareGE "$xcodeVersion" "8.3"; then
		logit "当前版本:$xcodeVersion"" > 8.3， 生成 -exportOptionsPlist 参数所需的Plist文件:/tmp/optionsplist.plist"
		generateOptionsPlist "$profileTeamId" "$profileType" "$appBundleId" "$profileName"
		##发现在xcode8.3 之后-exportPath 参数需要指定一个目录，而8.3之前参数指定是一个带文件名的路径！坑！
		 cmd="$cmd"" -archivePath \"$archivePath\" -exportPath \"$packageDir\" -exportOptionsPlist /tmp/optionsplist.plist"

	# < 8.3
	else
		cmd="$cmd"" -exportFormat IPA -archivePath \"$archivePath\" -exportPath \"$exprotPath\""
	fi
	##判断是否安装xcpretty
	if which xcpretty  >/dev/null 2>&1 ;then
		cmd="$cmd"" | xcpretty -c"
	fi
	eval "set -o pipefail && $cmd"

	if [[ $? -ne 0 ]]; then
		errorExit "$xcodebuild exportArchive  执行失败!"
	fi

	logit "IPA构建成功：\"$exprotPath\""


}

##在打企业包的时候：会报 archived-expanded-entitlements.xcent  文件缺失!这是xcode的bug
##链接：http://stackoverflow.com/questions/28589653/mac-os-x-build-server-missing-archived-expanded-entitlements-xcent-file-in-ipa
function repairXcentFile
{

### xcode 9.0 已经修复该问题了，所以针对xcode 9.0 以下进行修复。


if ! versionCompareGE "$xcodeVersion" "9.0"; then

	appName=`basename "$exprotPath" .ipa`
	xcentFile="${archivePath}"/Products/Applications/"${appName}".app/archived-expanded-entitlements.xcent
	if [[ -f "$xcentFile" ]]; then
		# logit  "修复xcent文件：\"$xcentFile\" "
		logit  "archived-expanded-entitlements.xcent 文件：已修复"
		unzip -o "$exprotPath" -d /"$packageDir" >/dev/null 2>&1
		app="${packageDir}"/Payload/"${appName}".app
		cp -af "$xcentFile" "$app" >/dev/null 2>&1
		##压缩,并覆盖原有的ipa
		cd "${packageDir}"  ##必须cd到此目录 ，否则zip会包含绝对路径
		zip -qry  "$exprotPath" Payload >/dev/null 2>&1 && rm -rf Payload
		cd - >/dev/null 2>&1
	else
		logit  "archived-expanded-entitlements.xcent 文件：跳过修复"
	fi
fi

}

##构建完成，检查App
function checkIPA
{

	##解压强制覆盖，并不输出日志

	if [[ -d /tmp/Payload ]]; then
		rm -rf /tmp/Payload
	fi
	unzip -o "$exprotPath" -d /tmp/ >/dev/null 2>&1
	appName=`basename "$exprotPath" .ipa`
	app=/tmp/Payload/"${appName}".app
	codesign --no-strict -v "$app"
	if [[ $? -ne 0 ]]; then
		errorExit "签名检查：签名校验不通过！"
	fi
	logit "==============签名检查：签名校验通过！==============="
	if [[ -d "$app" ]]; then
		ipaInfoPlistFile=${app}/Info.plist
		mobileProvisionFile=${app}/embedded.mobileprovision
		appShowingName=`$plistBuddy -c "Print :CFBundleName" $ipaInfoPlistFile`
		appBundleId=`$plistBuddy -c "print :CFBundleIdentifier" "$ipaInfoPlistFile"`
		appVersion=`$plistBuddy -c "Print :CFBundleShortVersionString" $ipaInfoPlistFile`
		appBuildVersion=`$plistBuddy -c "Print :CFBundleVersion" $ipaInfoPlistFile`
		appMobileProvisionName=`$plistBuddy -c 'Print :Name' /dev/stdin <<< $($security cms -D -i "$mobileProvisionFile" 2>/tmp/log.txt)`
		appMobileProvisionCreationDate=`$plistBuddy -c 'Print :CreationDate' /dev/stdin <<< $($security cms -D -i "$mobileProvisionFile" 2>/tmp/log.txt)`
        #授权文件有效时间
		appMobileProvisionExpirationDate=`$plistBuddy -c 'Print :ExpirationDate' /dev/stdin <<< $($security cms -D -i "$mobileProvisionFile" 2>/tmp/log.txt)`
        getProvisionfileExpirationDays "$mobileProvisionFile"
		appCodeSignIdenfifier=`codesign -dvvv "$app" 2>/tmp/log.txt &&  grep Authority /tmp/log.txt | head -n 1 | cut -d "=" -f2`
		#支持最小的iOS版本
		supportMinimumOSVersion=`$plistBuddy -c "print :MinimumOSVersion" "$ipaInfoPlistFile"`
		#支持的arch
		supportArchitectures=`$lipo -info "$app"/"$appName" | cut -d ":" -f 3`
		logit "【IPA】名字:$appShowingName"
		logit "【IPA】Xcode版本:$xcodeVersion"
		# getEnvirionment
		logit "【IPA】配置环境kBMIsTestEnvironment:$currentEnvironmentValue"
		logit "【IPA】bundle identify:$appBundleId"
		logit "【IPA】版本:$appVersion"
		logit "【IPA】build:$appBuildVersion"
		logit "【IPA】支持最低iOS版本:$supportMinimumOSVersion"
		logit "【IPA】支持的arch:$supportArchitectures"
		logit "【IPA】签名:$appCodeSignIdenfifier"
		logit "【IPA】授权文件:${appMobileProvisionName}.mobileprovision"
		logit "【IPA】授权文件创建时间:$appMobileProvisionCreationDate"
		logit "【IPA】授权文件过期时间:$appMobileProvisionExpirationDate"
    logit "【IPA】授权文件有效天数：${expirationDays} 天"
		getProfileType "$mobileProvisionFile"
        profileTypeToName "$profileType"
		logit "【IPA】分发渠道:$profileTypeName"

	else
		errorExit "解压失败！无法找到$app"
	fi
}



##重命名和备份
function renameAndBackup
{

	if [[ ! -d backupHistoryDir ]]; then
		mkdir -p $backupHistoryDir
	fi

	if [[ $haveConfigureEnvironment == true ]]; then
		if [[ "$currentEnvironmentValue" == 'YES' ]]; then
			environmentName='开发环境'
		else
			environmentName='生产环境'
		fi
	else
		environmentName='未知环境'
	fi

    profileTypeToName "$profileType"

	date=`date +"%Y%m%d_%H%M%S"`
	name=${appShowingName}_${date}_${environmentName}_${profileTypeName}_${appVersion}\($appBuildVersion\)
	ipaName=${name}.ipa
	textLogName=${name}.txt
	logit "【IPA】ipa重命名并备份到：$backupDir/$ipaName"

	mv "$exprotPath" "$packageDir"/$ipaName
	cp -af "$packageDir"/$ipaName $backupDir/$ipaName
	cp -af $tmpLogFile $backupDir/$textLogName

}


startDateSeconds=`date +%s`


while getopts p:c:r:b:dxvhgtl option; do
  case "${option}" in
    b) newBundleId=${OPTARG};;
  	g) getGitVersionCount;exit;;
    p) xcodeProject=${OPTARG};;
	c) checkChannel ${OPTARG};;
	t) productionEnvironment=false;;
	l) showUsableCodeSign;exit;;
	r) arch=${OPTARG};;
    x) set -x;;
	d) debugConfiguration=true;;
    v) verbose=true;;
    h | help) usage; exit;;
	* ) usage;exit;;
  esac
done



clean
initConfiguration
loginKeychainAccess
checkForProjectFile
checkIsExistWorkplace


checkEnvironmentConfigureFile

getXcodeVersion
getEnvirionment
getFirstTargets

getConfigurationsIds
getBuildConfigurationId
getAPPBundleId
setBundleId
autoMatchProvisionFile
autoMatchCodeSignIdentity
getGitVersionCount
setDisableBitCode
setManulSigning
setEnvironment
setBuildVersion
configureSigningByRuby
showBuildSetting
podInstall
build
repairXcentFile
checkIPA
renameAndBackup

endDateSeconds=`date +%s`

logit "【构建时长】构建时长：$((${endDateSeconds}-${startDateSeconds})) 秒"
