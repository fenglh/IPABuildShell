#!/bin/bash


# ----------------------------------------------------------------------
# name:         IPABuildShell.sh
# version:      3.0.0
# createTime:   2018-05-16
# description:  iOS 自动打包
# author:       冯立海
# email:        335418265@qq.com
# github:       https://github.com/aa335418265/IPABuildShell
# ----------------------------------------------------------------------

CMD_PlistBuddy="/usr/libexec/PlistBuddy"
CMD_Xcodebuild=$(which xcodebuild)
CMD_Security=$(which security)
CMD_Lipo=$(which lipo)
CMD_Codesign=$(which codesign)


##历史备份目录
Package_Dir=~/Desktop/PackageLog


##脚本工作目录
Shell_Work_Path=$(pwd)
##脚本文件目录
Shell_File_Path=$(cd `dirname $0`; pwd)
## 用户配置
Shell_User_Xcconfig_File="$Shell_File_Path/user.xcconfig"
## 脚本临时生成最终用于构建的配置
Tmp_Build_Xcconfig_File="$Package_Dir/build.xcconfig"
Tmp_Log_File="$Package_Dir/`date +"%Y%m%d%H%M%S"`.txt"
##临时文件目录
Tmp_Options_Plist_File="$Package_Dir/optionsplist.plist"


#############################################基本功能#############################################

function usage
{
	# setAliasShortCut
	echo ""
	echo "Usage:$(basename $0) -[abcdptx] [--enable-bitcode YES/NO] [--auto-buildversion YES/NO] ..."
	echo "可选项："
	echo "  -a | --archs 	<armv7|arm64|armv7 arm64> 	指定构建架构集，例如：-a 'armv7'或者 -a 'arm64' 或者 -a 'armv7 arm64' 等"
  	echo "  -b | --bundle-id bundleId 			设置Bundle Id"
  	echo "  -c | --channel <development|app-store|enterprise> 	指定分发渠道，development 内部分发，app-store商店分发，enterprise企业分发"
	echo "  -d | --provision-dir dir 			指定授权文件目录，默认会在~/Library/MobileDevice/Provisioning Profiles 中寻找"
	echo "  -p | --keychain-password passoword 		指定访问证书时解锁钥匙串的密码，即开机密码"
	echo "  -t | --configration-type  <Debug|Release> 	Debug 调试模式, Release 发布模式"
	echo "  -h | --help					帮助."
	echo "  -x 						脚本执行调试模式."

	echo "  --enable-bitcode <YES/NO> 			是否开启BitCode."
	echo "  --auto-buildversion <YES/NO>			是否自动修改构建版本号（设置为当前项目的git版本数量）"
	echo "  --env-filename filename 			指定开发和生产环境的配置文件"
	echo "  --env-varname varname				指定开发和生产环境的配置变量"
	echo "  --env-production <YES/NO>			YES 生产环境， NO 开发环境（只有指定filename和varname都存在时生效）"



	exit 0
}


## 日志格式化输出
function logit() {
    echo -e "\033[32m [IPABuildShell] \033[0m $@"
    echo "$@" >> "$Tmp_Log_File"
}

## 日志格式化输出
function errorExit(){

    echo -e "\033[31m【IPA构建失败】$@ \033[0m"
    exit 1
}

## 日志格式化输出
function warning(){

    echo -e "\033[33m【警告】$@ \033[0m"
}

##字符串版本号比较：大于等于
function versionCompareGE() { test "$(echo "$@" | tr " " "\n" | sort -rn | head -n 1)" == "$1"; }

## 备份历史数据
function historyBackup() {

		## 备份上一次的打包数据
	if [[ -d "$Package_Dir" ]]; then
		for name in `ls $Package_Dir` ; do
			if [[ "$name" == "History" ]] && [[ -d "$Package_Dir/$name" ]]; then
				continue;
			fi

			cp -rf "$Package_Dir/$name" "$Package_Dir/History"
			rm -rf "$Package_Dir/$name"
		done
	else
		mkdir -p "$Package_Dir/History"
	fi
}


## 获取xcpretty安装路径
function getXcprettyPath() {
	xcprettyPath=$(which xcpretty)
	echo $xcprettyPath
}

## 初始化build.xcconfig配置文件
function initBuildXcconfig() {
	local xcconfigFile=$Tmp_Build_Xcconfig_File
	if [[ -f "$xcconfigFile" ]]; then
		## 清空
		> "$xcconfigFile"
	else 
		## 生成文件
		touch "$xcconfigFile"
	fi
	echo $xcconfigFile
}

function initUserXcconfig() {
	if [[ -f "$Shell_User_Xcconfig_File" ]]; then
		local allKeys=(CONFIGRATION_TYPE ARCHS CHANNEL ENABLE_BITCODE DEBUG_INFORMATION_FORMAT AUTO_BUILD_VERSION UNLOCK_KEYCHAIN_PWD API_ENV_FILE_NAME API_ENV_VARNAME API_ENV_PRODUCTION PROVISION_DIR)
		for key in ${allKeys[@]}; do
			local value=$(getXcconfigValue "$Shell_User_Xcconfig_File" "$key")
			# echo "===$value====="
			if [[ "$value" ]]; then
				eval "$key"='$value'
				logit "【初始化用户配置】${key} = `eval echo "$value"`"
			fi

		done
	fi



}

function getXcconfigValue() {
	local xcconfigFile=$1
	local key=$2
	if [[ ! -f "$xcconfigFile" ]]; then
		exit 1
	fi
	## 去掉//开头 ;  查找key=特征
	local value=$(grep -v "[ ]*//" "$xcconfigFile" | grep -e "[ ]*$key[ ]*=" | tail -1| cut -d "=" -f2 | grep -o "[^ ]\+\( \+[^ ]\+\)*")
	echo $value
}

## 解锁keychain
function unlockKeychain(){
	$CMD_Security unlock-keychain -p "$UNLOCK_KEYCHAIN_PWD" "$HOME/Library/Keychains/login.keychain" 2>/dev/null
	if [[ $? -ne 0 ]]; then
		return 1
	fi
	$CMD_Security unlock-keychain -p "$UNLOCK_KEYCHAIN_PWD" "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null
	if [[ $? -ne 0 ]]; then
		return 1
	fi
	return 0
}

