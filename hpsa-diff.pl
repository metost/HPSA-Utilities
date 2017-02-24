#!/usr/bin/perl
# 2HPSA-DIFF.PL - Utility to compare HPSA nodes / to find a server
# 20160805, Ing. Ondrej DURAS (dury)
# ~/prog/HPSA-Utilities/2hpsa-diff.pl
#

## MANUAL ############################################################# {{{ 1

our $VERSION = 2016.081502;
our $MANUAL  = <<__MANUAL__;
NAME: HPSA Difference
FILE: hpsa-diff.pl

DESCRIPTION:
  Utility to find a differences between nodes
  within a HPSA MESH. It also searches for new servers,
  scripts, policies and customers just created onto MESH.
  Utility is intended to help to find differences between
  nodes and the best performance node regarding the access
  to the server.

  Utility works with 'mesh[0-9]*' / 'proxy[0-9]*' options,
  mentioned in 'hpsa' profile of PWA configuration.
  It tries to search them based on 'try' option, including
  the order in which the paricular WebService Points -
  proxy / mesh options should be used.

USAGE:
  ./hpsa-diff -name myserver -mesh 2.3.4.5 -mesh 3.4.5.6
  ./hpsa-diff -oid 12345678 -proxy https://6.7.8.9/osapi/...
  ./hpsa-diff -host myserver.domain.com -no-mesh 3.4.5.6
  ./hpsa-diff -addr 1.2.3.4 -no-proxy https://2.3.4.5/osapi... 
  ./hpsa-diff -server myserver  -mesh 2.3.4.5
  ./hpsa-diff -server 1.2.3.4 
  export VAR_HPSA_PROXY=`hpsa-diff -ser 1.2.3.4 -getpro|grep "^ht"`
  hpsa-diff -server 1.2.3.4 -getproxy | findstr /b http
  hpsa-diff -oid 480260002 -timeout 10 -hot 2>\&1 | hpsa-log

PARAMETERS:
  -name     - HPSA name of the server
  -oid      - HPSA ObjectID of server
  -host     - HostName of the server
  -addr     - IP address of the server
  -server   - any of above to identify a server
  -mesh     - adds one more HPSA node (ip/fqdn)
  -no-mesh  - adds one more HPSA node (ip/fqdn)
  -proxy    - adds one HPSA node (WS point URL)
  -no-proxy - removes one HPSA node (WS point URL)
  -getproxy - provides the best PROXY in standalone line
  -timeout  - timeout of SOAP session in seconds

VERSION: ${VERSION}
__MANUAL__

####################################################################### }}} 1
## INTERFACE ########################################################## {{{ 1

our $SOAP_LITE_STOP = 0;
use strict;
use warnings;
use subs 'die';                             #<#  1/8
use subs 'warn';                            #<#

use Time::HiRes qw(time);
use Data::Dumper;
use SOAP::Lite
      on_fault => sub  {
        my ($soap,$res) = @_;
        $SOAP_LITE_STOP = 1;
      };
use PWA;

sub warn(;$);                               #<#  2/8
sub die(;$$);                               #<#
sub toHpsaProxy($);  # $ $PROXY=toHpsaProxy($MESH); ... transforms PROXY or MESH => to $PROXY
sub feedHpsaProxy(); # Loads all proxies from PWA configuration ( from ~PWA.pm/.pwa.ini )
sub prepareServer(); # $param=prepareServer(); # uses SERVER*/MODE_* taken from command-line
sub findServer($$);  # $list=findServer($PROXY,$param);
sub hpsaFault() {    # giving the last staus of HPSA action and resets the flag;
  my $RESULT = $SOAP_LITE_STOP;
  $SOAP_LITE_STOP = 0;
  warn "#- Warning: SOAP Exception. Communication with proxy failed.\n" if $RESULT;
  return $RESULT;
}
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
#our $PROXY = pwa('hpsa','mesh')  or $PROXY = pwa ('hpsa','proxy') or die "#- Error: None HPSA Proxy found !\n";
sub SOAP::Transport::HTTP::Client::get_basic_credentials {
  return $USER => $PASS;
}

