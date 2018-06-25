import sys
import os
import subprocess
import re
import argparse

parser = argparse.ArgumentParser()
parser.add_argument ("module", help="Specify module name", nargs="?", default=os.getcwd())
parser.add_argument ("-fileList", help="Specify list of files", nargs="?")
args = parser.parse_args()
moduleName = args.module

cmd = "ls -d1 " + moduleName + "/*tcl >fileList.txt" 
os.system(cmd)
fileList = open ("fileList.txt", "r")
if args.fileList:
	fileList = args.fileList.split(" ")
outputFH = open("reviewCheckReport.txt", "w")
trafficProcs = {"SendIpFrame", "SendFrame", "SendIgmpFrame", "SendArpFrame", "SendFrameFromMultiplePorts"}
for fileName in fileList:
	fileName = fileName.replace("\n", "")
	CommentedList = []
	LenghierLinesList = []
	SleepLineList = []
	varaibleList = []
	globalVariableLine = []
	dupGlobalList = []
	sleepTime = 0
	i = 1
	outputFH.write("\n################################################################################")
	outputFH.write("\n\t\tParsing File:" + fileName)
	outputFH.write("\n################################################################################")
	print "\033[0;32m" +"\n################################################################################" + "\033[;0m"
	print "\033[0;32m" + "\t\tParsing File:" + fileName + "\033[;0m"
	print "\033[0;32m" +"################################################################################" + "\033[;0m"
	fileContent = open (fileName, "r")
	for line in fileContent:
		if "pause" in line:
			outputFH.write("\nScript contains pause:" + line)
			print ("\033[;31m" + "Script contains pause:" + line + "\033[;0m")
		if "exit" in line:
			outputFH.write("\nScript contains exit" + line)
			print ("\033[;31m" + "Script contains exit" + line + "\033[;0m")
		if re.search ('#(\w+)', line):
			CommentedList.append(str(i) + ":" + line)
		if len(line) > 81:
			LenghierLinesList.append(str(i) + ":" + line) 
		if "exSleep" in line:
			SleepLineList.append(str(i) + ":" + line)
			sleepLine = line.split()
			sleepTime = sleepTime + int(sleepLine[1].replace(";",""))
		if re.search('set\s+',line):
			variableLine = line.split()
			if "set" in variableLine[0]:
				varaibleList.append(variableLine[1].replace(";",""))
				if "testNo" in variableLine[1]:
					variableLine = variableLine
					testNo = variableLine[2].replace(";","")
					testNo = variableLine[2].replace("\"","")
		if re.search('global\s+',line):
			globalVariableLine.append(line.replace(";",""))
		i = i + 1
	outputFH.write("\nCommented Lines in the script:")			
	outputFH.write("\n------------------------------\n")			
	print ("\033[;1m" + "Commented Lines in the script:" + "\033[;0m")
	for line in CommentedList:
		outputFH.write("\n" + line)
		print line
	outputFH.write("\nLines which exceeds 80 characters in the script:")
	outputFH.write("\n------------------------------------------------\n")
	print ("\033[;1m" + "Lines which exceeds 80 characters in the script:" + "\033[;0m")
	for line in LenghierLinesList:
		outputFH.write("\n" + line)
		print line
	outputFH.write("\nTotal sleep time used in the script: %d" % sleepTime)
	print ("\033[;1m" + "Total sleep time used in the script: %d" % sleepTime + "\033[;0m")
	outputFH.write("\n\nexSleep lines used in the script:")
	outputFH.write("\n--------------------------------\n")
	print ("\033[;1m" + "exSleep lines used in the script:" + "\033[;0m")
	for line in SleepLineList:
		outputFH.write("\n" + line)
		print line
	fileContent.close()
	fileContent = open (fileName, "r").read()
	#Checking for unused variables
	for variable in varaibleList:
		if fileContent.count(variable) < 2:
			if "fd_res" not in variable:
				outputFH.write("\nUnused variable: " + variable)
				print "\033[;1m" + "Unused variable: " + "\033[;0m" + variable
	#Checking for report_start_test and report_end_test count
	if fileContent.count("report_start_test") != fileContent.count("report_end_test"):
		outputFH.write("\nreport_start_test count and report_end_test doesn't match")
		print ("\033[;31m" + "report_start_test count and report_end_test doesn't match" + "\033[;0m")
	#Checking for duplication in global variable declaration
	for globalVariable in globalVariableLine:
		fileContent = fileContent.replace(";","")
		if fileContent.count(globalVariable) > 1:
			dupGlobalList.append(globalVariable)
	dupGlobalList = list(set(dupGlobalList))
	for variable in dupGlobalList:
		outputFH.write("\nDuplication found in global variable declaration: " + variable)
		print ("\033[;1m" + "Duplication found in global variable declaration: " + variable)
		
	#Checking for testSkipped in scripts except init file
	if "init" not in fileName and "testSkipped" in fileContent:
		outputFH.write("\ntestSkipped used in the script")
		print ("\033[;31m" + "StestSkipped used in the script" + "\033[;0m")
	#Checking for cleanup procs
	if any(txproc in fileContent for txproc in trafficProcs):
		if "StopPortsTransmit" not in fileContent or "ClearPortsStats" not in fileContent:
			outputFH.write("\nScript doesn't have StopPortsTransmit/ClearPortsStats in the cleanup")
                        print ("\033[;31m" + "Script doesn't have StopPortsTransmit/ClearPortsStats in the cleanup" + "\033[;0m")			
	if "AddIPaddress" in fileContent and "DeleteIpaddres" not in fileContent:
		outputFH.write("\nScript doesn't have DeleteIpaddres in the cleanup")
		print ("\033[;31m" + "Script doesn't have DeleteIpaddres in the cleanup" + "\033[;0m")
	if "EnableIpaddress" in fileContent and "DisableIpaddress" not in fileContent:
		outputFH.write("\nScript doesn't have DisableIpaddress in the cleanup")
		print ("\033[;31m" + "Script doesn't have DisableIpaddress in the cleanup" + "\033[;0m")
	if "setupMLDServer" in fileContent and "cleanupMLD" not in fileContent:
		outputFH.write("\nScript doesn't have cleanupMLD in the cleanup")
		print ("\033[;31m" + "Script doesn't have cleanupMLD in the cleanup" + "\033[;0m")
	if "setupIgmpServer" in fileContent and "cleanupIgmp" not in fileContent:
		outputFH.write("\nScript doesn't have cleanupIgmp in the cleanup")
		print ("\033[;31m" + "Script doesn't have cleanupIgmp in the cleanup" + "\033[;0m")
	
	with open(fileName, 'r+') as f:
                lines = f.readlines()
		for i in range (0, len(lines)):
			if "proc" in lines[i]:
				testName = lines[i].split()
				testName = testName[1]
				break
                for i in range (0, len(lines)):
			#Checking for title format:
			if "set title" in lines[i]:
				title = lines[i].split()
				if "testNo" not in title[3] or title[2].lower().replace("\"", "") not in moduleName.lower():
					outputFH.write("\n" + "Title is not in Module Name <> $testNo format: " + lines[i])
					print ("\033[;31m" + "Title is not in Module Name <> $testNo format: " + lines[i] + "\033[;0m")
			#Checking for puts usage:
			if "puts" in lines[i]:
				outputFH.write("\n" + str(i + 1) + ": Use result_debug instead of puts")
		        	print ("\033[;1m" + str(i + 1) + ": Use result_debug instead of puts" + "\033[;0m")
			#Checking for exSleep after traffic transmission:
                        if any(txproc in lines[i] for txproc in trafficProcs):
                                for j in range(i, i + 6):
                                        if "exSleep" in lines[j]:
						sleepTime = lines[j].split()
						sleepTime = int(sleepTime[1].replace(";",""))
						if sleepTime > 10:
							outputFH.write("\n" + str(j) + ": Sleep exceeds 10 after traffic transmission")
	                                                print ("\033[;31m" + str(j) + ": Sleep exceeds 10 after traffic transmission" + "\033[;0m")
                                                break
			#Checking for explantion before exSleep
			if "exSleep" in lines[i]:
				if "result_debug" not in lines[i - 1] and "result_debug" not in lines[i - 2]:
					outputFH.write("\n" + str(i + 1) + ": Please give reason for exSleep in result_debug")
					print ("\033[;1m" + str(i + 1) + ": Please give reason for exSleep in result_debug" + "\033[;0m")
			#Checking for -time parameter in CheckKeyValue
			if "CheckKeyValue" in lines[i]:
				if "-time" not in lines[i] and "-time" not in lines[i + 1] and "-time" not in lines[i + 2]:
					outputFH.write("\n" + str(i + 1) + ": Please give -time parameter in CheckKeyValue")
                                        print ("\033[;1m" + str(i + 1) + ": Please give -time parameter in CheckKeyValue" + "\033[;0m")
			#Checking for exSleep before CheckKeyValue
			if "CheckKeyValue" in lines[i]:
				for j in range(i, i - 10, -1):
					if "exSleep" in lines[j]:
						outputFH.write("\n" + str(i + 1) + ": Please remove exSleep before CheckKeyValue")
						print ("\033[;1m" + str(i + 1) + ": Please remove exSleep before CheckKeyValue" + "\033[;0m")
						break
	if str(testName) != str(testNo):
		outputFH.write("\nError: TestName and TestNo is not same")
		print ("\033[;31m" + "TestName and TestNo is not same" + "\033[;0m")
						
outputFH.close()
os.system("rm -rf fileList.txt")




