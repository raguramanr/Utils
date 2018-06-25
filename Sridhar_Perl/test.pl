#!/bin/perl
use POSIX qw(strftime);
use DBI;
use Data::Dumper;
use Time::Piece;
use Time::Seconds;

# Global Variables
my $globals = {};
$globals->{dbHost}           = 'trackback';
$globals->{dbName}           = 'tracker'; 
$globals->{dbUser}           = 'CQG_SQA-RO';
$globals->{dbPassword}       = 'CQG_SQA-RO';
$globals->{updateProduction} = 0; # Set this to true only when you want to publish changes to the production database.  Can be set with --production option
$globals->{dbReference}      = undef;
$globals->{sendEmailTo}      = 'srbalakrishnan@extremenetworks.com';
$globals->{sendEmailFrom}    = 'RBC FA <srbalakrishnan@extremenetworks.com>';
$globals->{intbgColor}       = '';
$globals->{extbgColor}       = '';
$globals->{emailSubject}     = 'FIT & SVT CQG Report';
$globals->{pendingCQG}       = ();
$globals->{assignedCount}    = ();
$globals->{today}          = localtime->strftime('%d/%b/%Y');
$globals->{cqgCRcount}      = 0;
$globals->{intSLA}          = 0;
$globals->{extSLA}          = 0;
$globals->{intSLAdate}      = 0;
$globals->{extSLAdate}      = 0;
$globals->{FIT_Owner}       = '';
$globals->{SVT_Owner}       = '';

sub connectToDatabase()
{
  $globals->{dbReference} = DBI->connect("dbi:mysql:$globals->{dbName}:$globals->{dbHost}:3306", $globals->{dbUser}, $globals->{dbPassword});
  if (!defined $globals->{dbReference}) {
    logError("Unable to connect to database: $DBI::errstr");
    return;
  }
}

sub runCQGQuery()
{
  my $sqlStatement = qq(
select bugDescriptions_bugNumber, bugDescriptions_severity, bugDescriptions_priority, bugDescriptions_globalState, bugDescriptions_subComponent, bugDescriptions_module, bugDescriptions_creator, bugDescriptions_assignedTo, bugDescriptions_assignedToManager, bugDescriptions_summary, bugDescriptions_formattedTimeStamp as createdDate,
    metaDataFIT, metaDataSVT, numDays, intSLA, DATE_FORMAT(intSLADate,'%e/%b/%Y') as intSLADate,
    extSLA, DATE_FORMAT(extSLADate,'%e/%b/%Y') as extSLADate,
    IF(numDays > intSLA, 'Yes', 'No') as intSLAViolation,
    IF(numDays > extSLA, 'Yes', 'No') as extSLAViolation 
FROM (SELECT bugDescriptions.bugNumber as bugDescriptions_bugNumber,
    bugDescriptions.severity as bugDescriptions_severity,
    bugDescriptions.priority as bugDescriptions_priority,
    If(count(distinct(targetReleaseId))>1, concat(globalState,'*'), globalState) as bugDescriptions_globalState,
    bugDescriptions.subComponent as bugDescriptions_subComponent,
    bugDescriptions.module as bugDescriptions_module,
    bugDescriptions.creator as bugDescriptions_creator,
    CAST(bugDescriptions.creationTimeStamp AS DATE) as bugDescriptions_creationTimeStamp,
    DATE_FORMAT(bugDescriptions.creationTimeStamp,'%e/%b/%Y') as bugDescriptions_formattedTimeStamp,
    IF(bugDescriptions.assignedTo != '', bugDescriptions.assignedTo, releaseTracking.assignedTo) as bugDescriptions_assignedTo,
    IF(bugDescriptions.assignedTo != '', assignedToManagerAlias.userName, assignedToManagerRTAlias.userName) as bugDescriptions_assignedToManager,
    bugDescriptions.summary as bugDescriptions_summary,
    DATEDIFF(NOW(), bugDescriptions.creationTimeStamp) AS numDays, MAX(IF(metadata.metadataKeyMapId='34', metadata.value, '')) as metaDataFIT,
    MAX(IF(metadata.metadataKeyMapId='35', metadata.value, '')) as metaDataSVT,
    CASE priority*1 WHEN '1' THEN '30' WHEN '2' THEN '30' WHEN '3' THEN '45' ELSE '60' END AS intSLA, CASE priority*1 WHEN '1' THEN DATE_ADD(DATE_FORMAT(bugDescriptions.creationTimeStamp,'%Y-%m-%d'), INTERVAL 30 day) WHEN '2' THEN DATE_ADD(DATE_FORMAT(bugDescriptions.creationTimeStamp,'%Y-%m-%d'), INTERVAL 30 day) WHEN '3' THEN DATE_ADD(DATE_FORMAT(bugDescriptions.creationTimeStamp,'%Y-%m-%d'), INTERVAL 45 day) ELSE DATE_ADD(DATE_FORMAT(bugDescriptions.creationTimeStamp,'%Y-%m-%d'), INTERVAL 60 day) END AS intSLADate, CASE priority*1 WHEN '1' THEN '45' WHEN '2' THEN '45' WHEN '3' THEN '60' ELSE '75' END AS extSLA, CASE priority*1 WHEN '1' THEN DATE_ADD(DATE_FORMAT(bugDescriptions.creationTimeStamp,'%Y-%m-%d'), INTERVAL 45 day) WHEN '2' THEN DATE_ADD(DATE_FORMAT(bugDescriptions.creationTimeStamp,'%Y-%m-%d'), INTERVAL 45 day) WHEN '3' THEN DATE_ADD(DATE_FORMAT(bugDescriptions.creationTimeStamp,'%Y-%m-%d'), INTERVAL 60 day) ELSE DATE_ADD(DATE_FORMAT(bugDescriptions.creationTimeStamp,'%Y-%m-%d'), INTERVAL 75 day) END AS extSLADate 
FROM bugDescriptions 
LEFT JOIN users ON bugDescriptions.creator=users.username 
LEFT JOIN metadata ON metadata.typeId=bugDescriptions.bugNumber 
LEFT JOIN metadataKeyMap ON metadataKeyMap.metadataKeyMapId=metadata.metadataKeyMapId 
LEFT JOIN releaseTracking ON releaseTracking.bugNumber=bugDescriptions.bugNumber 
LEFT JOIN users as assignedToManager ON bugDescriptions.assignedTo=assignedToManager.userName 
LEFT JOIN users as assignedToManagerAlias ON assignedToManagerAlias.userName=assignedToManager.managerName 
LEFT JOIN users as assignedToManagerRT ON releaseTracking.assignedTo=assignedToManagerRT.userName 
LEFT JOIN users as assignedToManagerRTAlias ON assignedToManagerRTAlias.userName=assignedToManagerRT.managerName 
WHERE ( bugDescriptions.productFamily = 'cqg' ) 
   AND ( bugDescriptions.globalState = 'Assigned' ) 
   AND ( bugDescriptions.component = 'EXOS' ) 
GROUP BY bugDescriptions.bugNumber) AS tmptbl
                      );
  my $queryRef     = $globals->{dbReference}->prepare($sqlStatement);
  my $result       = $queryRef->execute();
  if (!$result) {
    logError(qq(Error while executing SQL statement.  Error: "$queryRef->{errstr}"));
  };
  my @bugList = ();
  while( my $currentRow = $queryRef->fetchrow_hashref()) {
    push(@{$globals->{pendingCQG}}, $currentRow);
    ++$globals->{cqgCRcount};
  }
}

