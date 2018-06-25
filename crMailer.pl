#!/bin/perl
use strict;
use DBI;
use Data::Dumper;
use Time::Piece;
use DateTime;

# Global Variables
my $globals = {};
$globals->{dbHost}           = 'trackback';
$globals->{dbName}           = 'tracker'; 
$globals->{dbUser}           = 'enikiosk-RO';
$globals->{dbPassword}       = 'enikiosk-RO';
$globals->{updateProduction} = 0; # Set this to true only when you want to publish changes to the production database.  Can be set with --production option
$globals->{dbReference}      = undef;
$globals->{sendEmailTo}      = '';
$globals->{sendEmailCc}      = '';
$globals->{sendEmailFrom}    = 'CR Mailer <ragrajan@extremenetworks.com>';
$globals->{bgColor}    	     = '';
$globals->{emailSubject}     = 'Consolidated Bug Report';
$globals->{releaseName}      = '';
$globals->{releaseId}        = 0;
$globals->{feedbackCRcount}  = 0;
$globals->{verifyCRcount}    = 0;
$globals->{openCRcount}      = 0;
$globals->{feedbackBugs}     = ();
$globals->{verifyFixBugs}    = ();
$globals->{lastDayBugs}      = ();
$globals->{today}	     = localtime->strftime('%d/%b/%Y');
$globals->{"Gopla Ramkumar"} 	= "#D4FFD4";
$globals->{"Raj Velusamy"} 	= "#EFF2F9";
$globals->{"Shankar Palanivel"} = "#F4B084";
$globals->{"Raguraman Rajan"} 	= "#92D050";
$globals->{"Uma Parthasarathy"} = "#F2d050";


sub connectToDatabase()
{
  $globals->{dbReference} = DBI->connect("dbi:mysql:$globals->{dbName}:$globals->{dbHost}:3306", $globals->{dbUser}, $globals->{dbPassword});
  if (!defined $globals->{dbReference}) {
    logError("Unable to connect to database: $DBI::errstr");
    return;
  }
}

sub getReleaseId(){
  my $sqlStatement = qq(SELECT releaseId FROM releases WHERE productId=132 AND releaseName=?);
  my $queryRef     = $globals->{dbReference}->prepare($sqlStatement);
  my $result       = $queryRef->execute($globals->{releaseName});
  if (!$result) {
    logError(qq(Error while executing SQL statement.  Error: "$queryRef->{errstr}"));
  }
  
  # Get the releaseId
  my $currentRow = $queryRef->fetchrow_hashref();
  die "$globals->{releaseName} is not a valid EXOS release" unless defined $currentRow;
  $globals->{releaseId} = $currentRow->{releaseId};
}

sub runFeedbackNeededQuery()
{
  my $sqlStatement = qq(
SELECT bugDescriptions.bugNumber, bugDescriptions.severity, bugDescriptions.priority, bugDescriptions.globalState, bugDescriptions.creator,ldapManagerName,
       bugDescriptions.assignedTo, DATE_FORMAT(MAX(bugShortHistory.transitionDate),'%e/%b/%Y') AS feedbackNeededDate,
       DATE(NOW()) as today, DATEDIFF(NOW(), MAX(bugShortHistory.transitionDate)) AS numDays,
bugRelationships.bugNumber as relatedCRID, bugDescriptions1.globalState as relatedCRGlobalState, releaseTracking1.releaseState as relatedCRState
FROM bugDescriptions
LEFT JOIN bugShortHistory USING(bugNumber)
LEFT JOIN releaseTracking USING(bugNumber)
LEFT JOIN users ON bugDescriptions.creator=users.username
LEFT JOIN bugRelationships ON bugDescriptions.bugNumber=bugRelationships.relatedTo
LEFT join bugDescriptions bugDescriptions1 on bugDescriptions1.bugNumber=bugRelationships.bugNumber
LEFT join releaseTracking releaseTracking1 on releaseTracking1.bugNumber=bugRelationships.bugNumber AND releaseTracking1.targetReleaseId='$globals->{releaseId}'
WHERE (bugDescriptions.globalState='Feedback Needed' || bugDescriptions.globalState='Verify Duplicate' || bugDescriptions.globalState='Verify No Change')
AND (bugDescriptions.releaseDetected='$globals->{releaseName}' || releaseTracking.targetReleaseId=?)
AND (ldapManagerName like '%Velusamy%'      ||
     ldapManagerName like '%Ramkumar%'      ||
     ldapManagerName like '%Parthasarathy%' ||
     ldapManagerName like '%Palanivel%'     ||
     ldapManagerName like '%Raguraman%')
GROUP BY bugDescriptions.bugNumber
ORDER BY bugDescriptions.globalState ASC, ldapManagerName ASC, numDays DESC;
                      );
  my $queryRef     = $globals->{dbReference}->prepare($sqlStatement);
  my $result       = $queryRef->execute($globals->{releaseId});
  if (!$result) {
    logError(qq(Error while executing SQL statement.  Error: "$queryRef->{errstr}"));
  };
  my @bugList = ();
  while( my $currentRow = $queryRef->fetchrow_hashref()) {
    push(@{$globals->{feedbackBugs}}, $currentRow);
    ++$globals->{feedbackCRcount};
  }
}