## 添加一项配置
function setXCconfigWithKeyValue() {

	local key=$1
	local value=$2

	local xcconfigFile=$Tmp_Build_Xcconfig_File
	if [[ ! -f "$xcconfigFile" ]]; then
		exit 1
	fi

	if grep -q "[ ]*$key[ ]*=.*" "$xcconfigFile";then 
		## 进行替换
		sed -i "_bak" "s/[ ]*$key[ ]*=.*/$key = $value/g" "$xcconfigFile"
	else 
		## 进行追加(重定位)
		echo "$key = $value" >>"$xcconfigFile"
	fi
}

##获取Xcode 版本
function getXcodeVersion() {
	local xcodeVersion=`$CMD_Xcodebuild -version | head -1 | cut -d " " -f 2`
	echo $xcodeVersion
}


##xcode 8.3之后使用-exportFormat导出IPA会报错 xcodebuild: error: invalid option '-exportFormat',改成使用-exportOptionsPlist
function generateOptionsPlist(){
	local provisionFile=$1
	if [[ ! -f "$provisionFile" ]]; then
		exit 1
	fi

	local provisionFileTeamID=$(getProvisionfileTeamID "$provisionFile")
	local provisionFileType=$(getProfileType "$provisionFile")
	local provisionFileName=$(getProvisionfileName "$provisionFile")
	local provisionFileBundleID=$(getProfileBundleId "$provisionFile")
	local compileBitcode='<false/>'
	if [[ "$ENABLE_BITCODE" == 'YES' ]]; then
		compileBitcode='<true/>'
	fi


	local plistfileContent="
	<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n
	<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n
	<plist version=\"1.0\">\n
	<dict>\n
	<key>teamID</key>\n
	<string>$provisionFileTeamID</string>\n
	<key>method</key>\n
	<string>$provisionFileType</string>\n
	<key>stripSwiftSymbols</key>\n
    <true/>\n
	<key>provisioningProfiles</key>\n
    <dict>\n
        <key>$provisionFileBundleID</key>\n
        <string>$provisionFileName</string>\n
    </dict>\n
	<key>compileBitcode</key>\n
	$compileBitcode\n
	</dict>\n
	</plist>\n
	"
	## 重定向
	echo -e "$plistfileContent" > "$Tmp_Options_Plist_File"
	echo "$Tmp_Options_Plist_File"
}

##检查xcodeproj 是否存在
function checkXcodeprojExist() {

	local xcodeprojPath=$(find "$Shell_Work_Path" -maxdepth 1  -type d -name "*.xcodeproj")
	if [[ ! -d "$xcodeprojPath" ]]; then
		exit 1
	fi
	echo  $xcodeprojPath
}

##检查xcworkspace 是否存在
function getXcworkspace() {

	local xcworkspace=$(find "$Shell_Work_Path" -maxdepth 1  -type d -name "*.xcworkspace")
	if [[ -d "$xcworkspace" ]]; then
		echo $xcworkspace
	fi
}

##检查podfile是否存在
function  checkPodfileExist() {

	local podfile=$(find "$Shell_Work_Path" -maxdepth 1  -type f -name "Podfile")
	if [[ ! -f "$podfile" ]]; then
		exit 1
	fi
	echo $podfile
}


function getProjectVersion() {
	local infoPlistFile=$1
	if [[ ! -f "$infoPlistFile" ]]; then
		exit 1
	fi
	local projectVersion=$($CMD_PlistBuddy -c "Print :CFBundleShortVersionString"  "$infoPlistFile")

	echo $projectVersion
}
function getBuildVersion() {
	local infoPlistFile=$1
	if [[ ! -f "$infoPlistFile" ]]; then
		exit 1
	fi
	local projectVersion=$($CMD_PlistBuddy -c "Print :CFBundleVersion"  "$infoPlistFile")

	echo $projectVersion
}

## 获取git仓库版本数量
function getGitRepositoryVersionNumbers (){
		## 是否存在.git目录
	local gitRepository=$(find "$Shell_Work_Path" -maxdepth 1  -type d -name ".git")
	if [[ ! -d "$gitRepository" ]]; then
		exit 1
	fi

	local gitRepositoryVersionNumbers=$(git -C "$Shell_Work_Path" rev-list HEAD 2>/dev/null | wc -l | grep -o "[^ ]\+\( \+[^ ]\+\)*")
	if [[ $? -ne 0 ]]; then
		## 可能是git只有在本地，而没有提交到服务器,或者没有网络
		exit 1
	fi
	echo $gitRepositoryVersionNumbers
}

#设置Info.plist文件的构建版本号
function setBuildVersion () {
	local infoPlistFile=$1
	local buildVersion=$2
	if [[ ! -f "$infoPlistFile" ]]; then
		exit 1
	fi
	$CMD_PlistBuddy -c "Set :CFBundleVersion $buildVersion" "$infoPlistFile"
}

function finalIPAName ()
{

	local targetName=$1
	local apiEnvFile=$2
	local apiEnvVarName=$3
	local infoPlistFile=$4
	local channelName=$5

	if [[ ! -f "$infoPlistFile" ]]; then
		return;
	fi
		## IPA和日志重命名
	local curDatte=`date +"%Y%m%d_%H%M%S"`
	local ipaName=${targetName}_${curDatte}
	local apiEnvValue=$(getIPAEnvValue "$apiEnvFile" "$apiEnvVarName")
	local projectVersion=$(getProjectVersion "$infoPlistFile")
	local buildVersion=$(getBuildVersion "$infoPlistFile")



	if [[ "$apiEnvValue" ]]; then
		local apiEnvName=''
		if [[ "$apiEnvValue" == 'YES' ]]; then
			apiEnvName='生产环境'
		elif [[ "$apiEnvValue" == 'NO' ]]; then
			apiEnvName='开发环境'
		else
			apiEnvName='未知环境'
		fi
		ipaName="$ipaName""_${apiEnvName}"
	fi
	ipaName="${ipaName}""_${channelName}""_${projectVersion}""(${buildVersion})"
	echo "$ipaName"
}


