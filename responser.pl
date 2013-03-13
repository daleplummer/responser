#!/usr/bin/perl 
# $Id: responser.pl,v 1.1 2004/06/16 21:28:50 dalep Exp $

#
#  responser (original author unknown)
#
#  Checks servers by looking at a server web site.  If the site
#  responds then the server is assumed to be up.  If the site
#  is down then email is sent.  There are two (!) config files
#  used to specify what sites to monitor and where to send email
#  (see "Program Settings" below.)
#
#  Schedule this with a cron job, e.g.
#  $ crontab -e
#     55 * * * * /home/dalep/responser/responser.pl
#  This will run responser.pl at 55 minutes past the hour for every
#  hour of every day.
#
use warnings;
use strict;
use Tie::File;
use Net::SMTP;
use LWP::UserAgent;

#################################################################
#             Program  Settings
#
my $file_path = '/home/dalep/responser/';	# Path to needed files
my $error_log  = $file_path.'responser_errors.txt';  	# File to store errors of program
my $input_file = $file_path.'responser_urls.txt';          # File containing URLs of sites to be monitored
my $smtp_file  = $file_path.'responser_smtp_settings.txt'; # File for SMTP Settings
my $response_limit = 12; #In Seconds      # seconds to wait for sendmail; 0 -> will not send mail
my $send_mail  = 1;                       # my $send_mail  = 1; ->SMTP option is ON,
                                          # my $send_mail  = 0; ->SMTP option is OFF
##################################################################
#                      END OF SETTINGS
# Do not edit bellow if you dont understand it.
##################################################################
die "File $input_file does not exist\n" unless (-e $input_file);
die "SMTP is ON, but file $smtp_file does not exist\n" unless (-e $smtp_file);
my $localtime     = localtime;
our @errors;
my ($day,$month,$date,$hour,$year) = split /\s+/,scalar localtime;
#my $output_file = $file_path.'report-'.$date.'.'.$month.'.'.$year.'.txt';
my $output_file = $file_path . $year . $month . $date .'.txt';
print $output_file . "\n";
my ($smtp_host,$recipient,$reverse_path, @all_addr) = ();
tie @all_addr, 'Tie::File', $input_file or error("Cannot open $input_file to read addresses");
if (-e $output_file) {
	open(OUT,">> $output_file") or error("Cannot open existing file $output_file for append");
} else {
	open(OUT,"> $output_file") or error("Cannot open new file $output_file for writting");
}

my @smtp_settings;

if ($^O =~ /win/i) {
	tie @smtp_settings, 'Tie::File', $smtp_file,, recsep => "\012" or error("Cannot open $smtp_file to read SMTP settings");
} else {
	tie @smtp_settings, 'Tie::File', $smtp_file,autochomp => '0'                  or error("Cannot open $smtp_file to read SMTP settings");
}

for (@smtp_settings) {
	chomp;
	next if /^#/;
	#next if /^$/;
	if (/^(\w+)\s=\s'(\S+)'/) {
		$smtp_host     = $2 if ($1 eq 'SMTPHost');
		$recipient     = $2 if ($1 eq 'Recipient');
		$reverse_path  = $2 if ($1 eq 'Reverse');
	}
}

print OUT "\n+" .('-' x 74) . "+\n";
print OUT   "|", ' ' x 30,"Time: $hour",' ' x 30,"|\n";
print OUT   "|",' 'x 10,'HOST',' ' x 37,'STATUS',' ' x 7,"RESPONSE  |\n";
print OUT   "+" .('-' x 74) . "+\n";

for (0 .. $#all_addr) {
	chop $all_addr[$_] if ($all_addr[$_] =~ /\s+$/);
	next if ($all_addr[$_]  eq "");
	if ($all_addr[$_] =~ /^http:\/\/\S+\.\w{2,4}$/) {  #address will begin with http://.  Next some string
                                                    # finish with point and 2 to 4 letters
		check_url($all_addr[$_]);    #call subroutine check_url()
	} else {
		my $out_format = sprintf "| %-50.50s %-10s  %-20s|\n", $all_addr[$_], "WRONG", "N/A";
		printf OUT $out_format;
		printf $out_format;
		push @errors, "$all_addr[$_] is WRONG Address.";
	}
}

my $err = join "\015\012",@errors;
my $err2 = $err."\n";
my $err_num = scalar @errors;  # How match DOWN + WRONG Sites have
$send_mail = 0 unless $err_num;
untie @all_addr or error("Unable to close file $input_file");

if ($send_mail) {
	my $smtp = Net::SMTP->new($smtp_host,
				-Debug=>1,
				-Timeout=>20,
				-Hello=>"$smtp_host") or error("Cannot connect to $smtp_host");
				
	print OUT   "recipient: $recipient","\n";                           
	print OUT   "smtp_host: $smtp_host","\n";
	
	# Begin Compare mail message
my $msg = <<__END_OF_MAIL__;
To: $recipient
Subject: $err_num : Server Down : $localtime .
$localtime
$err
	
__END_OF_MAIL__
	# End Compare
	
	$smtp->mail("$reverse_path") or error("Failed to specify a reverse-path");#  If all is OK
	$smtp->to($recipient) or error("Failed to specify a recipient");          #  that will
	$smtp->data([$msg]) or error("Failed to send a message");                 #  send mail
	$smtp->quit or error("Failed to quit");                                   #  to You
} else {
	print "Send Mail is OFF\n" if $err_num;          # If you do not wish to receive mail
}

close OUT or error("Unable to close file $output_file");
print "\nProcess FINISH\n";

sub check_url {  # subroutine who check given URL
	my $target = $_[0];
	my $ua = LWP::UserAgent->new;
	$ua->agent("$0/0.1 " . $ua->agent);
	my $req = HTTP::Request->new(GET => "$target");
	$req->header('Accept' => 'text/html');          #Accept HTML Page
	# send request
	my $start = time;      # Start timer
	my $res = $ua->request($req);
	# check the outcome
	if ($res->is_success) {# Success....all content of page has been received
		my $time = time;     # End timer
		my $out_format;
		$time = ($time - $start); # Result of timer
		if ($response_limit && ($response_limit <= $time)) {
			push(@errors, "Slow response from $target\: $time seconds");
			$out_format = sprintf "| %-40.40s %-10s %-20s |\n", $target, "SLOW", "Response $time seconds";
		} else {
			$out_format = sprintf "| %-40.40s %-10s %-20s |\n", $target, "ACCESSED", "Response $time seconds";
			}
		print OUT $out_format; # write to file
		print $out_format;     # print to console
	} else {                 # Error .... Site is DOWN and script send e-mail to you..
		my $out_format = sprintf "| %-40.40s %-10s %-20s |\n", $target, "DOWN", " N/A";
		push(@errors, "$target is DOWN." . $res->status_line) or error("Cannot push error for DOWN");
		print OUT $out_format; # write to file
		print $out_format;     # print to console
		}
}

sub error {      # subroutine to print in Error Log
  my $error_msg = shift;
  open ERR,">> $error_log" or die "Cannot open log file $error_log : $!\n";
  print ERR "$localtime\: $error_msg : $!\n";
  close ERR or die "Cannot close log file $error_log : $!\n";
}
