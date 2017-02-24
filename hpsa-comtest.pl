#!/usr/bin/perl
# HPSA-ComTest - Utility to perform a HPSA Communication Test
# 20160502, Ing. Ondrej DURAS (dury)
# vpc-automation/Examples-Soap/4hpsa-comtest.pl


## MANUAL ############################################################# {{{ 1

our $VERSION = 2016.081502;
our $MANUAL  = <<__END__;
NAME: HPSA Communication Test Utility
FILE: hpsa-comtest.pl

DESCRIPTION:
  Performs Communication Test 
  between server and HPSA MESH.

USAGE:
  ./hpsa-comtest -name myserver
  ./hpsa-comtest -oid 12345678
  ./hpsa-comtest -host myserver.domain.com
  ./hpsa-comtest -add 1.2.3.4
  ./hpsa-comtest -server myserver 
  ./hpsa-comtest -server myserver -timeout 10 

PARAMETERS:
  -name    - HPSA name of the server
  -oid     - HPSA ObjectID of server
  -host    - HostName of the server
  -addr    - IP address of the server
  -server  - any of above
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
our $MODE_DUMP   = 0;  # troubleshooting mode - dumps all soap communication with HPSA WSPoint
our $MODE_HOTOUT = 2;  # 0=OFF 1=ON 2=TBD caching STDOUT  -hot / -no-hot  #<#  3/8
our $MODE_TIMEOUT= 0;  # 0=OFF 0>... timeout in seconds                   #<#
our $MODE_REF    = 0;
our $MODE_OID    = 0; 
our $SERVER_NAME = ""; # HPSA name of the server %
our $SERVER_HOST = ""; # FQDN of the server
our $SERVER_ADDR = ""; # Management IP address of the server
our $SERVER_OID  = ""; # HPSA ObjectID of the server
our $SERVER_ALL  = ""; # any of above server related
our $PROCESS_OID = 0;
our $EXP         = ""; # expression going to be used in findServerRefs();
our @AOID        = ();

our @hJobStatus = qw(
  ABORTED ACTIVE CANCELED DELETED FAILURE
  PENDING SUCCESS UNKNOWN WARNING TAMPERED STALE
  BLOCKED RECURRING EXPIRED ZOMBIE TERMINATING
  TERMINATED
);