sub runCQGCount()
{

  my $sqlStatement = qq(
   SELECT IF(bugDescriptions.assignedTo != '', bugDescriptions.assignedTo, releaseTracking.assignedTo) as assignedTo, count(bugDescriptions.bugNumber) as count
   FROM bugDescriptions
   LEFT JOIN releaseTracking ON releaseTracking.bugNumber=bugDescriptions.bugNumber
   LEFT JOIN users as assignedToManager ON bugDescriptions.assignedTo=assignedToManager.userName
   LEFT JOIN users as assignedToManagerAlias ON assignedToManagerAlias.userName=assignedToManager.managerName
   LEFT JOIN users as assignedToManagerRT ON releaseTracking.assignedTo=assignedToManagerRT.userName
  LEFT JOIN users as assignedToManagerRTAlias ON assignedToManagerRTAlias.userName=assignedToManagerRT.managerName
   WHERE ( bugDescriptions.productFamily = 'cqg' )
     AND ( bugDescriptions.globalState = 'Assigned' )
     AND ( bugDescriptions.component = 'EXOS' )
   GROUP BY assignedTo order by count DESC;
                      );
  my $queryRef     = $globals->{dbReference}->prepare($sqlStatement);
  my $result       = $queryRef->execute();
  if (!$result) {
    logError(qq(Error while executing SQL statement.  Error: "$queryRef->{errstr}"));
  };
  my @bugList = ();
  while( my $currentRow = $queryRef->fetchrow_hashref()) {
    push(@{$globals->{assignedCount}}, $currentRow);
  }

}

sub addDate{

   $creationDate  =  $_[0];
   my $deltaDays  = $_[1];
   my $day = 24*60*60;
   my $xdays = $deltaDays * $day;

   my $datetime  = Time::Piece->strptime($creationDate, '%Y-%m-%d %T');
   $return_date = $datetime + $xdays;
   #print "Return Date before formatting is - $return_date  ";
   my ($cday,$cmonth,$cdate,$cTime,$cyear) = split /\s+/,$return_date;
   $returnDate =  $cdate."/".$cmonth."/".$cyear;
   #print "In addDate Proc : Creation Date - $creationDate, Delta - $x, Return Date - $returnDate \n";
   return $returnDate;
}