##获取签名方式,##设置手动签名,即不勾选：Xcode -> General -> Signing -> Automatically manage signning
## 在xcode 9之前（不包含9），只有在General这里配置是否手动签名，在xcode9之后，多加了一项在setting中
function getCodeSigningStyle ()
{

	local pbxproj=$1/project.pbxproj
	local targetId=$2
	local rootObject=$($CMD_PlistBuddy -c "Print :rootObject" "$pbxproj")
	if [[ ! -f "$pbxproj" ]]; then
		exit 1
	fi
	##没有勾选过Automatically manage signning时，则不存在ProvisioningStyle
	signingStyle=$($CMD_PlistBuddy -c "Print :objects:$rootObject:attributes:TargetAttributes:$targetId:ProvisioningStyle " "$pbxproj" 2>/dev/null)
	echo $signingStyle

}

##设置签名方式（手动/自动）,注意：如果项目存在中文文件名，使用PlistBuddy 命令对pbxproj文件进行修改导致乱码！该方法已被抛弃!
function setManulCodeSigning ()
{

	local pbxproj=$1/project.pbxproj
	local targetId=$2
	local rootObject=$($CMD_PlistBuddy -c "Print :rootObject" "$pbxproj")
	##如果需要设置成自动签名,将Manual改成Automatic
	$CMD_PlistBuddy -c "Set :objects:$rootObject:attributes:TargetAttributes:$targetId:ProvisioningStyle Manual" "$pbxproj"


}

function setManulCodeSigningRuby()
{
	local project=$1
	local targetId=$2
	local pbxproj=$1/project.pbxproj


	local codeSigningStyle=$(getCodeSigningStyle "$xcodeprojPath" "$targetId")
	if [[ ! "$codeSigningStyle" ]] || [[ "$codeSigningStyle" != "Manual" ]]; then
		logit "【签名信息】设置签名方式:Manual"
		ruby "$Shell_File_Path/set_codesign_style.rb" "$project" "$targetId" 2>/dev/null
		## 这里会报错 :如果c [Xcodeproj] Unknown object version. (RuntimeError),但是实际可以修改成功，暂时不做下面的逻辑处理
		# if [[ $? -ne 0 ]]; then
		# 	local rootObject=$($CMD_PlistBuddy -c "Print :rootObject" "$pbxproj")
		# 	local compatibilityVersion=$($CMD_PlistBuddy -c "Print :objects:$rootObject:compatibilityVersion" "$pbxproj")
		# 	if [[ "$compatibilityVersion"=="Xcode 9.3" ]]; then
		# 		errorExit "设置手动签名失败,cocoapod 不兼容Xcode 9.3。版本请在【项目】- xxxTarget】- Show the File inspector】- Project Document】-【Project Format】 中选中小于Xcode 9.3-compatible的一项"
		# 	else
		# 		errorExit "设置手动签名失败，请在【项目】-【General】-【Signing】中去掉勾选Automatically manage signning"
		# 	fi

		# fi
	fi

}

function addManulCodeSigning ()
{
	local pbxproj=$1/project.pbxproj
	local targetId=$2
	local rootObject=$($CMD_PlistBuddy -c "Print :rootObject" "$pbxproj")
	##如果需要设置成自动签名,将Manual改成Automatic
	$CMD_PlistBuddy -c "Add :objects:$rootObject:attributes:TargetAttributes:$targetId:ProvisioningStyle string Manual" "$pbxproj"
}


#获取,会在当前脚本执行目录以及5级内的子目录下自动寻找

function findIPAEnvFile () {

	local fileName=$1
	## 如果直接是全路径文件,直接返回
	if [[ -f "$fileName" ]]; then
		echo $fileName
	else
		local apiEnvFile=`find "$Shell_Work_Path" -maxdepth 5 -path "./.Trash" -prune -o -type f -name "$fileName" -print| head -n 1`
		if [[ ! -f "$apiEnvFile" ]]; then
			exit 1
		fi
		echo $apiEnvFile
	fi
}

## 获取接口环境的值
function getIPAEnvValue () {
	local apiEnvFile=$1
	local apiEnvVarName=$2

	if [[ ! -f "$apiEnvFile" ]]; then
		exit 1
	fi
	local apiEnvValue=$(grep "$apiEnvVarName" "$apiEnvFile" | grep -v '^//' | cut -d ";" -f 1 | cut -d "=" -f 2 | sed 's/^[ \t]*//g' | sed 's/[ \t]*$//g')
	echo $apiEnvValue
}

function setIPAEnvFile () {
	local apiEnvFile=$1
	local apiEnvVarName=$2
	local apiEnvVarValue=$3

	if [[ ! -f "$apiEnvFile" ]]; then
		exit 1
	fi
	sed -i ".bak" "/[ ]*$apiEnvVarName[ ]*=/s/=.*/= $apiEnvVarValue;\/\/脚本自动设置/" "$apiEnvFile" && rm -rf ${apiEnvFile}.bak
}

##获取授权文件过期天数
function getProvisionfileExpirationDays()
{
    local provisionFile=$1

    if [[ ! -f "$provisionFile" ]]; then
    	exit 1
    fi
    ##切换到英文环境，不然无法转换成时间戳
    export LANG="en_US.UTF-8"
    ##获取授权文件的过期时间
    local profileExpirationDate=$($CMD_PlistBuddy -c 'Print :ExpirationDate' /dev/stdin <<< $($CMD_Security cms -D -i "$provisionFile" 2>/dev/null))
    local profileExpirationTimestamp=$(date -j -f "%a %b %d  %T %Z %Y" "$profileExpirationDate" "+%s")
    local nowTimestamp=`date +%s`
    local r=$[profileExpirationTimestamp-nowTimestamp]
    local expirationDays=$[r/60/60/24]
    echo $expirationDays
}

## 获取授权文件中的签名id
function getProvisionCodeSignIdentity
{
	local provisionFile=$1
	if [[ ! -f "$provisionFile" ]]; then
		exit 1
	fi
	## 获取DeveloperCertificates 字段
	local data=$($CMD_Security cms -D -i "$provisionFile" | grep data | head -n 1 | sed 's/.*<data>//g' | sed 's/<\/data>.*//g' ) 


	if [[ $? -ne 0 ]]; then
		exit 1
	fi
	## 使用openssl进行解码 1. 构建cer证书 2. 解码证书
	## 1.
	local tmpCerFile='/tmp/tmp.cer'
	echo "-----BEGIN CERTIFICATE-----" 	> "$tmpCerFile"
	echo "${data}"						>> "$tmpCerFile"
	echo "-----END CERTIFICATE-----"	>> "$tmpCerFile"


	local codeSignIdentity=$(openssl x509 -noout -text -in "$tmpCerFile"  | grep Subject | grep "CN=" | cut -d "," -f2 | cut -d "=" -f2)


	echo $codeSignIdentity
}

