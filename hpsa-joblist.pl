#!/usr/bin/perl
# HPSA-JobList - Utility to search JOB statuses & results
# 20160501, Ing. Ondrej DURAS (dury)
# ~/prog/vpc-automation/Examples-Soap/3hpsa-joblist.pl

## MANUAL ############################################################# {{{ 1

our $VERSION = 2016.081502;
our $MANUAL  = <<__END__;
NAME: HPSA Job List Utility
FILE: hpsa-joblist.pl

DESCRIPTION:
  Provides a list of HPSA Jobs related
  to the server.

USAGE:
  ./hpsa-joblist -name myserver
  ./hpsa-joblist -oid 12345678
  ./hpsa-joblist -name myserver -timeout 10

PARAMETERS:
  -name    - HPSA name of the server
  -oid     - HPSA ObjectID of server
  -timeout - timeout of SOAP session in seconds


VERSION: ${VERSION}
__END__

####################################################################### }}} 1
## INTERFACE ########################################################## {{{ 1

use strict;
use warnings;
use subs 'die';                             #<#  1/8
use subs 'warn';                            #<#
use Data::Dumper;
#use SOAP::Lite +trace=>'debug';
use SOAP::Lite;
use PWA;

sub warn(;$);                               #<#  2/8
sub die(;$$);                               #<#

# if no parameters given, then provide a manual
unless(scalar @ARGV) {
  print $MANUAL;
  exit 1;
}

# Site related details.
# To configure or troubleshoot them
# please use the PassWord Agent.
# Do not edit them manualy !
our $USER  = pwaLogin('hpsa')    or die "#- Error: None HPSA Login found !\n";
our $PASS  = pwaPassword('hpsa') or die "#- Error: None HPSA Password found !\n";
our $PROXY = pwa('hpsa','mesh')  or $PROXY = pwa ('hpsa','proxy') or die "#- Error: None HPSA Proxy found !\n";
our $URI   = 'urn:com.opsware.';

# aplication related variables
our $MODE_DUMP   = 0;  # troubleshooting mode - dumps all HPSA(soap) communication
our $MODE_HOTOUT = 2;  # 0=OFF 1=ON 2=TBD caching STDOUT  -hot / -no-hot  #<#  3/8
our $MODE_TIMEOUT= 0;  # 0=OFF 0>... timeout in seconds                   #<#
our $SEARCH_NAME = ""; # search the server by its hpsa name
our $SEARCH_OID  = ""; # search the server based on its hpsaoid
our $EXP = "";

# collect parameters from the command-line
while(my $ARGX = shift @ARGV) {
  if($ARGX =~ /^-+hot/)     { $MODE_HOTOUT = 1;     next; }  # --hot               #<#  4/8
  if($ARGX =~ /^-+no-?hot/) { $MODE_HOTOUT = 0;     next; }  # --no-hot            #<#
  if($ARGX =~ /^-+tim/)     { $MODE_TIMEOUT= shift; next; }  # --timeout <second>  #<#
  if($ARGX =~ /^-+no-?tim/) { $MODE_TIMEOUT= 0;     next; }  # --no-timeout        #<#
  if($ARGX =~ /^-+n/)    { $SEARCH_NAME = shift @ARGV; next; }
  if($ARGX =~ /^-+o/)    { $SEARCH_OID  = shift @ARGV; next; }
  if($ARGX =~ /^-+dump/) { $MODE_DUMP = 1; next; }
  die "#- Error: wrong argument '${ARGX}' !\n";        #<#  5/8
}


if($MODE_HOTOUT == 2) {                        #<#  6/8
  unless( -t STDOUT) { $MODE_HOTOUT = 1; }     #<#
  else               { $MODE_HOTOUT = 0; }     #<#
}                                              #<#
if($MODE_HOTOUT) {                             #<#
  # http://perl.plover.com/FAQs/Buffering.html #<#
  select((select(STDOUT), $|=1)[0]);           #<#
}                                              #<#


# PROXY  settings
unless($PROXY =~ /^https?:\/\// ) {
  $PROXY = "https://".$PROXY."/osapi/com/opsware/";
  debug "4","PROXY = '${PROXY}'";
}
  
# STOP if something necessary is missing.
die "#- Error: arguments required !\n"
  unless ( $SEARCH_NAME or $SEARCH_OID );
die "#- Error: missing HPSA login or password !\n"
  unless ( $USER and $PASS );
die "#- Error: have a look into HPSA references !\n"
  unless ( $PROXY and $URI );

####################################################################### }}} 1
## get_basic_credentials ; warn & die - overwritten ################### {{{ 1

sub SOAP::Transport::HTTP::Client::get_basic_credentials {
  return $USER => $PASS;
}