our $PROXY = ""; # fullfilled later eachtime when a findServer found.
our $URI   = 'urn:com.opsware.';
our %HAWSP = (); # Hash of WebService Points
our %HNWSP = (); # Hash of webservice points, they should be removed

# aplication related variables
our $MODE_DUMP   = 0;
our $MODE_REF    = 0;
our $MODE_OID    = 0; 
our $MODE_GETPXY = 0;  # getting the best proxy by the easier way
our $MODE_HOTOUT = 2;  # 0=OFF 1=ON 2=TBD caching STDOUT  -hot / -no-hot  #<#  3/8
our $MODE_TIMEOUT= 0;  # 0=OFF 0>... timeout in seconds                   #<#
our $SERVER_NAME = ""; # HPSA name of the server %
our $SERVER_HOST = ""; # FQDN of the server
our $SERVER_ADDR = ""; # Management IP address of the server
our $SERVER_OID  = ""; # HPSA ObjectID of the server
our $SERVER_ALL  = ""; # any of above server related
our $PROCESS_OID = 0;
our $EXP         = ""; # expression going to be used in findServerRefs();
our @AOID        = ();

our $BEST_PROXY  = "";         # the best WebService Point 
our $BEST_COUNT  = 0;          # the number of servers found at the best WSP
our $BEST_DELAY  = 9999999999; # the delay time of the best WebServicePoint