sub generateAndSendEmail()
{

my $strMsg = qq(Hi all,<br><br>Please find below the CQG details as on $globals->{today}. CQG Dashboard <a href=http://autosqaeni/tracker/index.php?printCQG=yes>Click Here</a><br><br>);

if ($globals->{cqgCRcount} == 0) {
  $strMsg .=  qq(<br><font size=3 color=green>Zero CQG CRs... !!! </font><br>);
} else {
  my @pendingCQGBugs = (@{$globals->{pendingCQG}});

  # Create the html output that will go into the e-mail  
  $strMsg .= qq(<font size=3 color=red>CQG CRs - $globals->{cqgCRcount}</font><br>
  <TABLE BORDER=1>
  <TR bgcolor=#A0B0E0>
    <TH>CR</TH>
    <TH>Severity</TH>
    <TH>Priority</TH>
    <TH>SubComponent</TH>
    <TH>Module</TH>
    <TH>FIT Owner</TH>
    <TH>SVT Owner</TH>
    <TH>Summary</TH>
    <TH>Pending Days</TH>
	<TH>SLA</TH>		
	<TH>FIT Comments</TH>
	<TH>SVT Comments</TH>	
  </TR>  
  );

  foreach my $currentBug (@pendingCQGBugs) {
    $strMsg .= "<TR bgcolor=white>";

    if ($currentBug->{bugDescriptions_priority} == "1 - Critical" || $currentBug->{bugDescriptions_priority} == "2 - Urgent") {
       $globals->{intSLA} = 30;
    } elsif ($currentBug->{bugDescriptions_priority} == "3 - Important") {
       $globals->{intSLA} = 45;
    } else {
       $globals->{intSLA} = 60;
    }
   
    if ($currentBug->{numDays} < $globals->{intSLA}) { 
       $globals->{intbgColor} = "#D4FFD4"; 
    } else {
       $globals->{intbgColor} = "#EF5A5A";
    }

    $globals->{extSLA} = $globals->{intSLA} + 15;

    if ($currentBug->{numDays} < $globals->{extSLA}) {
       $globals->{extbgColor} = "#D4FFD4";
    } else {
       $globals->{extbgColor} = "#EF5A5A";
    }
	
	# Assign FIT and SVT owners for every CQG, based on the component and subComponent
	print "Sub Component is $currentBug->{bugDescriptions_subComponent} - ";
	if ($currentBug->{bugDescriptions_subComponent} eq "DC") {
	  print "Inside DC Loop \n";
	} else { 
	  print "Subcomponent is not DC \n";
    	}
	#End of Owner Assignment Block

    $globals->{intSLAdate} = addDate($currentBug->{bugDescriptions_creationTimeStamp}, $globals->{intSLA});
    $globals->{extSLAdate} = addDate($currentBug->{bugDescriptions_creationTimeStamp}, $globals->{extSLA});

    $strMsg .= qq(
    <TD><a href=https://tracker.extremenetworks.com/cgi/trackerReport.pl?bugNumber=$currentBug->{bugDescriptions_bugNumber}>$currentBug->{bugDescriptions_bugNumber}</a></TD>
    <TD>$currentBug->{bugDescriptions_severity}</TD>
    <TD>$currentBug->{bugDescriptions_priority}</TD>
    <TD>$currentBug->{bugDescriptions_subComponent}</TD>
    <TD>$currentBug->{bugDescriptions_module}</TD>
    <TD>$globals->{FIT_Owner}</TD>
    <TD>$globals->{SVT_Owner}</TD>
    <TD>$currentBug->{bugDescriptions_summary}</TD>
    <TD align=center>$currentBug->{numDays}</TD>
    <TD align=center>$globals->{intSLA}</TD>	
    <TD>$currentBug->{metaDataFIT}</TD>	
    <TD>$currentBug->{metaDataSVT}</TD>		
</TR>);
  }

  my @pendingCQGCount = (@{$globals->{assignedCount}});

  # Table header for CQG Count pending against each team memner
  $strMsg .= qq(
  </TABLE><BR>
  <font size=3 color=red>Total - $globals->{cqgCRcount}</font><br>
  <TABLE BORDER=1>
  <TR bgcolor=#A0B0E0>
    <TH>Assigned To</TH>
    <TH>Total</TH>
  </TR>
  );

  foreach my $currentBug (@pendingCQGCount) {
    $strMsg .= qq(
    <TD>$currentBug->{assignedTo}</TD>
    <TD align=center>$currentBug->{count}</TD>
    </TR>);
  }

} 

  $strMsg .= qq(</TABLE><br>Thanks,<br>Sridhar\n);

  # Close the html file
  $strMsg .= qq(</HTML>\n);

  # Send the e-mail
  #open(MAIL,"|/usr/sbin/sendmail -t");
    #print MAIL "To: $globals->{sendEmailTo}\n";
    #print MAIL "From: $globals->{sendEmailFrom}\n";
    #print MAIL "Subject: $globals->{emailSubject} - $globals->{today}\n";

    ## Mail Body
    #print MAIL "Content-Type: text/html; charset=ISO-8859-1\n\n";
    #print MAIL $strMsg;
    #close(MAIL);
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
  runCQGQuery();
  runCQGCount();
  generateAndSendEmail();
}

main();

