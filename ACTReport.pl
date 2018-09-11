#!/bin/perl
use strict;
use DBI;
use Data::Dumper;
use Time::Piece;
use DateTime;

# Global Variables
my $globals = {};
$globals->{dbHost}           = 'localhost';
$globals->{dbName}           = 'autosqa_act'; 
$globals->{dbUser}           = 'root';
$globals->{dbPassword}       = 'extreme';
$globals->{dbReference}      = undef;
$globals->{sendEmailTo}      = '';
$globals->{sendEmailCc}      = '';
$globals->{sendEmailFrom}    = 'ACT Mailer <ragrajan@extremenetworks.com>';
$globals->{bgColor}    	     = '';
$globals->{emailSubject}     = 'Automation Productivity Report';
$globals->{today}	     = localtime->strftime('%d/%b/%Y');

sub connectToDatabase()
{
  $globals->{dbReference} = DBI->connect("dbi:mysql:$globals->{dbName}:$globals->{dbHost}:3306", $globals->{dbUser}, $globals->{dbPassword});
  if (!defined $globals->{dbReference}) {
    logError("Unable to connect to database: $DBI::errstr");
    return;
  }
}

sub runlastDayQuery()
{
  my $lastDate = DateTime->today;
  $lastDate->subtract( days => 1 );
  my $yesterday = $lastDate->ymd('-');
  my $sqlStatement = qq(

select 
act_test_assigned_to,
SUM(IF(act_test_scripted_date like '%$yesterday%',1,0)) as countScripted,  
SUM(IF(act_test_review_date like '%$yesterday%',1,0)) as countReview,  
SUM(IF(act_test_rework_date like '%yesterday%',1,0)) as countRework,  
SUM(IF(act_test_checkin_date like '%$yesterday%',1,0)) as countCheckIn  
from act_test_report 
where act_test_assigned_to in ('aashok','ailamvazhuthi','mmuthu','rmariappan','ssaladi') 
group by act_test_assigned_to;
                      );
  my $queryRef     = $globals->{dbReference}->prepare($sqlStatement);
  my $result       = $queryRef->execute();
  if (!$result) {
    logError(qq(Error while executing SQL statement.  Error: "$queryRef->{errstr}"));
  };
  my @bugList = ();
  while( my $currentRow = $queryRef->fetchrow_hashref()) {
    push(@{$globals->{lastDayBugs}}, $currentRow);
  }
}

sub generateAndSendEmail()
{
  my $lastDate = DateTime->today;
  $lastDate->subtract( days => 1 );
  my $yesterday = $lastDate->dmy('/');

  # Create the html output that will go into the e-mail  
  my $strMsg = qq(Team,<br><br>Please find the productivity details for $yesterday.<br>);

 # Print the yesterday created Bugs
	  my @lastBugs = (@{$globals->{lastDayBugs}}); 
	  $strMsg .=  qq(<br><TABLE BORDER=1>
	  <TR bgcolor=#A0B0E0>
	    <TH>Scripter Name</TH>
	    <TH>#Scripted</TH>
	    <TH>#Review</TH>
	    <TH>#Rework</TH>
	    <TH>#CheckedIn</TH>
	  </TR> 
	);

	  foreach my $currentBug (@lastBugs) {

	    $strMsg .= qq(
	    <TR>
	    <TD>$currentBug->{act_test_assigned_to}</TD>
	    <TD align=center>$currentBug->{countScripted}</TD>
	    <TD align=center>$currentBug->{countReview}</TD>
	    <TD align=center>$currentBug->{countRework}</TD>
	    <TD align=center>$currentBug->{countCheckIn}</TD>
	  </TR>); 
	 }
	  $strMsg .= qq(</TABLE>);

	  $strMsg .= qq(<br>Thanks,<br>Raguraman\n);
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
  $globals->{sendEmailTo} = $ARGV[0];
  $globals->{sendEmailCc} = $ARGV[1];
  connectToDatabase();
  runlastDayQuery();
  generateAndSendEmail();
}

main();