# collect parameters from the command-line
while(my $ARGX = shift @ARGV) {
  if($ARGX =~ /^-+hot/)     { $MODE_HOTOUT = 1;     next; }  # --hot               #<#  4/8
  if($ARGX =~ /^-+no-?hot/) { $MODE_HOTOUT = 0;     next; }  # --no-hot            #<#
  if($ARGX =~ /^-+tim/)     { $MODE_TIMEOUT= shift; next; }  # --timeout <second>  #<#
  if($ARGX =~ /^-+no-?tim/) { $MODE_TIMEOUT= 0;     next; }  # --no-timeout        #<#
  if($ARGX =~ /^-+n/)    { $SERVER_NAME = shift @ARGV; $MODE_REF=1; next; }
  if($ARGX =~ /^-+[hf]/) { $SERVER_HOST = shift @ARGV; $MODE_REF=1; next; }
  if($ARGX =~ /^-+[ai]/) { $SERVER_ADDR = shift @ARGV; $MODE_REF=1; next; }
  if($ARGX =~ /^-+o/)    { $SERVER_OID  = shift @ARGV; $MODE_OID=1; next; }
  if($ARGX =~ /^-+s/)    { $SERVER_ALL  = shift @ARGV; $MODE_REF=1; next; }
  if($ARGX =~ /^-+dump/) { $MODE_DUMP = 1; next; }
  die "#- Error: wrong argument '${ARGX}' !\n";    #<#  5/8
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

if($SERVER_ALL =~ /^[0-9]+$/) {
  $SERVER_OID = $SERVER_ALL; $SERVER_ALL = "";
  $MODE_REF = 0; $MODE_OID = 1;
  debug "4","-server parameter contains OID, changing to MODE_OID=1.";
}

# STOP if something necessary is missing.
die "#- Error: arguments required !\n"
  unless ( $MODE_REF or $MODE_OID );
die "#- Error: missing HPSA login or password !\n"
  unless ( $USER and $PASS );
die "#- Error: have a look into HPSA references !\n"
  unless ( $PROXY and $URI );

####################################################################### }}} 1
## warn & die - overwritten + auth #################################### {{{ 1

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

sub SOAP::Transport::HTTP::Client::get_basic_credentials {
  return $USER => $PASS;
}

####################################################################### }}} 1
## SOAP Initiation #################################################### {{{ 1



our $soap_server;                                                               #<#  8/8
    if($MODE_TIMEOUT) {                                                         #<#
      $soap_server = SOAP::Lite                                                 #<#
         ->uri($URI.'server')                                                   #<#
         ->proxy($PROXY.'server/ServerService?wsdl', timeout => $MODE_TIMEOUT); #<#
    } else {                                                                    #<#
      $soap_server = SOAP::Lite                                                 #<#
         ->uri($URI.'server')                                                   #<#
         ->proxy($PROXY.'server/ServerService?wsdl');                           #<#
    }                                                                           #<#

our $soap_job;                                                                  #<#
    if($MODE_TIMEOUT) {                                                         #<#
      $soap_job = SOAP::Lite                                                    #<#
         ->uri($URI.'job')                                                      #<#
         ->proxy($PROXY.'job/JobService?wsdl', timeout => $MODE_TIMEOUT);       #<#
    } else {                                                                    #<#
      $soap_job = SOAP::Lite                                                    #<#
         ->uri($URI.'job')                                                      #<#
         ->proxy($PROXY.'job/JobService?wsdl');                                 #<#
    }                                                                           #<#


our $param;
our $object;
our $selves;
our $process;
our $expression;
our $result;

####################################################################### }}} 1
## MAIN findServerRefs - MODE_REF==1 ################################## {{{ 1

# That part is used when we translate 
# name/fqdn/something --into--> HPSA_ObjectID
if($MODE_REF) {

  # Builds a EXPression for query
  if($SERVER_NAME) {
    $EXP = 'ServerVO.name like "'.$SERVER_NAME.'"';
  } elsif($SERVER_HOST) {
    $EXP = 'ServerVO.HostName like "'.$SERVER_HOST.'"';
  } elsif($SERVER_ADDR) {
    $EXP = '((device_interface_ip = "'.$SERVER_ADDR.'") | '
         . '(device_management_ip = "'.$SERVER_ADDR.'"))';
  } elsif($SERVER_ALL)  {
    $EXP = '((ServerVO.name like "'.$SERVER_ALL.'") | '
         . '(ServerVO.hostName like "'.$SERVER_ALL.'") | '
         . '(device_interface_ip = "'.$SERVER_ALL.'") | '
         . '(device_management_ip = "'.$SERVER_ALL.'"))';
  } else {
    die "#- Error: invalid expression !\n";
  }
  
  # Transforms EXPression into XML/SOAP query
  $expression = SOAP::Data->name('self')
                          ->value(
                              \SOAP::Data->name('expression')
                                         ->type('string')
                                         ->value($EXP)
                );
  
  # Queries the HPSA MESH over SOAP/HTTPS -> and retrieves a result
  $result = $soap_server->findServerRefs($expression)->result;
  unless($result) {
    die "#- Error: None server found !\n";
  }
  if($MODE_DUMP) { print Dumper $result; }
  
  # Provides a result to STDOUT
  foreach my $server (@$result) {
    $SERVER_OID  = $server->{id}; 
    $SERVER_NAME = $server->{name};
    push @AOID,$SERVER_OID;
    unless($MODE_DUMP) {
      print "#: server ${SERVER_OID} = ${SERVER_NAME}\n";
    }
  }
  if((scalar @$result) != 1) {
    die "#- Error: More than one server found !\n";
  }
  
}


####################################################################### }}} 1
## MAIN - getServerVO  - MODE_OID==1 ################################## {{{ 1

# That part is used when we translate
# HPSA ObjectID --into--> name,HostName,IP...
if($MODE_OID) {
  $param = SOAP::Data->name('self')
                     ->attr({ 'xmlns:ser' => 'http://server.opsware.com'})
                     ->type('ser:ServerRef')
                     ->value(
                         \SOAP::Data->name('id')
                                    ->type('long')
                                    ->value($SERVER_OID)
                     );
  $result = $soap_server->getServerVO($param)->result;
  unless($result) {
    die "#- Error: None server found (${SERVER_OID}) !\n";
  }
  push @AOID,$SERVER_OID;
  if($MODE_DUMP) { 
     print Dumper $result; 
  } else { 
    my $NAME = $result->{name};
    print "#: server ${SERVER_OID} = ${NAME}\n";
  }
}

####################################################################### }}} 1
## MAIN - Create Communication-Test Job ############################### {{{ 1



$object = SOAP::Data->name('ServerRef')
                    ->value(\SOAP::Data->name('id')
                                       ->type('long')
                                       ->value($SERVER_OID)
                           )
                    ->attr({ 'xmlns:ser' => 'http://server.opsware.com'})
                    ->type('ser:ServerRef');


$selves = SOAP::Data->name("selves" => 
                            \SOAP::Data->name("element" => ($object))
                                       ->type("ser:ServerRef")
                          )
                    ->attr({ 'xmlns:ser' => 'http://server.opsware.com'})
                    ->type("ser:ArrayOfServerRef");


$process = $soap_server->runAgentCommTest($selves)->result;
$PROCESS_OID = $process->{id};

if($MODE_DUMP) { print Dumper $process; }
else { 
  my $TYPE = $process->{secureResourceTypeName};
  my $NAME = $process->{name};
  my $LONG = $process->{idAsLong};
  print "#: process JobOID   = ${PROCESS_OID} \n";
  print "#: process idAsLong = ${LONG}\n";
  print "#: process type     = ${TYPE}\n";
  print "#: process name     = ${NAME}\n";
  print "==============================\n";
}

####################################################################### }}} 1
## MAIN - Tracking JobID ############################################## {{{ 1

$param = SOAP::Data->name('self')
                   ->attr({ 'xmlns:job' => 'http://job.opsware.com'})
                   ->type('job:JobRef')
                   ->value(
                      \SOAP::Data->name('id')
                                 ->value($PROCESS_OID)
                    );

our $COUNT=0;
while(my $job = $soap_job->getJobInfoVO($param)->result) {
  $COUNT++;
  my $STAT=$job->{status};
  my $STXT=$hJobStatus[$STAT];
  #my $STAT=$job->{serverInfo}->[0]->{status};
  print "${COUNT} ... ${STXT}(${STAT}) Job=${PROCESS_OID} Server=${SERVER_OID} ${SERVER_NAME}\n";
  if($MODE_DUMP) { print Dumper $job; }
  last if ($STAT != 1);
  sleep(1);
}
print "==============================\n";
our $job = $soap_job->getJobInfoVO($param)->result;

if($MODE_DUMP) { print Dumper $job; }
else {
  my $JSTATUS  = $job->{status};         unless(defined $JSTATUS)  { $JSTATUS = ""; }
  my $JSTEXT   = $hJobStatus[$JSTATUS];  unless(defined $JSTEXT)   { $JSTEXT  = ""; }
  my $JSTART   = $job->{startDate};      unless(defined $JSTART)   { $JSTART  = ""; }
  my $JSTOP    = $job->{endDate};        unless(defined $JSTOP)    { $JSTOP   = ""; }
  my $JBREASON = $job->{blockedReason};  unless(defined $JBREASON) { $JBREASON= ""; }
  my $JCREASON = $job->{canceledReason}; unless(defined $JCREASON) { $JCREASON= ""; }
  my $JSCHED   = $job->{schedule};       unless(defined $JSCHED)   { $JSCHED  = ""; }
  my $JDESC    = $job->{description};    unless(defined $JDESC)    { $JDESC   = ""; }
  my $JNOTIFY  = $job->{notification};   unless(defined $JNOTIFY)  { $JNOTIFY = ""; }
  my $JTYPE    = $job->{type};           unless(defined $JTYPE)    { $JTYPE   = ""; }

  print "Status ................ ${JSTEXT}(${JSTATUS})\n";
  print "Job Type .............. ${JTYPE}\n"    if $JTYPE;
  print "Description ........... ${JDESC}\n"    if $JDESC;
  print "Comtest started ....... ${JSTART}\n"   if $JSTART;
  print "Comtest ended ......... ${JSTOP}\n"    if $JSTOP;
  print "Reason for Blocked .... ${JBREASON}\n" if $JBREASON;
  print "Reason ofr Canceled ... ${JCREASON}\n" if $JCREASON;
  print "Schedule .............. ${JSCHED}\n"   if $JSCHED;
  print "Notification .......... ${JNOTIFY}\n"  if $JNOTIFY;
}

####################################################################### }}} 1

# --- end ---