sub runVerifyFixQuery()
{
  my $sqlStatement = qq(
SELECT bugNumber, severity, priority, releaseState, creator, relassignedTo,  DATE_FORMAT(MAX(transitionDate),'%e/%b/%Y') AS verifyFixDate, 
       DATE(NOW()) as today, DATEDIFF(NOW(), MAX(transitionDate)) AS numDays, 
       creatorManager.ldapManagerName as creatorManager, verifierManager.ldapManagerName as ldapManagerName
       FROM      
         (SELECT bugNumber, targetReleaseId, transitionDate, assignedTo as relassignedTo, releaseState
               FROM bugShortHistory 
               LEFT JOIN releaseTracking USING(bugNumber) 
               WHERE targetReleaseId=? 
               AND (releaseState='Verify Fix' || releaseState='Verify Task Complete')) AS tmpTbl1
LEFT JOIN bugDescriptions USING(bugNumber)       
LEFT JOIN users as creatorManager ON bugDescriptions.creator=creatorManager.username 
LEFT JOIN users as verifierManager ON relassignedTo=verifierManager.username 
WHERE (releaseState='Verify Fix' || releaseState='Verify Task Complete')
AND (verifierManager.ldapManagerName like '%Velusamy%'      || 
     verifierManager.ldapManagerName like '%Ramkumar%'      || 
     verifierManager.ldapManagerName like '%Parthasarathy%' || 
     verifierManager.ldapManagerName like '%Palanivel%'     || 
     verifierManager.ldapManagerName like '%Raguraman%')     
GROUP BY bugNumber
ORDER BY verifierManager.managerName  ASC, numdays DESC;
                      );
  my $queryRef     = $globals->{dbReference}->prepare($sqlStatement);
  my $result       = $queryRef->execute($globals->{releaseId});
  if (!$result) {
    logError(qq(Error while executing SQL statement.  Error: "$queryRef->{errstr}"));
  };
  my @bugList = ();
  while( my $currentRow = $queryRef->fetchrow_hashref()) {
    push(@{$globals->{verifyFixBugs}}, $currentRow);
    ++$globals->{verifyCRcount};
  }
}

sub runlastDayQuery()
{
  my $lastDate = DateTime->today;
  $lastDate->subtract( days => 1 );
  my $yesterday = $lastDate->ymd('-');
  my $sqlStatement = qq(
SELECT
        bugDescriptions.bugNumber as bugNumber, 
        bugDescriptions.severity as severity, 
        bugDescriptions.priority as priority, 
        bugDescriptions.gaBlocking as gaBlocking,
        GROUP_CONCAT(DISTINCT bugTestBlocking.testBlocking SEPARATOR ', ') AS testBlocking,
        bugDescriptions.component as component, 
        bugDescriptions.subComponent as subComponent, 
        udf1.features as udfFeature,
	udf2.passedPreviously as passedPreviously,
	udf3.lastPassBuild as lastPassBuild,
        metadata.value as metaData,
        bugDescriptions.summary as summary,
        bugDescriptions.globalState as globalState, 
        CAST(bugDescriptions.creationTimeStamp AS DATE) as creationTimeStamp,
        bugDescriptions.releaseDetected as releaseDetected, 
        bugDescriptions.creator as creator,
        ldapManagerName
FROM bugDescriptions
LEFT JOIN bugTestBlocking          ON bugTestBlocking.bugNumber=bugDescriptions.bugNumber 
LEFT JOIN udfFeatures         udf1 ON udf1.bugNumber=bugDescriptions.bugNumber 
LEFT JOIN udfPassedPreviously udf2 ON udf2.bugNumber=bugDescriptions.bugNumber 
LEFT JOIN udfLastPassBuild    udf3 ON udf3.bugNumber=bugDescriptions.bugNumber 
LEFT JOIN users ON bugDescriptions.creator=users.username
LEFT JOIN metadata ON metadata.typeId=bugDescriptions.bugNumber 
LEFT JOIN metadataKeyMap ON metadataKeyMap.metadataKeyMapId=metadata.metadataKeyMapId 
WHERE bugDescriptions.releaseDetected=?
AND bugDescriptions.creationTimeStamp like '%$yesterday%'
AND (ldapManagerName like '%Velusamy%'      || 
     ldapManagerName like '%Ramkumar%'      || 
     ldapManagerName like '%Parthasarathy%' || 
     ldapManagerName like '%Palanivel%'     || 
     ldapManagerName like '%Raguraman%') 
GROUP BY bugDescriptions.bugNumber 
ORDER BY bugDescriptions.severity ASC;
                      );
  my $queryRef     = $globals->{dbReference}->prepare($sqlStatement);
  my $result       = $queryRef->execute($globals->{releaseName});
  if (!$result) {
    logError(qq(Error while executing SQL statement.  Error: "$queryRef->{errstr}"));
  };
  my @bugList = ();
  while( my $currentRow = $queryRef->fetchrow_hashref()) {
    push(@{$globals->{lastDayBugs}}, $currentRow);
    ++$globals->{openCRcount};
  }
}

