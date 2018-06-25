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
$globals->{sendEmailTo}     = 'sasrinivasan@ExtremeNetworks.com';
$globals->{sendEmailFrom}    = 'Extreme Fabric CRs <ragrajan@extremenetworks.com>';
$globals->{bgColor}    	     = '';
$globals->{emailSubject}     = 'Extreme Fabric CRs';
$globals->{releaseName}      = 'EXOS 22.4.1';
$globals->{releaseId}        = 0;
$globals->{feedbackCRcount}  = 0;
$globals->{verifyCRcount}    = 0;
$globals->{openCRcount}      = 0;
$globals->{feedbackBugs}     = ();
$globals->{verifyFixBugs}    = ();
$globals->{lastDayBugs}      = ();
$globals->{today}	     = localtime->strftime('%d/%b/%Y');


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

sub runlastDayQuery() {
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
WHERE bugDescriptions.globalState='Assigned'
AND bugDescriptions.creationTimeStamp like '%$yesterday%'
AND bugDescriptions.component='ExtremeFabric'
GROUP BY bugDescriptions.bugNumber 
ORDER BY bugDescriptions.severity ASC;
                      );
  my $queryRef     = $globals->{dbReference}->prepare($sqlStatement);
  my $result       = $queryRef->execute();
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
  my $strMsg = qq(Hi all,<br><br>Please find below the CR details as on $globals->{today}<br><br>);

 # Print the yesterday created Bugs
 if ($globals->{openCRcount} == 0) {
  $strMsg .=  qq(<br><font size=4 color=red>Zero CRs Opened yesterday... !!! </font><br>);
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
    <TR>
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
  $strMsg .= qq(<br>Thanks,<br>Raguraman\n);
}
  # Close the html file
  $strMsg .= qq(</HTML>\n);

  # Send the e-mail
  open(MAIL,"|/usr/sbin/sendmail -t");
    print MAIL "To: $globals->{sendEmailTo}\n";
    print MAIL "From: $globals->{sendEmailFrom}\n";
    print MAIL "Subject: $globals->{emailSubject} - $globals->{today}\n";

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
  connectToDatabase();
  getReleaseId();
  runlastDayQuery();
  generateAndSendEmail();
}

main();