# collect parameters from the command-line
while(my $ARGX = shift @ARGV) {
  if($ARGX =~ /^-+hot/)     { $MODE_HOTOUT = 1;     next; }  # --hot               #<#  4/8
  if($ARGX =~ /^-+no-?hot/) { $MODE_HOTOUT = 0;     next; }  # --no-hot            #<#
  if($ARGX =~ /^-+tim/)     { $MODE_TIMEOUT= shift; next; }  # --timeout <second>  #<#
  if($ARGX =~ /^-+no-?tim/) { $MODE_TIMEOUT= 0;     next; }  # --no-timeout        #<#
  if($ARGX =~ /^-+n/)       { $SERVER_NAME = shift @ARGV; $MODE_REF=1; next; }
  if($ARGX =~ /^-+[hf]/)    { $SERVER_HOST = shift @ARGV; $MODE_REF=1; next; }
  if($ARGX =~ /^-+[ai]/)    { $SERVER_ADDR = shift @ARGV; $MODE_REF=1; next; }
  if($ARGX =~ /^-+o/)       { $SERVER_OID  = shift @ARGV; $MODE_OID=1; next; }
  if($ARGX =~ /^-+s/)       { $SERVER_ALL  = shift @ARGV; $MODE_REF=1; next; }
  if($ARGX =~ /^-+dump/)    { $MODE_DUMP   = 1;  next; }
  if($ARGX =~ /^-+getpro/)  { $MODE_GETPXY = 1;  next; } 
  if($ARGX =~ /^-+mesh/)    { my $X=shift @ARGV; $HAWSP{toHpsaProxy($X)}=scalar keys %HAWSP; next; }
  if($ARGX =~ /^-+proxy/)   { my $X=shift @ARGV; $HAWSP{toHpsaProxy($X)}=scalar keys %HAWSP; next; }
  if($ARGX =~ /^-+no-?me/)  { my $X=shift @ARGV; $HNWSP{toHpsaProxy($X)}=scalar keys %HNWSP; next; }
  if($ARGX =~ /^-+no-?pr/)  { my $X=shift @ARGV; $HNWSP{toHpsaProxy($X)}=scalar keys %HNWSP; next; }
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


unless($MODE_REF or $MODE_OID) {
  die "#- Error: What should I do ? Have a look to the manual.\n";
}

####################################################################### }}} 1
## MAIN ############################################################### {{{ 1

feedHpsaProxy();
if($MODE_REF or $MODE_OID) {
  my $server = prepareServer();
  foreach my $PROXY ( sort { $HAWSP{$a} cmp $HAWSP{$b} } keys %HAWSP) {
    my $list = findServer($PROXY,$server);
  }
  if($BEST_COUNT > 0) {
    print "#: Server(s) found   ${BEST_COUNT} \n";
    print "#: the Best reply is ${BEST_DELAY} second(s).\n";
    print "#+ the Best proxy  = ${BEST_PROXY}\n";
    if($MODE_GETPXY) {
      print $BEST_PROXY;
      if( -t STDOUT ) { print "\n"; }
    }
  } else {
    warn "#- Error: None server found at any HPSA node !\n";
  }
}

####################################################################### }}} 1
## warn & die - overwritten ########################################### {{{ 1

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
## $PROXY=toHpsaProxy($MESH); ######################################### {{{ 1

sub toHpsaProxy($) {
  my $PROXY = shift;
  
  unless($PROXY =~ /^https?:\/\// ) {
    $PROXY = "https://".$PROXY."/osapi/com/opsware/";
    debug "4","PROXY = '${PROXY}'";
  }
  return $PROXY;
}

####################################################################### }}} 1
## feedHpsaProxy(); ################################################### {{{ 1

sub feedHpsaProxy() {

   # Takes 'try' option - order of WebServicePoints/URLs from PWA config
   my $STRTRY=pwa('hpsa','try');
   my $PXYCT;
   unless($STRTRY) {
     warn "#- Error: 'try' option within 'hpsa' profile of \n";
     warn "#- Error: .pwa.ini file is not defined !\n";
     exit 1;
   }
   print "#: try = ${STRTRY}\n";

   # adding mesh/proxy-ies translated to proxies into list of proxies
   foreach my $ITEM (split(/,/,$STRTRY)) {
     my $PROXY=pwa('hpsa',$ITEM);
     next unless $PROXY;
     $PROXY = toHpsaProxy($PROXY);
     $PXYCT = scalar keys %HAWSP;
     $HAWSP{$PROXY} = $PXYCT;
     print "#: Adding proxy(${PXYCT}) ${ITEM} = ${PROXY}\n";
   }
   foreach my $PROXY (keys %HNWSP) {
     next unless exists($HAWSP{$PROXY});
     $PXYCT = $HNWSP{$PROXY};
     delete $HAWSP{$PROXY};
     print "#: Deleting proxy(n=${PXYCT}) ${PROXY}\n";    
   }
}

####################################################################### }}} 1
## param=prepareServer(); ############################################# {{{ 1

sub prepareServer() {
  my $param;
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
    $param = SOAP::Data->name('self')
                       ->value(
                           \SOAP::Data->name('expression')
                                      ->type('string')
                                      ->value($EXP)
                       );
  }

  if($MODE_OID) {
    $param = SOAP::Data->name('self')
                       ->attr({ 'xmlns:ser' => 'http://server.opsware.com'})
                       ->type('ser:ServerRef')
                       ->value(
                           \SOAP::Data->name('id')
                                      ->type('long')
                                      ->value($SERVER_OID)
                       );
  }

  return $param;
}

####################################################################### }}} 1
## $list=findServer($PROXY,$param); ################################### {{{ 1

