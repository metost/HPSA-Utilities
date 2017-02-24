#!/usr/bin/perl
# HPSA-Script - Utility to manage/launch Scripts from HPSA MESH
# 20160426, Ing. Ondrej DURAS (dury)
# ~/prog/vpc-automation/Examples-Soap/5hpsa-script.pl

## MANUAL ############################################################# {{{ 1

our $VERSION = 2017.020701;
our $MANUAL  = <<__MANUAL__;
NAME: HPSA Run Script Utility
FILE: hpsa-script.pl

DESCRIPTION:
  Allows to run a HPSA script onto server.
  Script works in one of three modes.
  -list helps to find a proper script to execute
  -detail helps to know more about the script
  -execute executes the script

USAGE:
  ./hpsa-script -name myserver   -script-id 123456 -execute
  ./hpsa-script -oid 12345678    -script-name "snmpLinux" -execute
  ./hpsa-script -host myserver   -script "snmpLinux" -execute
  ./hpsa-script -addr 1.2.3.4    -script 123456 -execute
  ./hpsa-script -server myserver -script "snmpLinux" -execute
  ./hpsa-script -script-name "snmp%" -list
  ./hpsa-script -script-name "snmp%" -list -timeout 10
  ./hpsa-script -script-id 1234 -details

PARAMETERS:
  -name        - HPSA name of the server
  -oid         - HPSA ObjectID of server
  -host        - HostName of the server
  -addr        - IP address of the server
  -server      - any of above
  -script-name - the name of the script
  -script-oid  - Script unique ID
  -script      - the name or ObjectID of the script
  -list        - lists ScriptID = ScriptName
  -detail      - gives a script details
  -execute     - executes a script onto server
  -timeout     - timeout of SOAP session in seconds

VERSION: ${VERSION}
__MANUAL__

####################################################################### }}} 1
## INTERFACE ########################################################## {{{ 1

use strict;
use warnings;
use subs 'die';
use subs 'warn';
use Data::Dumper;
use SOAP::Lite;
#use SOAP::Lite +trace => 'debug';
use PWA;

# Prototypes
sub warn(;$);
sub die(;$$);
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
our $MODE_LIST   = 0;  # modes of the script operation
our $MODE_DETAIL = 0;  # detailed informations about Script ( listed on -iod basis)
our $MODE_GETOID = 0;  # mode for scripts / providing an ObjectID of the scipt
our $MODE_EXEC   = 0;  # mode of the Script Execution
our $MODE_DUMP   = 0;  # for troubleshooting only - dumps the soap communication with HPSA node
our $MODE_HOTOUT = 2;  # 0=OFF 1=ON 2=TBD caching STDOUT  -hot / -no-hot
our $MODE_TIMEOUT= 0;  # 0=OFF 0>... timeout in seconds
our $MODE_REF    = 0;  # searching the server on findServerRefs basis
our $MODE_OID    = 0;  # searching for the server on ObjectID / getServerVO basis 

our $SERVER_NAME = ""; # HPSA name of the server %
our $SERVER_HOST = ""; # FQDN of the server
our $SERVER_ADDR = ""; # Management IP address of the server
our $SERVER_OID  = ""; # HPSA ObjectID of the server
our $SERVER_ALL  = ""; # any of above server related

our $SCRIPT_NAME = "";
our $SCRIPT_OID  = "";
our $SCRIPT_ANY  = "";
our $EXP = "";
our @AOID        = ();

our @hJobStatus = qw(
  ABORTED ACTIVE CANCELED DELETED FAILURE
  PENDING SUCCESS UNKNOWN WARNING TAMPERED STALE
  BLOCKED RECURRING EXPIRED ZOMBIE TERMINATING
  TERMINATED
);