## 获取授权文件UUID
function getProvisionfileUUID()
{
	local provisionFile=$1
	if [[ ! -f "$provisionFile" ]]; then
		exit 1
	fi
	provisonfileUUID=$($CMD_PlistBuddy -c 'Print :UUID' /dev/stdin <<< $($CMD_Security cms -D -i "$provisionFile" 2>/dev/null))
	echo $provisonfileUUID
}

## 获取授权文件TeamID
function getProvisionfileTeamID()
{
	local provisionFile=$1
	if [[ ! -f "$provisionFile" ]]; then
		exit 1
	fi
	provisonfileTeamID=$($CMD_PlistBuddy -c 'Print :Entitlements:com.apple.developer.team-identifier' /dev/stdin <<< $($CMD_Security cms -D -i "$provisionFile" 2>/dev/null))
	echo $provisonfileTeamID
}

## 获取授权文件名称
function getProvisionfileName()
{
	local provisionFile=$1
	if [[ ! -f "$provisionFile" ]]; then
		exit 1
	fi
	provisonfileName=$($CMD_PlistBuddy -c 'Print :Name' /dev/stdin <<< $($CMD_Security cms -D -i "$provisionFile" 2>/dev/null))
	echo $provisonfileName
}


##这里只取第一个target id
function getBuildTargetId()
{
	local pbxproj=$1/project.pbxproj
	if [[ ! -f "$pbxproj" ]]; then
		exit 1
	fi
	local rootObject=$($CMD_PlistBuddy -c "Print :rootObject" "$pbxproj")
	local targetList=$($CMD_PlistBuddy -c "Print :objects:${rootObject}:targets" "$pbxproj" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//')
	#括号用于初始化数组,例如arr=(1,2,3),括号用于初始化数组,例如arr=(1,2,3)
	local targets=($(echo $targetList));
	##这里，只取第一个target,因为默认情况下xcode project 会有自动生成Tests 以及 UITests 两个target
	local targetId=${targets[0]}
	echo $targetId
}

##这里只取第一个target
function getTargetName()
{
	local pbxproj=$1/project.pbxproj
	local targetId=$2
	if [[ ! -f "$pbxproj" ]]; then
		exit 1
	fi
	local targetName=$($CMD_PlistBuddy -c "Print :objects:$targetId:name" "$pbxproj")
	echo $targetName
}


## 获取配置ID,主要是后续用了获取bundle id
function getConfigurationIds() {

	##配置模式：Debug 或 Release
	local targetId=$2
	local pbxproj=$1/project.pbxproj
	if [[ ! -f "$pbxproj" ]]; then
		exit 1
	fi
  	local buildConfigurationListId=$($CMD_PlistBuddy -c "Print :objects:$targetId:buildConfigurationList" "$pbxproj")
  	local buildConfigurationList=$($CMD_PlistBuddy -c "Print :objects:$buildConfigurationListId:buildConfigurations" "$pbxproj" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//')
  	##数组中存放的分别是release和debug对应的id
  	local configurationTypeIds=$(echo $buildConfigurationList)
  	echo $configurationTypeIds

}

function getConfigurationIdWithType(){

	local configrationType=$3
	local targetId=$2
	local pbxproj=$1/project.pbxproj
	if [[ ! -f "$pbxproj" ]]; then
		exit 1
	fi

	local configurationTypeIds=$(getConfigurationIds "$1" $targetId)
	for id in ${configurationTypeIds[@]}; do
	local name=$($CMD_PlistBuddy -c "Print :objects:$id:name" "$pbxproj")
	if [[ "$configrationType" == "$name" ]]; then
		echo $id
	fi
	done
}

function getInfoPlistFile()
{
	configurationId=$2
	local pbxproj=$1/project.pbxproj
	if [[ ! -f "$pbxproj" ]]; then
		exit 1
	fi
   local  infoPlistFileName=$($CMD_PlistBuddy -c "Print :objects:$configurationId:buildSettings:INFOPLIST_FILE" "$pbxproj" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//')
	  ### 完整路径
	infoPlistFilePath="$1/../$infoPlistFileName"
	echo $infoPlistFilePath
}


## 获取bundle Id,分为Releae和Debug
function getProjectBundleId()
{	
	local configurationId=$2
	local pbxproj=$1/project.pbxproj
	if [[ ! -f "$pbxproj" ]]; then
		exit 1
	fi
	local bundleId=$($CMD_PlistBuddy -c "Print :objects:$configurationId:buildSettings:PRODUCT_BUNDLE_IDENTIFIER" "$pbxproj" | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//')
	echo $bundleId
}

function checkCodeSignIdentityValid()
{
	local codeSignIdentity=$1
	local content=$($CMD_Security find-identity -v -p codesigning | grep "$codeSignIdentity")
	echo "$content"
}


##匹配签名身份--方法已被替换
# function matchCodeSignIdentity()
# {
# 	local provisionFile=$1
# 	local channel=$2
# 	local channelFilterString=''
# 	local startSearchString=''
# 	local endSearchString='1\\0230\\021\\006\\003U\\004'


# 	if [[ ! -f "$provisionFile" ]]; then
# 		exit 1;
# 	fi

# 	if [[ "$channel" == 'enterprise' ]] || [[ "$channel" == 'app-store' ]]; then
# 		channelFilterString='iPhone Distribution: '
# 		startSearchString='003U\\004\\003\\0142'
# 	else
# 		channelFilterString='iPhone Developer: '
# 		startSearchString='003U\\004\\003\\014&'
# 	fi
# 	profileTeamId=$($CMD_PlistBuddy -c 'Print :Entitlements:com.apple.developer.team-identifier' /dev/stdin <<< $($CMD_Security cms -D -i "$provisionFile" 2>/dev/null))
# 	codeSignIdentity=$($CMD_Security dump-keychain 2>/dev/null | grep "\"subj\"<blob>=" | cut -d '=' -f 2 | grep "$profileTeamId" | awk -F "[\"\"]" '{print $2}' | grep "$channelFilterString" | sed "s/\(.*\)$startSearchString\(.*\)$endSearchString\(.*\)/\2/g" | head -n 1)
# 	echo "$codeSignIdentity"
# }

##匹配授权文件
function matchMobileProvisionFile()
{	

	##分发渠道
	local channel=$1
	local appBundleId=$2
	##授权文件目录
	local mobileProvisionFileDir=$3
	if [[ ! -d "$mobileProvisionFileDir" ]]; then
		exit 1
	fi
	##遍历
	local provisionFile=''
	local provisionFileExpirationDays=0

	for file in "${mobileProvisionFileDir}"/*.mobileprovision; do
		local bundleIdFromProvisionFile=$(getProfileBundleId "$file")
		if [[ "$bundleIdFromProvisionFile" ]] && [[ "$appBundleId" == "$bundleIdFromProvisionFile" ]]; then
			local profileType=$(getProfileType "$file")
			if [[ "$profileType" == "$channel" ]]; then
				local expirationDays=$(getProvisionfileExpirationDays "$file")
				## 匹配到有效天数最大的授权文件
				if [[ $expirationDays -gt $provisionFileExpirationDays ]]; then
					provisionFile=$file
					provisionFileExpirationDays=$expirationDays
				fi
			fi
		fi
	done
	echo $provisionFile
}



function getProfileBundleId()
{
	local profile=$1
	local applicationIdentifier=$($CMD_PlistBuddy -c 'Print :Entitlements:application-identifier' /dev/stdin <<< "$($CMD_Security cms -D -i "$profile" 2>/dev/null )")
	if [[ $? -ne 0 ]]; then
		exit 1;
	fi
	##截取bundle id,这种截取方法，有一点不太好的就是：当applicationIdentifier的值包含：*时候，会截取失败,如：applicationIdentifier=6789.*
	local bundleId=${applicationIdentifier#*.}
	echo $bundleId
}

##获取授权文件类型
function getProfileType()
{
	local profile=$1
	local profileType=''
	if [[ ! -f "$profile" ]]; then
		exit 1
	fi
	##判断是否存在key:ProvisionedDevices
	local haveKey=$($CMD_Security cms -D -i "$profile" 2>/dev/null | sed -e '/Array {/d' -e '/}/d' -e 's/^[ \t]*//' | grep ProvisionedDevices)
	if [[ "$haveKey" ]]; then
		local getTaskAllow=$($CMD_PlistBuddy -c 'Print :Entitlements:get-task-allow' /dev/stdin <<< $($CMD_Security cms -D -i "$profile" 2>/dev/null ) )
		if [[ $getTaskAllow == true ]]; then
			profileType='development'
		else
			profileType='ad-hoc'
		fi
	else

		local haveKeyProvisionsAllDevices=$($CMD_Security cms -D -i "$profile" 2>/dev/null | grep ProvisionsAllDevices)
		if [[ "$haveKeyProvisionsAllDevices" != '' ]]; then
			provisionsAllDevices=$($CMD_PlistBuddy -c 'Print :ProvisionsAllDevices' /dev/stdin <<< "$($CMD_Security cms -D -i "$profile" 2>/dev/null)" )
			if [[ $provisionsAllDevices == true ]]; then
				profileType='enterprise'
			else
				profileType='app-store'
			fi
		else
			profileType='app-store'
		fi
	fi
	echo $profileType
}

## 获取profile type的中文名字
function getProfileTypeCNName()
{
    local profileType=$1
    local profileTypeName
    if [[ "$profileType" == 'app-store' ]]; then
        profileTypeName='商店分发'
    elif [[ "$profileType" == 'enterprise' ]]; then
        profileTypeName='企业分发'
    else
        profileTypeName='内部测试'
    fi
    echo $profileTypeName

}



### 开始构建归档，因为该函数里面逻辑较多，所以在里面添加了日志打印
function archiveBuild()
{
	local targetName=$1
	local xcconfigFile=$2
	local xcworkspacePath=$(getXcworkspace)

	## 暂时使用全局变量---
	archivePath="${Package_Dir}"/$targetName.xcarchive



	####################进行归档########################
	local cmd="$CMD_Xcodebuild archive"
	if [[ "$xcworkspacePath" ]]; then
		cmd="$cmd"" -workspace \"$xcworkspacePath\""
	fi
	cmd="$cmd"" -scheme $targetName -archivePath \"$archivePath\" -configuration $CONFIGRATION_TYPE -xcconfig $xcconfigFile clean build"

	local xcpretty=$(getXcprettyPath)
	if [[ "$xcpretty" ]]; then
		## 格式化日志输出
		cmd="$cmd"" | xcpretty "
	fi

	# 执行构建，set -o pipefail 为了获取到管道前一个命令xcodebuild的执行结果，否则$?一直都会是0
	eval "set -o pipefail && $cmd " 
	if [[ $? -ne 0 ]]; then
		errorExit "归档失败，请检查编译日志(编译错误、签名错误等)。"
	fi


	# echo "$archivePath"
}



function exportIPA() {

	local archivePath=$1
	local provisionFile=$2
	local targetName=${archivePath%.*}
	targetName=${targetName##*/}
	local xcodeVersion=$(getXcodeVersion)
	exportPath="${Package_Dir}"/${targetName}.ipa

	if [[ ! -f "$provisionFile" ]]; then
		exit 1
	fi

	####################进行导出IPA########################
	local cmd="$CMD_Xcodebuild -exportArchive"
	## >= 8.3
	if versionCompareGE "$xcodeVersion" "8.3"; then
		local optionsPlistFile=$(generateOptionsPlist "$provisionFile")
		 cmd="$cmd"" -archivePath \"$archivePath\" -exportPath \"$Package_Dir\" -exportOptionsPlist \"$optionsPlistFile\""
	else
		cmd="$cmd"" -exportFormat IPA -archivePath \"$archivePath\" -exportPath \"$exportPath\""
	fi
	##判断是否安装xcpretty
	xcpretty=$(getXcprettyPath)
	if [[ "$xcpretty" ]]; then
		## 格式化日志输出
		cmd="$cmd | xcpretty -c"
	fi
	# 这里需要添加>/dev/null 2>&1; ，否则echo exportPath 作为函数返回参数，会带有其他信息
	eval "set -o pipefail && $cmd" ;
	if [[ $? -ne 0 ]]; then
		exit 1
	fi
}



##在包的时候：会报 archived-expanded-entitlements.xcent  文件缺失!这是xcode的bug
##链接：http://stackoverflow.com/questions/28589653/mac-os-x-build-server-missing-archived-expanded-entitlements-xcent-file-in-ipa
## 发现在 xcode >= 8.3.3 以上都不存在 ,在xcode8.2.1 存在
function repairXcentFile()
{

	local exportPath=$1
	local archivePath=$2
	local xcodeVersion=$(getXcodeVersion)

	## 小于8.3(不包含8.3)
	if ! versionCompareGE "$xcodeVersion" "8.3"; then
		local appName=`basename "$exportPath" .ipa`
		local xcentFile="${archivePath}"/Products/Applications/"${appName}".app/archived-expanded-entitlements.xcent
		if [[ -f "$xcentFile" ]]; then
			# baxcent文件从archive中拷贝到IPA中
			unzip -o "$exportPath" -d /"$Package_Dir" >/dev/null 2>&1
			local app="${Package_Dir}"/Payload/"${appName}".app
			cp -af "$xcentFile" "$app" >/dev/null 2>&1
			##压缩,并覆盖原有的ipa
			cd "${Package_Dir}"  ##必须cd到此目录 ，否则zip会包含绝对路径
			zip -qry  "$exportPath" Payload >/dev/null 2>&1 && rm -rf Payload
			cd - >/dev/null 2>&1
			## 因为重新加压，文件名和路径都没有变化
			local ipa=$exportPath
			echo  "$ipa"
		fi
	fi
}


#构建完成，检查App
function checkIPA()
{
	local exportPath=$1
	if [[ ! -f "$exportPath" ]]; then
		exit 1
	fi
	local ipaName=`basename "$exportPath" .ipa`
	##解压强制覆盖，并不输出日志
	if [[ -d "${Package_Dir}/Payload" ]]; then
		rm -rf "${Package_Dir}/Payload"
	fi
	unzip -o "$exportPath" -d ${Package_Dir} >/dev/null 2>&1
	
	local app=${Package_Dir}/Payload/"${ipaName}".app
	codesign --no-strict -v "$app"
	if [[ $? -ne 0 ]]; then
		errorExit "签名检查：签名校验不通过！"
	fi
	logit "【签名校验】签名校验通过"
	if [[ ! -d "$app" ]]; then
		errorExit "解压失败！无法找到$app"
	fi

	local ipaInfoPlistFile=${app}/Info.plist
	local mobileProvisionFile=${app}/embedded.mobileprovision
	local appShowingName=`$CMD_PlistBuddy -c "Print :CFBundleName" $ipaInfoPlistFile`
	local appBundleId=`$CMD_PlistBuddy -c "print :CFBundleIdentifier" "$ipaInfoPlistFile"`
	local appVersion=`$CMD_PlistBuddy -c "Print :CFBundleShortVersionString" $ipaInfoPlistFile`
	local appBuildVersion=`$CMD_PlistBuddy -c "Print :CFBundleVersion" $ipaInfoPlistFile`
	local appMobileProvisionName=`$CMD_PlistBuddy -c 'Print :Name' /dev/stdin <<< $($CMD_Security cms -D -i "$mobileProvisionFile" 2>/dev/null)`
	local appMobileProvisionCreationDate=`$CMD_PlistBuddy -c 'Print :CreationDate' /dev/stdin <<< $($CMD_Security cms -D -i "$mobileProvisionFile" 2>/dev/null)`
    #授权文件有效时间
	local appMobileProvisionExpirationDate=`$CMD_PlistBuddy -c 'Print :ExpirationDate' /dev/stdin <<< $($CMD_Security cms -D -i "$mobileProvisionFile" 2>/dev/null)`
	local provisionFileExpirationDays=$(getProvisionfileExpirationDays "$mobileProvisionFile")
	local provisionType=$(getProfileType "$mobileProvisionFile")
	local channelName=$(getProfileTypeCNName $provisionType)
	local appCodeSignIdenfifier=$($CMD_Codesign -dvvv "$app" 2>/tmp/log.txt &&  grep Authority /tmp/log.txt | head -n 1 | cut -d "=" -f2)
	#支持最小的iOS版本
	local supportMinimumOSVersion=$($CMD_PlistBuddy -c "print :MinimumOSVersion" "$ipaInfoPlistFile")
	#支持的arch
	local supportArchitectures=$($CMD_Lipo -info "$app"/"$ipaName" | cut -d ":" -f 3)

	logit "【IPA 信息】名字:$appShowingName"
	# getEnvirionment
	# logit "配置环境kBMIsTestEnvironment:$currentEnvironmentValue"
	logit "【IPA 信息】bundleID:$appBundleId"
	logit "【IPA 信息】版本:$appVersion"
	logit "【IPA 信息】build:$appBuildVersion"
	logit "【IPA 信息】支持最低iOS版本:$supportMinimumOSVersion"
	logit "【IPA 信息】支持的archs:$supportArchitectures"
	logit "【IPA 信息】签名:$appCodeSignIdenfifier"
	logit "【IPA 信息】授权文件:${appMobileProvisionName}.mobileprovision"
	logit "【IPA 信息】授权文件创建时间:$appMobileProvisionCreationDate"
	logit "【IPA 信息】授权文件过期时间:$appMobileProvisionExpirationDate"
    logit "【IPA 信息】授权文件有效天数：${provisionFileExpirationDays} 天"
    logit "【IPA 信息】授权文件分发渠道：${channelName}($provisionType)"

    ## 清除解压出来的Playload
    rm -rf ${Package_Dir}/Payload
}



################################################################################################



## 默认配置
CONFIGRATION_TYPE='Release'
ARCHS='arm64'
CHANNEL='development'
ENABLE_BITCODE='NO'
DEBUG_INFORMATION_FORMAT='dwarf'
AUTO_BUILD_VERSION='NO'
UNLOCK_KEYCHAIN_PWD=''
CODE_SIGN_STYLE='Manual'
UNLOCK_KEYCHAIN_PWD=''
PROVISION_DIR="${HOME}/Library/MobileDevice/Provisioning Profiles"
## 为了方便脚本配置接口环境（测试/正式）,需要3个参数分别是：接口环境配置文件名、接口环境变量名、接口环境变量值
##是否是生产环境，默认为空不做任何修改
API_ENV_PRODUCTION=''
API_ENV_FILE_NAME=''
API_ENV_VARNAME=''



###########################################核心逻辑#####################################################



while [ "$1" != "" ]; do
    case $1 in
        -b | --bundle-id )
            shift
            NEW_BUNDLE_IDENTIFIER=("$1")
            ;;
        -c | --channel )
            shift
            CHANNEL="$1"
            ;;
        -d | --provision-dir )
            shift
            PROVISION_DIR="$1"
            ;;
        -t | --configration-type )
            shift
            CONFIGRATION_TYPE="$1"
            ;;
        -a| --archs )
            shift
            ARCHS="$1"
            ;;
        -p| --keychain-password )
            shift
            UNLOCK_KEYCHAIN_PWD="$1"
            ;;
         -x )
			set -x;;
            
      	--enable-bitcode )
            ENABLE_BITCODE='YES'
            ;;
      	--auto-buildversion )
            AUTO_BUILD_VERSION='YES'
            ;;

      	--env-filename )
			shift
            API_ENV_FILE_NAME="$1"
            ;;
    	--env-varname)
			shift
	        API_ENV_VARNAME="$1"
	        ;;
    	--env-production)
			shift
	        API_ENV_PRODUCTION="$1"
	        ;;
        -h | --help )
            usage
            ;;
        * )
            usage
            ;;
    esac

    shift
