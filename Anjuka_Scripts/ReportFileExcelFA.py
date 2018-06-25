import os
import subprocess
import re
from subprocess import call
import sys
import xlsxwriter

versionList = sys.argv[1].split()
moduleList = sys.argv[2].split()

#Creating xls work book
if (len(moduleList[0]) > 9):
	workbookName = 'consolidatedReport_' + moduleList[0][:9] + '.xlsx'
else:
	workbookName = 'consolidatedReport_' + moduleList[0] + '.xlsx'

workbook = xlsxwriter.Workbook(workbookName)
frontsheet = workbook.add_worksheet("Dashboard")
bold = workbook.add_format({'bold': 1})
frontsheet.write('A1', "ModuleName", bold)
frontsheet.write_string ('B1', "PASSED", bold)
frontsheet.write_string ('C1', "FAILED", bold)
frontsheet.write_string ('D1', "SKIPPED", bold)

fr = 1
fc = 0
#Creating dictionary to store result of each test script
testResult_Dict = dict()
for module in moduleList:
	res = dict()
	totalTestcaseList = []
	if (len(module) > 18):
	        moduleSheetName = module[:18]
        else:
        	moduleSheetName = module
        worksheet_module = workbook.add_worksheet(moduleSheetName)
	worksheet_module.write('A1', 'Testcase Name', bold)
        worksheet_module.write('B1', 'Testcase Result', bold)
	for version in versionList:
		listName = "listFile_" + module + "_" + version + ".txt"
		cmd = "ls -d1 " + module + "\/Report\/*" + version + "* >" + listName
		os.system (cmd)
		listFileFH = open (listName, "r")
		#Opening a work sheet for each module
		if (len(module) > 15) and (len(version) > 15):
			sheetName = module[:14] + "_" + version[:14]
		elif (len(module) > 18):
			sheetName = module[:18] + "_" + version
		elif (len(version) > 18):
			sheetName = module + "_" + version[:10]
		else:
			sheetName =  module + "_" + version
		worksheet = workbook.add_worksheet(sheetName)
		bold = workbook.add_format({'bold': 1})
		#Defining column headers
		worksheet.write('A1', 'ConfigFile', bold)
		worksheet.write('B1', 'Testcase Name', bold)
		worksheet.write('C1', 'Testcase Result', bold)
		worksheet.write('D1', 'Execution Time', bold)
		worksheet.write('F1', 'TestScript', bold)
		worksheet.write('G1', 'AverageExecutionTime', bold)
		worksheet.write('H1', 'Result', bold)

		row = 1
		col = 0
		testcaseList = []
		cfgList = []
		for directory in listFileFH:
			try:
				configFH = open (os.path.join(directory.strip("\r\n"), "report.txt"),"r")
				resultFH = open (os.path.join(directory.strip("\r\n"),"TestcaseStatusList.txt"), "r")
				execFH = open (os.path.join(directory.strip("\r\n"),"execTime.txt"), "r")
			except IOError:
				continue
			for line in configFH:
				if re.search ('Using config file: cfg/', line):
					cfgInfo = re.sub ("Using config file: cfg/", '',line)
					cfgList.append(str(cfgInfo.strip("\r\n")))
			for line1,line2 in zip(resultFH,execFH):
				line2 = re.sub ("testcase:.*duration:",'',line2.strip("\r\n"))
				line1 = line1.strip("\r\n")
                		line1 = line1.split(":")
                		testcaseName = line1[0].strip ("\t")
				testcaseList.append(testcaseName)
                		testResult = line1[1].strip ("\t")
				if testcaseName in testResult_Dict:
                                        testResult_Dict[testcaseName].append(testResult)
                                else:
	                               	testResult_Dict[testcaseName] = [testResult]

                                testcaseList.append(testcaseName)
	
				worksheet.write_string  (row, col, str(cfgInfo.strip("\r\n")))
				worksheet.write_string  (row, col + 1, testcaseName)
				worksheet.write_string  (row, col + 2, testResult)
				worksheet.write_number  (row, col + 3, int(line2))
				row = row + 1  

		testcaseUniqueList = set(testcaseList)
		maxRow = row
		row = 1
		col = 1
		#Calculating status of each scripts across testbeds.
		for testScript in testcaseUniqueList:
			if ('init' in testScript) or (testScript == "cleanup") or ('end' in testScript):
				continue
			if testScript not in res:
	                	res[testScript] = []
			worksheet.write_string	(row, 5, testScript)
			script = '"' + testScript + '"'
			formula = '=IFERROR(AVERAGEIFS(D1:D%d,B1:B%d,%s,C1:C%d,"<>SKIPPED"),0)' % (maxRow,maxRow,script,maxRow)
			worksheet.write_formula (row, 6, formula)
			if (len(testResult_Dict[testScript])) == (testResult_Dict[testScript].count("PASSED")):
				result = "PASSED"
				res[testScript].append(result)
			elif (len(testResult_Dict[testScript])) == (testResult_Dict[testScript].count("SKIPPED")):
                                result = "SKIPPED"
                                res[testScript].append(result)
			elif (len(testResult_Dict[testScript])) == ((testResult_Dict[testScript].count("SKIPPED")) + (testResult_Dict[testScript].count("PASSED"))):
                                result = "PASSED"
				res[testScript].append(result)
			else :
				result = "FAILED"
				res[testScript].append(result)
                        worksheet.write_string (row, 7, result)
			row = row + 1
		
		totalTestcases = row
		worksheet.write_string ('J2', "Total Average Execution Time", bold)
		formula = '=SUM(G1:G%d)' % totalTestcases
		worksheet.write_formula ('K2', formula)
		
		worksheet.write_string ('J3', "PASSED", bold)
                worksheet.write_formula ('K3', 'COUNTIF(H:H,"PASSED")')

		worksheet.write_string ('J4', "FAILED", bold)
                worksheet.write_formula ('K4', 'COUNTIF(H:H,"FAILED")')
		
		worksheet.write_string ('J5', "SKIPPED", bold)
                worksheet.write_formula ('K5', 'COUNTIF(H:H,"SKIPPED")')
		
		totalTestcaseList.extend(testcaseUniqueList)
		testResult_Dict.clear()
		listFileFH.close()
		os.remove(listName)
	row = 1	
	totalTestcaseList = set(totalTestcaseList)
	for testScript in totalTestcaseList:
		if ('init' in testScript) or (testScript == "cleanup") or ('end' in testScript):
                                continue
                worksheet_module.write_string  (row, 0, testScript)
                if (len(res[testScript])) == (res[testScript].count("PASSED")):
        	        result = "PASSED"
		elif (len(res[testScript])) == (res[testScript].count("SKIPPED")):
                        result = "SKIPPED"
                elif (len(res[testScript])) == ((res[testScript].count("SKIPPED")) + (res[testScript].count("PASSED"))):
                        result = "PASSED"
                else :
                	result = "FAILED"
                worksheet_module.write_string (row, 1, result)
                row = row + 1
	#Writing consolidated results to module sheets
	worksheet_module.write_string ('C2', "PASSED", bold)
        worksheet_module.write_formula ('D2', 'COUNTIF(B:B,"PASSED")')
        worksheet_module.write_string ('C3', "FAILED", bold)
        worksheet_module.write_formula ('D3', 'COUNTIF(B:B,"FAILED")')
        worksheet_module.write_string ('C4', "SKIPPED", bold)
        worksheet_module.write_formula ('D4', 'COUNTIF(B:B,"SKIPPED")')
	
	#Writing Dashboard information
	frontsheet.write_string (fr, fc, moduleSheetName)
        passFormula = "='%s'!D2" % moduleSheetName
        frontsheet.write_formula (fr, fc + 1, passFormula)
	failFormula = "='%s'!D3" % moduleSheetName
        frontsheet.write_formula (fr, fc + 2, failFormula)
	skipFormula = "='%s'!D4" % moduleSheetName
        frontsheet.write_formula (fr, fc + 3, skipFormula)
	fr = fr + 1

configFH.close()
resultFH.close()
execFH.close()
#outputFH.close()
workbook.close()