# collect parameters from the command-line
while(my $ARGX = shift @ARGV) {
  if($ARGX =~ /^-+hot/)         { $MODE_HOTOUT = 1;     next; }  # --hot
  if($ARGX =~ /^-+no-?hot/)     { $MODE_HOTOUT = 0;     next; }  # --no-hot
  if($ARGX =~ /^-+tim/)         { $MODE_TIMEOUT= shift; next; }  # --timeout <second>
  if($ARGX =~ /^-+no-?tim/)     { $MODE_TIMEOUT= 0;     next; }  # --no-timeout
  if($ARGX =~ /^-+dump/)        { $MODE_DUMP = 1; next; }        # --dump
  if($ARGX =~ /^-+n/)           { $SERVER_NAME = shift @ARGV; $MODE_REF=1; next; }  # --name
  if($ARGX =~ /^-+[hf]/)        { $SERVER_HOST = shift @ARGV; $MODE_REF=1; next; }  # --host / --fqdn
  if($ARGX =~ /^-+[ai]/)        { $SERVER_ADDR = shift @ARGV; $MODE_REF=1; next; }  # --addr / --ip
  if($ARGX =~ /^-+o/)           { $SERVER_OID  = shift @ARGV; $MODE_OID=1; next; }  # --oid
  if($ARGX =~ /^-+s[re]/)       { $SERVER_ALL  = shift @ARGV; $MODE_REF=1; next; }  # --server / --search / --srv

  if($ARGX =~ /^-+script-name/) { $SCRIPT_NAME = shift @ARGV; next; }  # --script-name
  if($ARGX =~ /^-+script-oid/)  { $SCRIPT_OID  = shift @ARGV; next; }  # --script-oid
  if($ARGX =~ /^-+script$/)     { $SCRIPT_ANY  = shift @ARGV; next; }  # --script

  if($ARGX =~ /^-+list/)        { $MODE_LIST   = 1; next; }            # --list
  if($ARGX =~ /^-+detail/)      { $MODE_DETAIL = 1; next; }            # --detail
  if($ARGX =~ /^-+exec(ute)?/)  { $MODE_EXEC   = 1; next; }            # --exec
  if($ARGX =~ /^-+getoid$/)     { $MODE_GETOID = 1; next; }            # --getoid
  die "#- Error: wrong argument '${ARGX}' !\n";
}


if($MODE_HOTOUT == 2) {
  unless( -t STDOUT) { $MODE_HOTOUT = 1; }
  else               { $MODE_HOTOUT = 0; }
}
if($MODE_HOTOUT) {
  # http://perl.plover.com/FAQs/Buffering.html
  select((select(STDOUT), $|=1)[0]);
}

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
if($SCRIPT_ANY =~ /^[0-9]+$/) {
  $SCRIPT_OID  = $SCRIPT_ANY;
}
if($SCRIPT_ANY =~ /[a-zA-Z]/) {
  $SCRIPT_NAME = $SCRIPT_ANY;
}
# STOP if something necessary is missing.
die "#- Error: What should I do (-list/-detail/-exec) ?\n"
  unless ( $MODE_LIST or $MODE_DETAIL or $MODE_EXEC or $MODE_GETOID);
die "#- Error: arguments required !\n"
  unless ( $MODE_REF or $MODE_OID or $MODE_LIST or $MODE_DETAIL or $MODE_GETOID);
die "#- Error: missing HPSA login or password !\n"
  unless ( $USER and $PASS );
die "#- Error: have a look into HPSA references !\n"
  unless ( $PROXY and $URI );

####################################################################### }}} 1
## warn & die - overwritten + auth #################################### {{{ 1

sub warn(;$) {
  my $MSG = shift;
  $MSG = "#- Waring !\n" unless $MSG;
  if($MODE_HOTOUT) {
    print STDOUT $MSG;
  } else {
    print STDERR $MSG;
  }
}
sub die(;$$) {
  my ($MSG,$EXIT) = @_; 
  $MSG = "#- Error !\n" unless $MSG; 
  $EXIT = 1 unless $EXIT;
  if($MODE_HOTOUT) {
    print STDOUT $MSG; 
  } else { 
    print STDERR $MSG; 
  } 
  exit $EXIT; 
}

sub SOAP::Transport::HTTP::Client::get_basic_credentials {
  return $USER => $PASS;
}

####################################################################### }}} 1
## SOAP Initiation #################################################### {{{ 1

our $soap_server;                                                                          #<#  8/8a
    if($MODE_TIMEOUT) {                                                                    #<#
      $soap_server = SOAP::Lite                                                            #<#
         ->uri($URI.'server')                                                              #<#
         ->proxy($PROXY.'server/ServerService?wsdl', timeout => $MODE_TIMEOUT);            #<#
    } else {                                                                               #<#
      $soap_server = SOAP::Lite                                                            #<#
         ->uri($URI.'server')                                                              #<#
         ->proxy($PROXY.'server/ServerService?wsdl');                                      #<#
    }                                                                                      #<#