sub warn(;$) {                              #<#  7/8
  my $MSG = shift;                          #<#
  $MSG = "#- Waring !\n" unless $MSG;       #<#
  if($MODE_HOTOUT) {                        #<#
    print STDOUT $MSG;                      #<#
  } else {                                  #<#
    print STDERR $MSG;                      #<#
  }                                         #<#
}                                           #<#
sub die(;$$) {                              #<#
  my ($MSG,$EXIT) = @_;                     #<#
  $MSG = "#- Error !\n" unless $MSG;        #<#
  $EXIT = 1 unless $EXIT;                   #<#
  if($MODE_HOTOUT) {                        #<#
    print STDOUT $MSG;                      #<#
  } else {                                  #<#
    print STDERR $MSG;                      #<#
  }                                         #<#
  exit $EXIT;                               #<#
}                                           #<#

####################################################################### }}} 1
## MAIN ############################################################### {{{ 1

if($SEARCH_NAME) {
  $EXP = 'job_device_systemname like "'.$SEARCH_NAME.'%"';
} elsif($SEARCH_OID) {
  $EXP = 'job_device_id = '.$SEARCH_OID;
}


our $soap_job;                                                             #<#  8/8a
    if($MODE_TIMEOUT) {                                                    #<#
      $soap_job = SOAP::Lite                                               #<#
         ->uri($URI.'job')                                                 #<#
         ->proxy($PROXY.'job/JobService?wsdl', timeout => $MODE_TIMEOUT);  #<#
    } else {                                                               #<#
      $soap_job = SOAP::Lite                                               #<#
         ->uri($URI.'job')                                                 #<#
         ->proxy($PROXY.'job/JobService?wsdl');                            #<#
    }                                                                      #<#

our $soap_swmgmt;                                                                       #<#  8/8b
    if($MODE_TIMEOUT) {                                                                 #<#
      $soap_swmgmt = SOAP::Lite                                                         #<#
         ->uri($URI.'swmgmt')                                                           #<#
         ->proxy($PROXY.'swmgmt/SoftwarePolicyService?wsdl', timeout => $MODE_TIMEOUT); #<#
    } else {                                                                            #<#
      $soap_swmgmt = SOAP::Lite                                                         #<#
         ->uri($URI.'swmgmt')                                                           #<#
         ->proxy($PROXY.'swmgmt/SoftwarePolicyService?wsdl');                           #<#
    }                                                                                   #<#

our $all_policies = $soap_swmgmt->findSoftwarePolicyRefs()->result;
our $hpolicy = {};
foreach my $policy (@$all_policies) {
  $hpolicy->{$policy->{id}} = $policy->{name};
}
#print Dumper $hpolicy;



our $param = SOAP::Data->name('self')->value(
               \SOAP::Data->name('expression')
                          ->type('string')
                          ->value($EXP)
             );


our $result = $soap_job->findJobRefs($param)->result;
our @mids = (); 
foreach my $jobref (@$result) {
  my $JID = $jobref->{id};
  my $JNM = $jobref->{name};
  if($MODE_DUMP) { print "${JID} : ${JNM}\n"; }

  my $object = SOAP::Data->name('JobRef')
                   ->value(\SOAP::Data->name('id')
                           ->type('long')
                           ->value($jobref->{'id'})
                          )
                   ->attr({ 'xmlns:job' => 'http://job.opsware.com'})
                   ->type('job:JobRef');
  push @mids, $object;
}


our $selves = SOAP::Data->name("selves" => 
                           \SOAP::Data->name("element" => @mids)->type("job:JobRef")
                          )
             ->attr({ 'xmlns:job' => 'http://job.opsware.com'})
             ->type("job:ArrayOfJobRef");



our $par_result = $soap_job->getJobInfoVOs($selves)->result();

if($MODE_DUMP) {
  print Dumper $par_result;
  exit 0;
} 

foreach my $job (sort { $a->{startDate} cmp $b->{startDate}} @$par_result) {
 my $JID  = $job->{ref}->{id};
 my $TYPE = $job->{type};
 my $STAT = $job->{status};
 my $BEGIN= $job->{startDate};
 my $END  = $job->{endDate};
 my $NAME = "";  # Software (script/policy) name
 my $SWID = 0;   # Software (script/policy) ID
 if($TYPE eq 'server.script.run') {
    $TYPE = "Script";
    $SWID = $job->{script}->{id};
    $NAME = $job->{script}->{name};
 } elsif($TYPE eq 'server.swpolicy.remediate') {
    $TYPE = "Software Policy";
    $SWID = $job->{jobArgs}->{policyAttachableMap}->[0]->{policies}->[0]->{id};
    $NAME = $hpolicy->{$SWID};
 } elsif($TYPE eq 'program_apx.execute') {
    $TYPE = "APX";
    $SWID = 0;
    $NAME = $job->{ref}->{name}; 
 } elsif($TYPE eq 'opsware.agent_reach.check_reachability') {
    $TYPE = "Communication Test";
    $SWID = 0;
    $NAME = $job->{ref}->{name}; 
 }
 print <<__END__;

[${JID}]
  Type ............ ${TYPE}
  Status .......... ${STAT}  
  Started ......... ${BEGIN}
  End ............. ${END}
  Name ............ ${NAME}
  Software ID ..... ${SWID}
__END__
}

#print Dumper $par_result;


####################################################################### }}} 1

# --- end ---