done





##构建开始时间
startTimeSeconds=`date +%s`
historyBackup
## 初始化用户配置
initUserXcconfig
if [[ $? -eq 0 ]]; then
	logit "【数据备份】上一次打包文件已备份到：$Package_Dir/History"	
fi

### Xcode版本
xcVersion=$(getXcodeVersion)
if [[ ! "$xcVersion" ]]; then
	errorExit "获取当前XcodeVersion失败"
fi
logit "【构建信息】Xcode版本：$xcVersion"


xcodeprojPath=$(checkXcodeprojExist)
if [[ ! "$xcodeprojPath" ]]; then
	errorExit "当前目录不存在Xcodeproj文件，请在工程目录下执行脚本$(basename $0)"
fi


## 获取构建target Id
targetId=$(getBuildTargetId "$xcodeprojPath")
if [[ ! "$targetId" ]]; then
	errorExit "获取构建Target Id失败"
fi
logit "【构建信息】Target Id：$targetId"

## 获取target名称
targetName=$(getTargetName "$xcodeprojPath" $targetId)
if [[ ! "$targetName" ]]; then
	errorExit "获取构建Target名字失败"
fi
logit "【构建信息】Target 名字：$targetName"


##获取构配置类型的ID （Release和Debug分别对应不同的ID）
configurationTypeIds=$(getConfigurationIds "$xcodeprojPath" "$targetId")
if [[ ! "$configurationTypeIds" ]]; then
	errorExit "获取配置模式(Release和Debug)Id列表失败"
