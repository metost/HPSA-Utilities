#!/usr/bin/perl
# HPSA-Ping - Utility co check connectivity to HPSA Mesh over SOAP
# 20160606, Ing. Ondrej DURAS (dury)
# ~/prog/vpc-automation/Examples-Soap/8hpsa-ping.pl
#

## MANUAL ############################################################# {{{ 1

our $VERSION = 2016.081502;
our $MANUAL  = <<__END__;
NAME: HPSA Ping Utility
FILE: hpsa-ping.pl

DESCRIPTION:
  Checks the connection to HPSA mesh over the SOAP protocol.

USAGE:
  ./hpsa-ping -test
  ./hpsa-ping -test -quiet
  ./hpsa-ping -mesh frgrssas203.gre.omc.hp.com -timeout 10
  ./hpsa-ping -base https://frgrssas203.gre.omc.hp.com/osapi/com/opsware/

PARAMETERS:
  -test    - proceed the test of configured mesh
  -mesh    - allows to define the mesh fqdn to test
  -base    - allows to define the WebService base to test
  -quiet   - suppress the PROXY URL message
  -timeout - timeout of SOAP session in seconds

VERSION: ${VERSION}

__END__

####################################################################### }}} 1
## INTERFACE ########################################################## {{{ 1

use strict;
use warnings;
use subs 'die';                             #<#  1/8
use subs 'warn';                            #<#
use Time::HiRes qw(time);
use Data::Dumper;
use Net::SSLeay;
use IO::Socket::SSL;
use SOAP::Lite;
#use SOAP::Lite +trace => 'all';
use PWA;

# Prototypes 
sub warn(;$);                               #<#  2/8
sub die(;$$);                               #<#

# if no parameter given a manual is going to be displayed
unless(scalar @ARGV) {
  print $MANUAL;
  exit 1;
}

our $USER  = pwaLogin('hpsa')    or die "#- Error: None HPSA Login found !\n";
our $PASS  = pwaPassword('hpsa') or die "#- Error: None HPSA Password found !\n";
our $PROXY = "";
#our $PROXY = pwa('hpsa','proxy') or die "#- Error: None HPSA Proxy found !\n";
our $URI   = 'urn:com.opsware.'; 

our $MODE_DEBUG  = 0;
our $MODE_DUMP   = 0;
our $MODE_HOTOUT = 2;  # 0=OFF 1=ON 2=TBD caching STDOUT  -hot / -no-hot  #<#  3/8
our $MODE_TIMEOUT= 0;  # 0=OFF 0>... timeout in seconds                   #<#
our $MODE_TEST   = 0;
our $MODE_QUIET  = 0;
our $MODE_PROXY  = "";
our $MODE_MESH   = "";


while(my $ARGX = shift @ARGV) {
  if($ARGX =~ /^-+hot/)     { $MODE_HOTOUT = 1;     next; }      # --hot               #<#  4/8
  if($ARGX =~ /^-+no-?hot/) { $MODE_HOTOUT = 0;     next; }      # --no-hot            #<#
  if($ARGX =~ /^-+tim/)     { $MODE_TIMEOUT= shift; next; }      # --timeout <second>  #<#
  if($ARGX =~ /^-+no-?tim/) { $MODE_TIMEOUT= 0;     next; }      # --no-timeout        #<#
  if($ARGX =~ /^-+dump/)    { $MODE_DUMP  = 1;           next; } # --dump
  if($ARGX =~ /^-+t/)       { $MODE_TEST  = 1;           next; } # --test
  if($ARGX =~ /^-+q/)       { $MODE_QUIET = 1;           next; } # --quiet
  if($ARGX =~ /^-+no-?q/)   { $MODE_QUIET = 0;           next; } # --no-quiet
  if($ARGX =~ /^-+v+/)      { $MODE_DEBUG = 4;           next; } # --verbose
  if($ARGX =~ /^-+(b|p)/)   { $MODE_PROXY = shift @ARGV; next; } # --base / --proxy
  if($ARGX =~ /^-+m/)       { $MODE_MESH  = shift @ARGV; next; } # --mesh
  die "#- Error: wrong argument '${ARGX}' !\n";   #<#  5/8
}


if($MODE_HOTOUT == 2) {                        #<#  6/8
  unless( -t STDOUT) { $MODE_HOTOUT = 1; }     #<#
  else               { $MODE_HOTOUT = 0; }     #<#
}                                              #<#
if($MODE_HOTOUT) {                             #<#
  # http://perl.plover.com/FAQs/Buffering.html #<#
  select((select(STDOUT), $|=1)[0]);           #<#
}                                              #<#


# Setting a debug mode
if($MODE_DEBUG) { 
  print "#: debug level ${MODE_DEBUG}\n"; 
  SOAP::Lite->import(trace => 'all'); 
  $ENV{HTTPS_DEBUG}       = $MODE_DEBUG;
  $IO::Socket::SSL::DEBUG = $MODE_DEBUG;
  $Net::SSLeay::trace     = $MODE_DEBUG;
}

if($MODE_TEST) {
  $PROXY = pwa('hpsa','proxy');
  unless($PROXY) { 
    $PROXY =  pwa('hpsa','mesh') or die "#- None HPSA proxy or mesh defined !\n";
    $PROXY = 'https://'.$PROXY.'/osapi/com/opsware/';
  }
} elsif ($MODE_MESH) {
  $PROXY = 'https://'.$MODE_MESH.'/osapi/com/opsware/';
} elsif ($MODE_PROXY) {
  $PROXY = $MODE_PROXY;
} else { die "3- Error! What should I do (-test/-mesh/-proxy) ?\n"; }

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


debug(4,"PROXY = '${PROXY}'");
our $soap_search;                                                                  #<# 8/8
    if($MODE_TIMEOUT) {                                                            #<#
      $soap_search = SOAP::Lite                                                    #<#
          ->uri($URI.'search')                                                     #<#
          ->proxy($PROXY.'search/SearchService?wsdl', timeout => $MODE_TIMEOUT);   #<#
    } else {                                                                       #<#
      $soap_search = SOAP::Lite                                                    #<#
          ->uri($URI.'search')                                                     #<#
          ->proxy($PROXY.'search/SearchService?wsdl');                             #<#
    }                                                                              #<#

####################################################################### }}} 1
## MAIN ############################################################### {{{ 1

unless($MODE_QUIET) {
  print "#: proxy = ${PROXY}\n";
}

our $START  = time;
our $result = $soap_search->getSearchableTypes()->result;
our $STOP   = time;
if($MODE_DUMP) {
  print Dumper $result;
}
if($result) {
  my $DUR = $STOP - $START;
  print "Good ${DUR}s .\n";
}

####################################################################### }}} 1

# --- end ---