our $soap_job;                                                                             #<#
    if($MODE_TIMEOUT) {                                                                    #<#
      $soap_job = SOAP::Lite                                                               #<#
         ->uri($URI.'job')                                                                 #<#
         ->proxy($PROXY.'job/JobService?wsdl', timeout => $MODE_TIMEOUT);                  #<#
    } else {                                                                               #<#
      $soap_job = SOAP::Lite                                                               #<#
         ->uri($URI.'job')                                                                 #<#
         ->proxy($PROXY.'job/JobService?wsdl');                                            #<#
    }                                                                                      #<#

our $soap_script;                                                                          #<#
    if($MODE_TIMEOUT) {                                                                    #<#
      $soap_script = SOAP::Lite                                                            #<#
         ->uri($URI.'script')                                                              #<#
         ->proxy($PROXY.'script/ServerScriptService?wsdl', timeout => $MODE_TIMEOUT);      #<#
    } else {                                                                               #<#
      $soap_script = SOAP::Lite                                                            #<#
         ->uri($URI.'script')                                                              #<#
         ->proxy($PROXY.'script/ServerScriptService?wsdl');                                #<#
    }                                                                                      #<#

our $param;
our $args;
our $object;
our $result;
our $jobref;
our $expression;

####################################################################### }}} 1
## -list / -getoid handling ########################################### {{{ 1

if($MODE_LIST or $MODE_GETOID) { 

  # composing search expression
  if($SCRIPT_NAME) {
    $EXP = 'ServerScriptVO.name like "'.$SCRIPT_NAME.'"';
  } elsif($SCRIPT_OID) {
    $EXP = 'server_script_oid = '.$SCRIPT_OID;
  }

  # building parameters
  $param = SOAP::Data->name('self')
                     ->attr({ "xmlns:sear" => "http://search.opsware.com"})
                     ->type("sear:Filter")
                     ->value(
                        \SOAP::Data->name('expression')
                                   ->attr({ 'xmlns:soapenc' => 'http://schemas.xmlsoap.org/soap/encoding/'})
                                   ->type('soapenc:string')
                                   ->value($EXP)
                     );

  # communicating to the WebService
  $result = $soap_script->findServerScriptRefs($param)->result;
  if($MODE_DUMP) { 
    print Dumper $result; 
  } elsif($MODE_GETOID) {
    if((scalar @$result) != 1 ) {
      die "#- Error: More than one script found !\n";
    }
    print @$result[0]->{id};
    if( -t STDOUT) { print "\n"; }
  } else {
    foreach my $script ( sort { $a->{name} cmp $b->{name}} @$result ) {
      my $OID  = $script->{id};
      my $NAME = $script->{name};
      print "${OID} = '${NAME}'\n";
    }
  }
  exit 0;
 
}

####################################################################### }}} 1
## ONE script name & oid ONLY ! ####################################### {{{ 1

# composing search expression
if($SCRIPT_NAME) {
  $EXP = 'ServerScriptVO.name like "'.$SCRIPT_NAME.'"';
} elsif($SCRIPT_OID) {
  $EXP = 'server_script_oid = '.$SCRIPT_OID;
}

# building parameters
$param = SOAP::Data->name('self')
                   ->attr({ "xmlns:sear" => "http://search.opsware.com"})
                   ->type("sear:Filter")
                   ->value(
                      \SOAP::Data->name('expression')
                                 ->attr({ 'xmlns:soapenc' => 'http://schemas.xmlsoap.org/soap/encoding/'})
                                 ->type('soapenc:string')
                                 ->value($EXP)
                   );

# communicating to the WebService
$result = $soap_script->findServerScriptRefs($param)->result;
if((scalar @$result) != 1) {
  foreach my $script ( sort { $a->{name} cmp $b->{name}} @$result ) {
    my $OID  = $script->{id};
    my $NAME = $script->{name};
    print "${OID} = '${NAME}'\n";
  }
  die "#- Error: None or more than one script found. Which ONE to use ???\n";
}

$SCRIPT_OID  = $result->[0]->{id};
$SCRIPT_NAME = $result->[0]->{name};
print "#: script ${SCRIPT_OID} = '${SCRIPT_NAME}'\n";

####################################################################### }}} 1
## -detail handling ################################################### {{{ 1

if($MODE_DETAIL) {

  $param = SOAP::Data->name('self')
                     ->attr({'xmlns:scr'=>'http://script.opsware.com' })
                     ->type('scr:ServerScriptRef')
                     ->value(
                         \SOAP::Data->name('id')
                                    ->value($SCRIPT_OID)
                     );
  $result = $soap_script->getServerScriptVO($param);
  print Dumper $result;
  exit 0;
}

unless($MODE_EXEC) { die "#- Error: Something wrong !\n"; }