fi
logit "【构建信息】配置模式(Release和Debug)Id列表：$configurationTypeIds"



## 获取当前构建的配置模式ID
configurationId=$(getConfigurationIdWithType "$xcodeprojPath" "$targetId" "$CONFIGRATION_TYPE")
if [[ ! "$configurationId" ]]; then
	errorExit "获取${CONFIGRATION_TYPE}配置模式Id失败"
fi
logit "【构建信息】配置模式：$CONFIGRATION_TYPE"
logit "【构建信息】配置模式Id：$configurationId"


## 获取Bundle Id
if [[ $NEW_BUNDLE_IDENTIFIER ]]; then
	## 重新指定Bundle Id
	projectBundleId=$NEW_BUNDLE_IDENTIFIER
else
	## 获取工程中的Bundle Id
	projectBundleId=$(getProjectBundleId "$xcodeprojPath" "$configurationId")
	if [[ ! "$projectBundleId" ]] ; then
		errorExit "获取项目的Bundle Id失败"
	fi
fi
logit "【构建信息】Bundle Id：$projectBundleId"
infoPlistFile=$(getInfoPlistFile "$xcodeprojPath" "$configurationId")
if [[ ! "$infoPlistFile" ]]; then
	errorExit "获取infoPlist文件失败"
fi
logit "【构建信息】InfoPlist 文件：$infoPlistFile"

