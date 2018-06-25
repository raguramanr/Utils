import sys
import os
import subprocess
import re
import argparse
import filecmp

parser = argparse.ArgumentParser()
parser.add_argument ("cfg", help="Specify cfg name", type=str)
parser.add_argument ("-fileList", help="Specify list of files", nargs="?")
args = parser.parse_args()
cfgName = args.cfg

outputFH = open("unconfigCheckReport.txt", "w")

cmd = "ls -d1 " + "*tcl >fileList.txt" 
os.system(cmd)
fileList = open ("fileList.txt", "r")
if args.fileList:
	fileList = args.fileList.split(" ")

for testScript in fileList:
	
	#Fetching DUT configuration before script execution
	command = ['./main.tcl', 'mode', 'dev', 'module', 'ACL_network_zones', 'cfg', 'cfg/'+cfgName, 'tcList', '\"initialConfig\"']
	process = subprocess.Popen(command, cwd="../../main")
	process.wait()
	#Executing Script
	command = ['./main.tcl', 'mode', 'dev', 'module', 'ACL_network_zones', 'cfg', 'cfg/'+cfgName, 'tcList', '\"'+ testScript +'\"']
	process = subprocess.Popen(command, cwd="../../main")
	process.wait()
	#Fetching DUT configuration after script execution
	command = ['./main.tcl', 'mode', 'dev', 'module', 'ACL_network_zones', 'cfg', 'cfg/'+cfgName, 'tcList', '\"finalConfig\"']
        process = subprocess.Popen(command, cwd="../../main")
        process.wait()

	print "\ncomparing configurations for %s" %testScript
	outputFH.write("\n\n#######################################################################")
	outputFH.write("\ncomparing configurations for %s" %testScript)
	outputFH.write("\n#########################################################################")
	if not filecmp.cmp("initialConfig.txt", "finalConfig.txt", shallow=False):
		print "There is a confiuration mismatch before and after executing test script:%s" %testScript
		outputFH.write("\nThere is a confiuration mismatch before and after executing test script:%s" %testScript)
		with open("initialConfig.txt",'r') as f:
			d=set(f.readlines())
		with open("finalConfig.txt",'r') as f:
			e=set(f.readlines())
		for line in list(d-e):
			print "Config mismatch between DUT1 and DUT2"
			print line
		for line in list(e-d):
			print "Config mismatch between DUT2 and DUT1"
        		print line
	else:
		print "No unconfiguration identified after executing test script:%s" %testScript
		outputFH.write("\nNo configuration mismatch identified after executing test script:%s" %testScript)

outputFH.close()