sub generateAndSendEmail()
{

  # Create the html output that will go into the e-mail  
  my $strMsg = qq(Hi all,<br><br>Please find below the $globals->{releaseName} CR Backlog details as on $globals->{today}<br><br>);

 if ($globals->{feedbackCRcount} == 0) {
  $strMsg .=  qq(<br><font size=4 color=green>Zero Feedback/Verify Duplicate/No-Change CRs... !!! </font><br>);
 } else {
  my @feedbackNeededBugs = (@{$globals->{feedbackBugs}});
  $strMsg .= qq(<font size=4 color=red>Feedback/Duplicate/No-Change CRs - $globals->{feedbackCRcount} </font><br>
  <TABLE BORDER=1>
  <TR bgcolor=#A0B0E0>
    <TH>bugNumber</TH>
    <TH>severity</TH>
    <TH>priority</TH>
    <TH>globalState</TH>
    <TH>creator</TH>
    <TH>ldapManagerName</TH>
    <TH>assignedTo</TH>
    <TH>transitionDate</TH>
    <TH>numDays pending</TH>
    <TH>relatedCR</TH>
    <TH>relatedCrGlobalState</TH>
    <TH>relatedCrReleaseState</TH>
  </TR>  
	        );  

  foreach my $currentBug (@feedbackNeededBugs) {
    $strMsg .= qq(
    <TR bgcolor=$globals->{$currentBug->{ldapManagerName}}>
    <TD><a href=https://tracker.extremenetworks.com/cgi/trackerReport.pl?bugNumber=$currentBug->{bugNumber}>$currentBug->{bugNumber}</a></TD>
    <TD>$currentBug->{severity}</TD>
    <TD>$currentBug->{priority}</TD>
    <TD>$currentBug->{globalState}</TD>
    <TD>$currentBug->{creator}</TD>
    <TD>$currentBug->{ldapManagerName}</TD>
    <TD>$currentBug->{assignedTo}</TD>
    <TD>$currentBug->{feedbackNeededDate}</TD>
    <TD align=center>$currentBug->{numDays}</TD>
    <TD><a href=https://tracker.extremenetworks.com/cgi/trackerReport.pl?bugNumber=$currentBug->{relatedCRID}>$currentBug->{relatedCRID}</a></TD>
    <TD>$currentBug->{relatedCRGlobalState}</TD>
    <TD>$currentBug->{relatedCRState}</TD>
    </TR>
		);
  }
  $strMsg .=  qq(</TABLE><BR>);
 }
 
 # Print the verify fix table
 if ($globals->{verifyCRcount} == 0) {
  $strMsg .=  qq(<br><font size=4 color=green>Zero Verify-FIX CRs... !!! </font><br>);
 } else {
  my @verifyBugs         = (@{$globals->{verifyFixBugs}});
  $strMsg .=  qq(<br><font size=4 color=red>Verify Fix CRs - $globals->{verifyCRcount} </font><br><TABLE BORDER=1>
  <TR bgcolor=#A0B0E0>
    <TH>bugNumber</TH>
    <TH>severity</TH>
    <TH>priority</TH>
    <TH>releaseState</TH>
    <TH>creator</TH>
    <TH>relassignedTo</TH>
    <TH>ldapManagerName</TH>
    <TH>verifyFixDate</TH>
    <TH>numDays pending verification</TH>
  </TR>  
);
  foreach my $currentBug (@verifyBugs) {

    $strMsg .= qq(
    <TR bgcolor=$globals->{$currentBug->{ldapManagerName}}>
    <TD><a href=https://tracker.extremenetworks.com/cgi/trackerReport.pl?bugNumber=$currentBug->{bugNumber}>$currentBug->{bugNumber}</a></TD>
    <TD>$currentBug->{severity}</TD>
    <TD>$currentBug->{priority}</TD>
    <TD>$currentBug->{releaseState}</TD>
    <TD>$currentBug->{creator}</TD>
    <TD>$currentBug->{relassignedTo}</TD>
    <TD>$currentBug->{ldapManagerName}</TD>
    <TD>$currentBug->{verifyFixDate}</TD>
    <TD align=center>$currentBug->{numDays}</TD>
  </TR>);  
  }
  $strMsg .= qq(</TABLE><br>);
 }

 # Print the yesterday created Bugs
 if ($globals->{openCRcount} == 0) {
	  $strMsg .=  qq(<br><font size=4 color=green>Zero CRs Opened yesterday... !!! </font><br>);
	 } else {
	  my @lastBugs           = (@{$globals->{lastDayBugs}}); 
	  $strMsg .=  qq(<br><font size=4 color=red>CRs Opened yesterday - $globals->{openCRcount} </font><br><TABLE BORDER=1>
	  <TR bgcolor=#A0B0E0>
	    <TH>bugNumber</TH>
	    <TH>severity</TH>
	    <TH>priority</TH>
	    <TH>gaBlocking</TH>
	    <TH>testBlocking</TH>
	    <TH>component</TH>
	    <TH>subComponent</TH>
	    <TH>passedPreviously</TH>
	    <TH>lastPassBuild</TH>
	    <TH>metaData</TH>
	    <TH>globalState</TH>
	    <TH>creator</TH>
	    <TH>ldapManagerName</TH>
	    <TH>summary</TH>
	  </TR> 
	);

	  foreach my $currentBug (@lastBugs) {

	    $strMsg .= qq(
	    <TR bgcolor=$globals->{$currentBug->{ldapManagerName}}>
	    <TD><a href=https://tracker.extremenetworks.com/cgi/trackerReport.pl?bugNumber=$currentBug->{bugNumber}>$currentBug->{bugNumber}</a></TD>
	    <TD>$currentBug->{severity}</TD>
	    <TD>$currentBug->{priority}</TD>
	    <TD>$currentBug->{gaBlocking}</TD>
	    <TD>$currentBug->{testBlocking}</TD>
	    <TD>$currentBug->{component}</TD>
	    <TD>$currentBug->{subComponent}</TD>
	    <TD>$currentBug->{passedPreviously}</TD>
	    <TD>$currentBug->{lastPassBuild}</TD>
	    <TD>$currentBug->{metaData}</TD>
	    <TD>$currentBug->{globalState}</TD>
	    <TD>$currentBug->{creator}</TD>
	    <TD>$currentBug->{ldapManagerName}</TD>
	    <TD>$currentBug->{summary}</TD>
	  </TR>); 
	 }
	  $strMsg .= qq(</TABLE><br>);
	}
	  $strMsg .= qq(<br>Thanks,<br>Raguraman\n);
	  # Close the html file
	  $strMsg .= qq(</HTML>\n);

	  # Send the e-mail
	  open(MAIL,"|/usr/sbin/sendmail -t");
	    print MAIL "To: $globals->{sendEmailTo}\n";
            print MAIL "Cc: $globals->{sendEmailCc}\n";
	    print MAIL "From: $globals->{sendEmailFrom}\n";
	    print MAIL "Subject: $globals->{emailSubject} - $globals->{releaseName} - $globals->{today}\n";

    ## Mail Body
    print MAIL "Content-Type: text/html; charset=ISO-8859-1\n\n";
    print MAIL $strMsg;
    close(MAIL);
  
  # Remove the temporary file
  #kill $tmpFile;
}

sub logError()
{
  my $strError = shift();
  print($strError);
  exit 1;
}

sub main()
{
  $globals->{releaseName} = $ARGV[0];
  $globals->{sendEmailTo} = $ARGV[1];
  $globals->{sendEmailCc} = $ARGV[2];
  connectToDatabase();
  getReleaseId();
  runFeedbackNeededQuery();
  runVerifyFixQuery();
  runlastDayQuery();
  generateAndSendEmail();
}

main();
