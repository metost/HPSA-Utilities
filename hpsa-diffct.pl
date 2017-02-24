#!/usr/bin/perl
# HPSA-DiFFct - Utility to check HPSA node intergrity
# 20160615, Ing. Ondrej DURAS (dury)
# ~/prog/vpc-automation/Examples-HPSA/2hpsa-diff.pl

## MANUAL ############################################################# {{{ 1

our $VERSION = 2016.081502;
our $MANUAL  = <<__MANUAL__;
NAME: HPSA DiFFct Utility
FILE: hpsa-diffct.pl

DESCRIPTION:
  This utility helps to check whether the HPSA nodes
  are / are not synchronized. It's usefull when it's 
  needed to troubleshoot overloaded HPSA mesh, or
  other synchronization issues.

USAGE:
  hpsa-diffct -check mesh1.domain.com mesh2.domain.com
  hpsa-diffct -check 1.2.3.4 1.2.3.5
  hpsa-diffct -check -mesh1 -mesh2
  hpsa-diffct -check -proxy1 -proxy2
  hpsa-diffct -check https://mesh1.domain.com/osapi/com/opsware \
                     https://mesh2.domain.com/osapi/com/opsware
  hpsa-diffct -synch     1.2.3.4 1.2.3.5
  hpsa-diffct -servers   1.2.3.4 1.2.3.5
  hpsa-diffct -scripts   1.2.3.4 1.2.3.5
  hpsa-diffct -policies  1.2.3.4 1.2.3.5
  hpsa-diffct -customers 1.2.3.4 1.2.3.5

PARAMETERS:
  All parameters except (*) are followed by two or more
  HPSA nodes where each HPSA node can be defined by 
  WebService point URL, FQDN or  IP address or the attribut 
  name from PWA configuration / 'hpsa' user profile.
  (proxy1, proxy2, mesh1, mesh2 ...)

  -check     - checks all servers, policies, scripts, customers
  -servers   - compares the lists of servers only
  -scripts   - compares the lists of scripts only
  -policies  - compares the lists of SoftwarePolicies only
  -customers - compares the lists of customers
  -synch     - waits till nodes become synchronized
  -dump      - provides a dump of retrieved data (*)
  -verbose   - complete SOAP XML communication to STDOUT (*)
  -timeout   - timeout of SOAP session in seconds

VERSION: ${VERSION}
__MANUAL__

####################################################################### }}} 1
## INTERFACE ########################################################## {{{ 1

use strict;
use warnings;
use subs 'die';                             #<#  1/8
use subs 'warn';                            #<#
use Data::Dumper;
use SOAP::Lite;
#use SOAP::Lite +trace=>'debug';
use PWA;

sub warn(;$);                               #<#  2/8
sub die(;$$);                               #<#

# if no parameters given, then provide a manual
unless(scalar @ARGV) {
  print $MANUAL;
  exit 1;
}


our $MODE_DUMP     = 0;  # troubleshooting mode - dumps all SOAP communication
our $MODE_HOTOUT   = 2;  # 0=OFF 1=ON 2=TBD caching STDOUT  -hot / -no-hot  #<#  3/8
our $MODE_TIMEOUT  = 0;  # 0=OFF 0>... timeout in seconds                   #<#
our $MODE_VERB     = 0;  # troubleshooting mode -providing alghoritm details
our $MODE_SYNC     = 0;  # waiting while nodes become synchronized - a bulshit
our $MODE_SERVERS  = 0;  # comparing the number of servers
our $MODE_POLICIES = 0;  # conparing the number of policies
our $MODE_SCRIPTS  = 0;  # comparing the number of scripts
our $MODE_CUSTOMERS= 0;  # comparing the number of customers
our $CLUSTER       = {};
our $STOP          = 1;
our $USER          = pwaLogin('hpsa')    or die "#- Error: None HPSA Login found !\n";
our $PASS          = pwaPassword('hpsa') or die "#- Error: None HPSA Password found !\n";
our $URI           = 'urn:com.opsware.';