####################################################################### }}} 1
## EXEC findServerRefs - MODE_REF==1 ################################## {{{ 1

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
## EXEC - getServerVO  - MODE_OID==1 ################################## {{{ 1

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
## EXEC startServerScript ############################################# {{{ 1

$param = SOAP::Data->name('self')
                   ->attr({'xmlns:scr'=> "http://script.opsware.com"})
                   ->type('scr:ServerScriptRef')
                   ->value(
                      \SOAP::Data->name('id')
                                 ->type('long')
                                 ->value($SCRIPT_OID)
                   );



$object = SOAP::Data->name('targets')
                    ->attr({ 'xmlns:ser' => 'http://server.opsware.com'})
                    ->type('ser:ServerRef')
                    ->value(\SOAP::Data->name('id')
                            ->type('long')
                            ->value($SERVER_OID)
                       );

$args = SOAP::Data->name("args")
                  ->value( \SOAP::Data->name("elements" => ($object))->type("ser:ServerRef")
                           #,\SOAP::Data->name("recalculateServersAtRuntime")->value('1')
                            
                          )
             ->attr({ 'xmlns:scr' => 'http://script.opsware.com'})
             ->type("scr:ServerScriptJobArgs");



$jobref = $soap_script->startServerScript($param,$args)->result;
unless($jobref) {
  die "#- Error: Job has NOT been created !\n";
}

#print Dumper $jobref;
our $JOB_NAME = $jobref->{name};
our $JOB_OID  = $jobref->{id};
print "#: jobref ${JOB_OID} = '${JOB_NAME}'\n";

####################################################################### }}} 1
## EXEC - Tracking JobID ############################################## {{{ 1

$param = SOAP::Data->name('self')
                   ->attr({ 'xmlns:job' => 'http://job.opsware.com'})
                   ->type('job:JobRef')
                   ->value(
                      \SOAP::Data->name('id')
                                 ->value($JOB_OID)
                    );

our $COUNT=0;
while(my $job = $soap_job->getJobInfoVO($param)->result) {
  $COUNT++;
  my $STAT=$job->{status};
  my $STXT=$hJobStatus[$STAT];
  #my $STAT=$job->{serverInfo}->[0]->{status};
  print "${COUNT} ... ${STXT}(${STAT}) Job=${JOB_OID} Server=${SERVER_OID} ${SERVER_NAME}\n";
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
  print "Job startded .......... ${JSTART}\n"   if $JSTART;
  print "Job ended ............. ${JSTOP}\n"    if $JSTOP;
  print "Reason for Blocked .... ${JBREASON}\n" if $JBREASON;
  print "Reason ofr Canceled ... ${JCREASON}\n" if $JCREASON;
  print "Schedule .............. ${JSCHED}\n"   if $JSCHED;
  print "Notification .......... ${JNOTIFY}\n"  if $JNOTIFY;
}

####################################################################### }}} 1
## JobOutput ########################################################## {{{ 1

our $parjob = SOAP::Data->name('job')
                   ->attr({ 'xmlns:job' => 'http://job.opsware.com'})
                   ->type('job:JobRef')
                   ->value(
                      \SOAP::Data->name('id')
                                 ->value($JOB_OID)
                    );
our $parsrv = SOAP::Data->name('server')
                   ->attr({ 'xmlns:ser' => 'http://server.opsware.com'})
                   ->type('ser:ServerRef')
                   ->value(
                      \SOAP::Data->name('id')
                                 ->value($SERVER_OID)
                    );
our $jobresult = $soap_job->getJobInfoVO($param)->result;
our $joboutput = $soap_script->getServerScriptJobOutput($parjob,$parsrv)->result; 

if($MODE_DUMP) {
  print "# ===== Job Result =============\n";
  print Dumper $jobresult;
  print "# ===== Job Output =============\n";
  print Dumper $joboutput;
  exit;
} else {

  print "startDate ...... ".$jobresult->{startDate}."\n"; 
  print "endDate ........ ".$jobresult->{endDate}."\n";
  print "exitCode ....... ".$joboutput->{exitCode}."\n"; 
  
  our $XSTDOUT = $joboutput->{tailStdout};
  our $XSTDERR = $joboutput->{tailStderr};
  if($XSTDOUT =~ /\S/) {
    print "= [1] STDOUT =================\n";
    print $XSTDOUT;
  }
  if($XSTDERR =~ /\S/) {
    print "= [2] STDERR =================\n";
    print $XSTDERR;
  }
}
print "= done. ======================\n";

####################################################################### }}} 1