## 设置git仓库版本数量
gitRepositoryVersionNumbers=$(getGitRepositoryVersionNumbers)
if [[ "$AUTO_BUILD_VERSION" == "YES" ]] && [[ "$gitRepositoryVersionNumbers" ]]; then
	setBuildVersion "$infoPlistFile" "$gitRepositoryVersionNumbers"
	if [[ $? -ne 0 ]]; then
		warning "设置构建版本号失败，跳过此设置"
	else
		logit "【构建信息】设置构建版本号：$gitRepositoryVersionNumbers"
	fi
fi

## 设置环境变量
apiEnvFile=$(findIPAEnvFile "$API_ENV_FILE_NAME")
if [[ "$API_ENV_PRODUCTION" ]]; then
	if [[ "$apiEnvFile" ]]; then
		logit "【构建信息】API环境配置文件：$apiEnvFile"
		if [[ "$API_ENV_VARNAME" ]] ; then
			setIPAEnvFile "$apiEnvFile" "$API_ENV_VARNAME" "$API_ENV_PRODUCTION"

			if [[ $? -ne 0 ]]; then
				warning "设置API环境变量失败，跳过此设置"
			else
				logit "【构建信息】设置API环境变量：$API_ENV_VARNAME = $API_ENV_PRODUCTION"
			fi
		fi
	fi

fi

## 设置手动签名
setManulCodeSigningRuby "$xcodeprojPath" "$targetId"


####下面这段逻辑是用PlistBuddy工具进行配置，但是PlistBuddy工具会导致工程文建格式发生变化，导致中文乱码。所以改成用xcodeproj来修改
# codeSigningStyle=$(getCodeSigningStyle "$xcodeprojPath" "$targetId")
# if [[ ! "$codeSigningStyle" ]]; then
	
# 	## 添加手动签名配置
# 	addManulCodeSigning "$xcodeprojPath" "$targetId"
# 	if [[ $? -ne 0 ]]; then
# 		errorExit "设置General手动签名失败"
# 	else
# 		logit "【签名信息】设置手动签名"
# 	fi
# else
# 	if [[ "$codeSigningStyle" != "Manual" ]]; then
# 		setManulCodeSigning "$xcodeprojPath" "$targetId"
# 		if [[ $? -eq 0 ]]; then
# 			logit "【签名信息】设置手动签名"
# 		fi
# 	fi
# fi

