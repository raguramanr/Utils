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
$globals->{dbUser}           = 'enikiosk-RO';
$globals->{dbPassword}       = 'enikiosk-RO';
$globals->{updateProduction} = 0; # Set this to true only when you want to publish changes to the production database.  Can be set with --production option
$globals->{dbReference}      = undef;
$globals->{sendEmailTo}      = 'Gramkumar@ExtremeNetworks.com, rvelusamy@extremenetworks.com, SPalanivel@ExtremeNetworks.com, ragrajan@extremenetworks.com, uparthasarathy@ExtremeNetworks.com';
$globals->{sendEmailCc}      = 'srbalakrishnan@extremenetworks.com, vaswadhati@extremenetworks.com';
#$globals->{sendEmailTo}     = 'ragrajan@extremenetworks.com';
$globals->{sendEmailFrom}    = 'RBC FA <ragrajan@extremenetworks.com>';
$globals->{intbgColor}       = '';
$globals->{extbgColor}       = '';
$globals->{emailSubject}     = 'CQG Report';
$globals->{pendingCQG}       = ();
$globals->{assignedCount}    = ();
$globals->{today}	     = localtime->strftime('%d/%b/%Y');
$globals->{cqgCRcount}       = 0;
$globals->{intSLA} 	     = 0;
$globals->{extSLA} 	     = 0;
$globals->{intSLAdate} 	     = 0;
$globals->{extSLAdate} 	     = 0;

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
   SELECT bugDescriptions.bugNumber as bugDescriptions_bugNumber,     
       bugDescriptions.severity as bugDescriptions_severity,     
       bugDescriptions.priority as bugDescriptions_priority,     
       If(count(distinct(targetReleaseId))>1, concat(globalState,'*'), globalState) as bugDescriptions_globalState,     
       bugDescriptions.creator as bugDescriptions_creator,     
       CAST(bugDescriptions.creationTimeStamp AS DATE) as bugDescriptions_creationTimeStamp,     
       DATE_FORMAT(bugDescriptions.creationTimeStamp,'%e/%b/%Y') as bugDescriptions_formattedTimeStamp,
       IF(bugDescriptions.assignedTo != '', bugDescriptions.assignedTo, releaseTracking.assignedTo) as bugDescriptions_assignedTo,     
       IF(bugDescriptions.assignedTo != '', assignedToManagerAlias.userName, assignedToManagerRTAlias.userName) as bugDescriptions_assignedToManager,  
       bugDescriptions.summary as bugDescriptions_summary,
       DATEDIFF(NOW(), bugDescriptions.creationTimeStamp) AS numDays
   FROM bugDescriptions
   LEFT JOIN releaseTracking ON releaseTracking.bugNumber=bugDescriptions.bugNumber  
   LEFT JOIN users as assignedToManager ON bugDescriptions.assignedTo=assignedToManager.userName  
   LEFT JOIN users as assignedToManagerAlias ON assignedToManagerAlias.userName=assignedToManager.managerName  
   LEFT JOIN users as assignedToManagerRT ON releaseTracking.assignedTo=assignedToManagerRT.userName  
   LEFT JOIN users as assignedToManagerRTAlias ON assignedToManagerRTAlias.userName=assignedToManagerRT.managerName  
   WHERE ( bugDescriptions.productFamily = 'cqg' )    
     AND ( bugDescriptions.globalState = 'Assigned' )    
     AND ( bugDescriptions.component = 'EXOS' )  
   GROUP BY bugDescriptions.bugNumber
   ORDER BY bugDescriptions_assignedToManager ASC, numDays DESC;
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

 my $strMsg = qq(Hi all,<br><br>Please find below the CQG details as on $globals->{today}. CQG Dashboard <a href=http://autosqaeni/trackerDash/index.php?printCQG=yes>Click Here</a><br><br>);

 if ($globals->{cqgCRcount} == 0) {
  $strMsg .=  qq(<br><font size=4 color=green>Zero CQG CRs... !!! </font><br>);
 } else {
  my @pendingCQGBugs = (@{$globals->{pendingCQG}});

  # Create the html output that will go into the e-mail  
  $strMsg .= qq(<font size=4 color=red>CQG CRs - $globals->{cqgCRcount}</font><br>
  <TABLE BORDER=1>
  <TR bgcolor=#A0B0E0>
    <TH>CR</TH>
    <TH>Severity</TH>
    <TH>Priority</TH>
    <TH>Global State</TH>
    <TH>Creator</TH>
    <TH>Assigned To</TH>
    <TH>Manager</TH>
    <TH>Summary</TH>
    <TH>Created On</TH>
    <TH>Pending Days</TH>
    <TH>Internal SLA</TH>
    <TH>External SLA</TH>
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

    $globals->{intSLAdate} = addDate($currentBug->{bugDescriptions_creationTimeStamp}, $globals->{intSLA});
    $globals->{extSLAdate} = addDate($currentBug->{bugDescriptions_creationTimeStamp}, $globals->{extSLA});

    $strMsg .= qq(
    <TD><a href=https://tracker.extremenetworks.com/cgi/trackerReport.pl?bugNumber=$currentBug->{bugDescriptions_bugNumber}>$currentBug->{bugDescriptions_bugNumber}</a></TD>
    <TD>$currentBug->{bugDescriptions_severity}</TD>
    <TD>$currentBug->{bugDescriptions_priority}</TD>
    <TD>$currentBug->{bugDescriptions_globalState}</TD>
    <TD>$currentBug->{bugDescriptions_creator}</TD>
    <TD>$currentBug->{bugDescriptions_assignedTo}</TD>
    <TD>$currentBug->{bugDescriptions_assignedToManager}</TD>
    <TD>$currentBug->{bugDescriptions_summary}</TD>
    <TD>$currentBug->{bugDescriptions_formattedTimeStamp}</TD>
    <TD align=center>$currentBug->{numDays}</TD>
    <TD bgcolor=$globals->{intbgColor}>$globals->{intSLAdate}</TD>
    <TD bgcolor=$globals->{extbgColor}>$globals->{extSLAdate}</TD>
 </TR>);
  }

  my @pendingCQGCount = (@{$globals->{assignedCount}});

  # Table header for CQG Count pending against each team memner
  $strMsg .= qq(
  </TABLE><BR>
  <font size=4 color=red>Total - $globals->{cqgCRcount}</font><br>
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

  $strMsg .= qq(</TABLE><br>Thanks,<br>Raguraman\n);

  # Close the html file
  $strMsg .= qq(</HTML>\n);

  # Send the e-mail
  open(MAIL,"|/usr/sbin/sendmail -t");
    print MAIL "To: $globals->{sendEmailTo}\n";
    print MAIL "Cc: $globals->{sendEmailCc}\n";
    print MAIL "From: $globals->{sendEmailFrom}\n";
    print MAIL "Subject: $globals->{emailSubject} - $globals->{today}\n";

    ## Mail Body
    print MAIL "Content-Type: text/html; charset=ISO-8859-1\n\n";
    print MAIL $strMsg;
    close(MAIL);
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
