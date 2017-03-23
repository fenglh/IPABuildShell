#!/usr/bin/ruby

#encoding: utf-8


require 'xcodeproj'

$projectPath = ARGV[0]
$provisionProfileUuid = ARGV[1]
$provisionProfileName = ARGV[2]
$codeSignIdentify = ARGV[3]
$developmentTeam = ARGV[4]

project = Xcodeproj::Project.open($projectPath)

def setProvisioningStyle(project)
	targetUuid=project.root_object.targets[0].uuid
	##判断字典是否存在ProvisioningStyle
	haskey=project.root_object.attributes["TargetAttributes"][targetUuid].include?("ProvisioningStyle")
	if haskey
		project.root_object.attributes["TargetAttributes"][targetUuid]["ProvisioningStyle"]="Manual"
		puts "ProvisioningStyle设置为Manual"
		provisioningStyle=project.root_object.attributes["TargetAttributes"][targetUuid]["ProvisioningStyle"]
		puts "#{targetUuid}当前ProvisioningStyle：#{provisioningStyle}"
	else
		puts "key:ProvisioningStyle 不存在"
	end

	
end


def setSigning(project)
	project.targets.each do |target|
  		target.build_configurations.each do |config|
	    	config.build_settings['PROVISIONING_PROFILE[sdk=iphoneos*]'] = $provisionProfileUuid
	    	config.build_settings['PROVISIONING_PROFILE'] = $provisionProfileUuid

	    	config.build_settings['PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]'] = $provisionProfileName
	    	config.build_settings['PROVISIONING_PROFILE_SPECIFIER'] = $provisionProfileName

	    	config.build_settings['CODE_SIGN_IDENTITY[sdk=iphoneos*]'] = $codeSignIdentify
	    	config.build_settings['CODE_SIGN_IDENTITY'] = $codeSignIdentify

			config.build_settings['DEVELOPMENT_TEAM'] = $developmentTeam  
	    
  		end
	end
	
end

###例如:
##ruby /Users/itx/Desktop/脚本打包/xcocdeModify.rb ./SFATest.xcodeproj e4ee21f0-2e88-4c67-af81-fc0a67755266 dev_NK94TM64KF.cn.com.bluemoon.sfa_101_1107 "iPhone Developer: Li Chao (BTTHBUB23E)"  NK94TM64KF
##ruby /Users/itx/Desktop/脚本打包/xcocdeModify.rb ./SFATest.xcodeproj 866d5a17-5c1d-4373-b4bf-88af22bfe97b dis_NK94TM64KF.cn.com.bluemoon.sfa_20181109_过期 "iPhone Distribution: Blue Moon ( China ) Co., Ltd."  NK94TM64KF


setProvisioningStyle(project)
setSigning(project)


project.save