## 匹配授权文件
provisionFile=$(matchMobileProvisionFile "$CHANNEL" "$projectBundleId" "$PROVISION_DIR")
if [[ ! "$provisionFile" ]]; then
	errorExit "不存在Bundle Id 为 ${projectBundleId} 且分发渠道为${CHANNEL}的授权文件，请检查${PROVISION_DIR}目录是否存在对应授权文件"
fi
##导入授权文件
open "$provisionFile"
## 授权文件type对应的名字
channelName=$(getProfileTypeCNName $CHANNEL)
## 获取授权文件的有效天数
provisionFileExpirationDays=$(getProvisionfileExpirationDays "$provisionFile")
provisionFileName=$(getProvisionfileName "$provisionFile")
provisionFileTeamID=$(getProvisionfileTeamID "$provisionFile")
provisionFileUUID=$(getProvisionfileUUID "$provisionFile")
logit "【授权文件】匹配文件Bundle Id：${projectBundleId}"
logit "【授权文件】匹配文件路径：${provisionFile}"
logit "【授权文件】匹配文件名称：${provisionFileName}"
logit "【授权文件】匹配文件TeamID：${provisionFileTeamID}"
logit "【授权文件】匹配文件UUID：${provisionFileUUID}"
logit "【授权文件】匹配文件分发渠道：${CHANNEL}(${channelName})"
logit "【授权文件】匹配文件有效天数：${provisionFileExpirationDays}"



codeSignIdentity=$(getProvisionCodeSignIdentity "$provisionFile")

if [[ ! "$codeSignIdentity" ]]; then
	errorExit "获取授权文件签名失败! 授权文件:${provisionFile}"
fi
logit "【授权文件】匹配签名ID：$codeSignIdentity"


result=$(checkCodeSignIdentityValid "$codeSignIdentity")
if [[ ! "$result" ]]; then
	errorExit "签名ID:${codeSignIdentity}无效，请检查钥匙串是否导入对应的证书或脚本访问keychain权限不足，请使用-p参数指定密码 "
fi






### 进行构建配置信息覆盖，关闭BitCode、签名手动、配置签名等
xcconfigFile=$(initBuildXcconfig)
if [[ "$xcconfigFile" ]]; then
	logit "【签名设置】初始化XCconfig配置文件：$xcconfigFile"
fi


setXCconfigWithKeyValue "ENABLE_BITCODE" "$ENABLE_BITCODE"
setXCconfigWithKeyValue "DEBUG_INFORMATION_FORMAT" "$DEBUG_INFORMATION_FORMAT"
setXCconfigWithKeyValue "CODE_SIGN_STYLE" "$CODE_SIGN_STYLE"
setXCconfigWithKeyValue "PROVISIONING_PROFILE_SPECIFIER" "$provisionFileName" 
setXCconfigWithKeyValue "PROVISIONING_PROFILE" "$provisionFileUUID"
setXCconfigWithKeyValue "DEVELOPMENT_TEAM" "$provisionFileTeamID"
setXCconfigWithKeyValue "CODE_SIGN_IDENTITY" "$codeSignIdentity"
setXCconfigWithKeyValue "PRODUCT_BUNDLE_IDENTIFIER" "$projectBundleId"
## 如果是进行商店分发或则企业分发，那么构建标准arch（即armv7和arm64）
if [[ "$CHANNEL" == 'app-store' ]]|| [[ "$CHANNEL" == 'enterprise' ]] ; then
	setXCconfigWithKeyValue "ARCHS" "armv7 arm64"
else
	## 构建默认arch或者用户指定archs
	setXCconfigWithKeyValue "ARCHS" "$ARCHS"
fi



unlockKeychain
if [[ $? -eq 0 ]]; then
	logit "【钥匙串 】unlock-keychain";
else
	errorExit "unlock-keychain 失败, 请使用-p 参数或者在user.xcconfig配置文件中指定密码";
fi


## podfile 检查
podfile=$(checkPodfileExist)
if [[ "$podfile" ]]; then
	pod install
fi

## 开始归档。
## 这里使用a=$(...)这种形式会导致xocdebuild日志只能在函数archiveBuild执行完毕的时候输出；
## archivePath 在函数archiveBuild 是全局变量
archivePath=''
archiveBuild "$targetName" "$Tmp_Build_Xcconfig_File" 
logit "【归档信息】项目构建成功，文件路径：$archivePath"



# 开始导出IPA
exportPath=''
exportIPA  "$archivePath" "$provisionFile"
if [[ ! "$exportPath" ]]; then
	errorExit "IPA导出失败，请检查日志。"
fi
logit "【IPA 导出】IPA导出成功，文件路径：$exportPath"
if [[ ! "$ipaName" ]]; then
	ipaName=$targetName
fi


## 修复8.3 以下版本的xcent文件
xcentFile=$(repairXcentFile "$exportPath" "$archivePath")
if [[ "$xcentFile" ]]; then
	logit "【xcent 文件修复】拷贝archived-expanded-entitlements.xcent 到${xcentFile}"
fi

## 检查IPA
checkIPA "$exportPath"

##清理临时文件
rm -rf "$Tmp_Options_Plist_File"
rm -rf "$Tmp_Build_Xcconfig_File"
rm -rf "$archivePath"
rm -rf "$Package_Dir/Packaging.log"
rm -rf "$Package_Dir/ExportOptions.plist"
rm -rf "$Package_Dir/DistributionSummary.plist"




## IPA和日志重命名
logit "【IPA 信息】IPA和日志重命名"
exportDir=${exportPath%/*} 



ipaName=$(finalIPAName "$targetName" "$apiEnvFile" "$API_ENV_VARNAME" "$infoPlistFile" "$channelName")
mv "$exportPath" 	"${exportDir}/${ipaName}.ipa"
mv "$Tmp_Log_File" 	"${exportDir}/${ipaName}.txt"
logit "【IPA 信息】IPA路径:${exportDir}/${ipaName}.ipa"
logit "【IPA 信息】日志路径:${exportDir}/${ipaName}.txt"

##结束时间
endTimeSeconds=`date +%s`
logit "【构建时长】构建时长：$((${endTimeSeconds}-${startTimeSeconds})) 秒"