while(my $ARGX = shift @ARGV) {
  if($ARGX =~ /^-+hot/)     { $MODE_HOTOUT = 1;     next; }  # --hot               #<#  4/8
  if($ARGX =~ /^-+no-?hot/) { $MODE_HOTOUT = 0;     next; }  # --no-hot            #<#
  if($ARGX =~ /^-+tim/)     { $MODE_TIMEOUT= shift; next; }  # --timeout <second>  #<#
  if($ARGX =~ /^-+no-?tim/) { $MODE_TIMEOUT= 0;     next; }  # --no-timeout        #<#
  if($ARGX =~ /^-+dump/)    { $MODE_DUMP = 1; next; }
  if($ARGX =~ /^-+verb/)    { $MODE_VERB = 1; next; }
  if($ARGX =~ /^-+sync/)    { $MODE_SYNC = 1; next; }
  if($ARGX =~ /^-+serv/)    { $MODE_SERVERS   = 1; next; }
  if($ARGX =~ /^-+scr/)     { $MODE_SCRIPTS   = 1; next; }
  if($ARGX =~ /^-+pol/)     { $MODE_POLICIES  = 1; next; }
  if($ARGX =~ /^-+cust/)    { $MODE_CUSTOMERS = 1; next; }
  if($ARGX =~ /^-+check/)   { # Simply all 
                              $MODE_SERVERS   = 1;
                              $MODE_SCRIPTS   = 1;
                              $MODE_POLICIES  = 1;
                              $MODE_CUSTOMERS = 1;
                              next;
                            }

  # -mesh arguments
  if($ARGX =~ /^-+mesh[0-9]*$/) {
    my $NAME = $ARGX; $NAME =~ s/^-+//;
    my $MESH = pwa('hpsa',$NAME);
    unless($MESH) { 
      die "#- mesh '${NAME}' not found in PWA configuration !\n"; 
    }
    my $PROXY = "https://${MESH}/osapi/com/opsware/";
    $CLUSTER->{$NAME} =  {};
    $CLUSTER->{$NAME}->{proxy} = $PROXY;
    $STOP = 0 if $STOP == 1; # 2=error !!
    print "#: proxy '${NAME}' => ${PROXY}\n";
    next;
  }

  # -proxy arguments
  if($ARGX =~ /^-+proxy[0-9]*$/) {
    my $NAME  = $ARGX; $NAME =~ s/^-+//;
    my $PROXY = pwa('hpsa',$NAME);
    unless($PROXY) { 
      die "#- Proxy '${NAME}' not found in PWA configuration !\n"; 
    }
    $CLUSTER->{$NAME} =  {};
    $CLUSTER->{$NAME}->{proxy} = $PROXY;
    $STOP = 0 if $STOP == 1; # 2=error !!
    print "#: mesh '${NAME}' => ${PROXY}\n";
    next;
  }

  # something wrong
  if($ARGX =~ /^-/) { 
    warn "#- Wrong argument '${ARGX}' !\n"; $STOP=2; 
    next; 
  }

  # FQDN / IP / WebService URLs
  my $PROXY = $ARGX;
  unless($PROXY =~ /^https?:\/\//) {
    $PROXY = "https://${PROXY}/osapi/com/opsware/";
    print "#: FQDN '${ARGX}' => ${PROXY}\n";
  } else {
    print "#: WS '${ARGX}' => ${PROXY}\n";
  }
  $CLUSTER->{$ARGX} = {}; 
  $CLUSTER->{$ARGX}->{proxy} = $PROXY;
  $STOP = 0 if $STOP == 1; # 2=error !!
}

# if error or none node defined => STOP !
if($STOP) { 
  die "#- Errors at command-line !\n"; 
}

if($MODE_HOTOUT == 2) {                        #<#  6/8
  unless( -t STDOUT) { $MODE_HOTOUT = 1; }     #<#
  else               { $MODE_HOTOUT = 0; }     #<#
}                                              #<#
if($MODE_HOTOUT) {                             #<#
  # http://perl.plover.com/FAQs/Buffering.html #<#
  select((select(STDOUT), $|=1)[0]);           #<#
}                                              #<#

# Authentication
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
## RETRIEVING DATA #################################################### {{{ 1