sub findServer($$) {
  my ($PROXY,$param) = @_;
  my $result = {};
  my $NAME;
  my $OID;
  my $IDX = $HAWSP{$PROXY};
  my $REPCT = 0;
  my $START = time;

  my $soap_server;                                                            #<#  8/8
  if($MODE_TIMEOUT) {                                                         #<#
    $soap_server = SOAP::Lite                                                 #<#
       ->uri($URI.'server')                                                   #<#
       ->proxy($PROXY.'server/ServerService?wsdl', timeout => $MODE_TIMEOUT); #<#
    print "#: using proxy(${IDX}) = ${PROXY} (timeout=${MODE_TIMEOUT}sec)\n"; #<#
  } else {                                                                    #<#
    $soap_server = SOAP::Lite                                                 #<#
       ->uri($URI.'server')                                                   #<#
       ->proxy($PROXY.'server/ServerService?wsdl');                           #<#
    print "#: using proxy(${IDX}) = ${PROXY}\n";                              #<#
  }                                                                           #<#
  
  if($MODE_REF) {# Queries the HPSA MESH over SOAP/HTTPS -> and retrieves a result
    $result = $soap_server->findServerRefs($param);
    unless (hpsaFault()) { $result = $result->result(); }
    else                 { $result = undef; }
    unless($result) {
      warn "#- Warning: None server found !\n";
      return $result;
    }
    if($MODE_DUMP) { print Dumper $result; }
    
    # Provides a result to STDOUT
    foreach my $server (@$result) {
      $OID  = $server->{id}; 
      $NAME = $server->{name};
      push @AOID,$OID;
      unless($MODE_DUMP) {
        print "#: server ${OID} = ${NAME}\n";
      }
    }
    $REPCT = scalar @$result;
    my $MARKER =":";
    if($REPCT == 0) {
      warn "#- Warning: None server found !\n";
      $MARKER = "-";
    } elsif($REPCT != 1) {
      warn "#- Warning: More than one server found !\n";
      $MARKER = ":";
    } else {
      $MARKER = "+";
    }
    my $STOP = time;
    my $DELAY = $STOP - $START;
    print "#${MARKER} server(s) found ${REPCT} in ${DELAY} second(s).\n";
    if($REPCT > 0) {
      if($BEST_COUNT == 0) { 
        $BEST_COUNT = $REPCT;
        $BEST_PROXY = $PROXY;
        $BEST_DELAY = $DELAY;
      } 
      if($BEST_COUNT != $REPCT) { 
        warn "#- Warning: number of known servers changes from ${BEST_COUNT} to ${REPCT} !\n";
        $BEST_COUNT = $REPCT;
      }
      if($BEST_DELAY > $DELAY ) { 
        $BEST_PROXY = $PROXY;
        $BEST_DELAY = $DELAY;
      }
    }
    $$result[0]->{DELAY} = $DELAY;
    return $$result[0];
  }

  if($MODE_OID) {
    $result = $soap_server->getServerVO($param);
    unless( hpsaFault()) { $result = $result->result(); }
    else                 { $result = undef; }
    unless($result) {
      warn "#- Warning: None server found (${SERVER_OID}) !\n";
      return $result;
    }
    push @AOID,$SERVER_OID;
    if($MODE_DUMP) { 
       print Dumper $result; 
    } else { 
      $NAME = $result->{ref}->{name};
      $OID  = $result->{ref}->{id};
      print "#: server ${OID} = ${NAME}\n";
    }
    my $STOP = time;
    my $DELAY = $STOP - $START;
    $REPCT = 1;
    print "#+ server(s) found ${REPCT} in ${DELAY} second(s).\n";
    unless($BEST_COUNT) { $BEST_COUNT = $REPCT; }
    elsif($BEST_COUNT != $REPCT) { 
      warn "#- Warning: number of known servers changes from ${BEST_COUNT} to ${REPCT} !\n";
      $BEST_COUNT = $REPCT;
      $BEST_PROXY = $PROXY;
      $BEST_DELAY = $DELAY;
    }
    if($BEST_DELAY < $DELAY ) { 
      $BEST_COUNT = $REPCT;
      $BEST_PROXY = $PROXY;
      $BEST_DELAY = $DELAY;
    }
    $result->{ref}->{DELAY} = $DELAY;
    return $result->{ref}; 
  }
}

####################################################################### }}} 1

# --- end ---


