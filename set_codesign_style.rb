#! /usr/bin/ruby
# encoding: utf-8


require 'xcodeproj'




projectPath = ARGV[0]
targetId =  ARGV[1]
project = Xcodeproj::Project.open(projectPath)
project.root_object.attributes["TargetAttributes"][targetId]["ProvisioningStyle"]="Manual"
project.save