foreach my $NODE ( sort keys %$CLUSTER ) {
  my $PT    = $CLUSTER->{$NODE};
  my $PROXY = $PT->{proxy};
  
  if($MODE_SERVERS) {
    my $soap_server;                                                                             #<#
    if($MODE_TIMEOUT) {                                                                          #<#
      $soap_server = SOAP::Lite                                                                  #<#
                       ->uri($URI.'server')                                                      #<#
                       ->proxy($PROXY.'server/ServerService?wsdl', timeout => $MODE_TIMEOUT);    #<#
    } else {                                                                                     #<#
      $soap_server = SOAP::Lite                                                                  #<#
                       ->uri($URI.'server')                                                      #<#
                       ->proxy($PROXY.'server/ServerService?wsdl');                              #<#
    }                                                                                            #<#


    my $self = SOAP::Data->name('self')
                         ->value(
                              \SOAP::Data->name('expression')
                                         ->type('string')
                                         ->value('ServerVO.name like "%"')
                           );

    my $result = $PT->{servers}  = $soap_server->findServerRefs($self)->result;
    if($MODE_DUMP) { print Dumper $PT->{servers}; }
    print "#: ${NODE} has ".(scalar @$result)." servers.\n";
  }
  
  if($MODE_SCRIPTS) {
    my $soap_script;                                                                             #<#
    if($MODE_TIMEOUT) {                                                                          #<#
       $soap_script = SOAP::Lite                                                                 #<#
                    ->uri($URI.'script')                                                         #<#
                    ->proxy($PROXY.'script/ServerScriptService?wsdl', timeout => $MODE_TIMEOUT); #<#
    } else {                                                                                     #<#
       $soap_script = SOAP::Lite                                                                 #<#
                    ->uri($URI.'script')                                                         #<#
                    ->proxy($PROXY.'script/ServerScriptService?wsdl');                           #<#
    }                                                                                            #<#


    my $self = SOAP::Data->name('self')
                         ->attr({ "xmlns:sear" => "http://search.opsware.com"})
                         ->type("sear:Filter")
                         ->value(
                             \SOAP::Data->name('expression')
                                        ->attr({'xmlns:soapenc' => 'http://schemas.xmlsoap.org/soap/encoding/'})
                                        ->type('soapenc:string')
                                        ->value('ServerScriptVO.name like "%"')
                         );

    my $result = $PT->{scripts}  = $soap_script->findServerScriptRefs($self)->result;
    if($MODE_DUMP) { print Dumper $PT->{scripts}; }
    print "#: ${NODE} has ".(scalar @$result)." scripts.\n";
  }

  if($MODE_POLICIES) {
    my $soap_policy;                                                                               #<#
    if($MODE_TIMEOUT) {                                                                            #<#
       $soap_policy = SOAP::Lite                                                                   #<#
                    ->uri($URI.'swmgmt')                                                           #<#
                    ->proxy($PROXY.'swmgmt/SoftwarePolicyService?wsdl', timeout => $MODE_TIMEOUT); #<#
    } else {                                                                                       #<#
       $soap_policy = SOAP::Lite                                                                   #<#
                    ->uri($URI.'swmgmt')                                                           #<#
                    ->proxy($PROXY.'swmgmt/SoftwarePolicyService?wsdl');                           #<#
    }                                                                                              #<#

    my $filter = SOAP::Data->name('filter')
                           ->attr({ "xmlns:sear" => "http://search.opsware.com"})
                           ->type("sear:Filter")
                           ->value(
                               \SOAP::Data->name('expression')
                                          ->attr({ 'xmlns:soapenc' => 'http://schemas.xmlsoap.org/soap/encoding/'})
                                          ->type('soapenc:string')
                                          ->value('SoftwarePolicyVO.name like "%"')
                     );



    my $result = $PT->{policies} = $soap_policy->findSoftwarePolicyRefs($filter)->result;
    if($MODE_DUMP) { print Dumper $PT->{policies}; }
    print "#: ${NODE} has ".(scalar @$result)." SoftwarePolicies.\n";
  }

  if($MODE_CUSTOMERS) {
    my $soap_cust;                                                                              #<#
    if($MODE_TIMEOUT) {                                                                         #<#
       $soap_cust   = SOAP::Lite                                                                #<#
                    ->uri($URI.'locality')                                                      #<#
                    ->proxy($PROXY.'locality/CustomerService?wsdl', timeout => $MODE_TIMEOUT);  #<#
    } else {                                                                                    #<#
       $soap_cust   = SOAP::Lite                                                                #<#
                    ->uri($URI.'locality')                                                      #<#
                    ->proxy($PROXY.'locality/CustomerService?wsdl');                            #<#
    }                                                                                           #<#


    my $filter = SOAP::Data->name('filter')
                           ->attr({ "xmlns:sear" => "http://search.opsware.com"})
                           ->type("sear:Filter")
                           ->value(
                               \SOAP::Data->name('expression')
                                          ->attr({ 'xmlns:soapenc' => 'http://schemas.xmlsoap.org/soap/encoding/'})
                                          ->type('soapenc:string')
                                          ->value('CustomerVO.name like "%"')
                     );

    my $result = $PT->{customers}= $soap_cust->findCustomerRefs($filter)->result;
    if($MODE_DUMP) { print Dumper $PT->{customers}; }
    print "#: ${NODE} has ".(scalar @$result)." customers.\n";
  }

}

####################################################################### }}} 1
## SEARCHING for DIFFERENCIES ######################################### {{{ 1

####################################################################### }}} 1
## SUMMARIES ########################################################## {{{ 1

####################################################################### }}} 1
