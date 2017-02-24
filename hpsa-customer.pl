#!/usr/bin/perl
# HPSA-Customer - Server-Customer relationship management Utility
# 20160425, Ing. Ondrej DURAS (dury)
# ~/prog/vpc-automation/Examples-Soap/6hpsa-customer.pl

## MANUAL ############################################################# {{{ 1

our $VERSION = 2016.081502;
our $MANUAL  = <<__END__;
NAME: HPSA Customer Utility
FILE: hpsa-customer.pl

DESCRIPTION:
  Allows to browse the list of Customers.
  Also it allows you to check or set the right customer
  onto the server in Compute area.
  Script works in one of four modes.
  -list helps to find a Customer
  -detail helps to know more about the Customer
  -get provides a list of servers with their customers
  -set a customer for ONE particular server

USAGE:
  ./hpsa-customer -list   NASA\%
  ./hpsa-customer -detail 123435
  ./hpsa-customer -detail NASA\%
  ./hpsa-customer -getoid "NASA%"
  ./hpsa-customer -oid    1234567    -get
  ./hpsa-customer -name   mysrvida12 -set 12345
  ./hpsa-customer -server 12345678   -set markem
  ./hpsa-customer -addr   1.2.3.4    -get
  ./hpsa-customer -host   server123  -get -timeout 10


PARAMETERS:
  -list    - filtered list of the Customers
  -detail  - gives the details of ONE Customer
  -getoid  - gives a Customer ObjectID
  -get     - gets a customer of the particular ONE server
  -set     - sets a customer for particular ONE server
  -name    - HPSA name of the server
  -oid     - HPSA ObjectID of server
  -host    - HostName of the server
  -addr    - IP address of the server
  -server  - any of above server related
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
#use SOAP::Lite +trace => 'debug';
use PWA;

# Prototypes
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
our $MODE_DUMP   = 0;  # for troubleshooting purposes only
our $MODE_HOTOUT = 2;  # 0=OFF 1=ON 2=TBD caching STDOUT  -hot / -no-hot  #<#  3/8
our $MODE_TIMEOUT= 0;  # 0=OFF 0>... timeout in seconds                   #<#
our $MODE_REF    = 0;  # server searched by name or something on findServerRefs basis
our $MODE_OID    = 0;  # server searched by oid on getServerVO basis

our $MODE_LIST   = 0;  # modes of the script operation
our $MODE_DETAIL = 0;  # provides details of particular customer
our $MODE_GETOID = 0;  # for scripts - gives the Customer's ObjectID
our $MODE_QUIET  = 0;  # suppres translations and other details (-getoid uses it transparently)
our $MODE_GET    = 0;  # retieves customer detail related to the server
our $MODE_SET    = 0;  # sets the customer to the server

our $SERVER_NAME = ""; # HPSA name of the server %
our $SERVER_HOST = ""; # FQDN of the server
our $SERVER_ADDR = ""; # Management IP address of the server
our $SERVER_OID  = ""; # HPSA ObjectID of the server
our $SERVER_ALL  = ""; # any of above server related
our $SERVER_MSG  = ""; # Server_name / oid ...whatever for error messages
our $CUSTOM_NAME = ""; # in request
our $CUSTOM_OID  = "";
our $CUSTOM_MSG  = ""; # Customer's name/oid whatever for erro messages
our $QCUST_NAME  = ""; # retrieved
our $QCUST_OID   = 0;  
our $EXP = "";
our @AOID        = ();


# collect parameters from the command-line
while(my $ARGX = shift @ARGV) {
  if($ARGX =~ /^-+hot/)     { $MODE_HOTOUT = 1;     next; }  # --hot               #<#  4/8
  if($ARGX =~ /^-+no-?hot/) { $MODE_HOTOUT = 0;     next; }  # --no-hot            #<#
  if($ARGX =~ /^-+tim/)     { $MODE_TIMEOUT= shift; next; }  # --timeout <second>  #<#
  if($ARGX =~ /^-+no-?tim/) { $MODE_TIMEOUT= 0;     next; }  # --no-timeout        #<#
  if($ARGX =~ /^-+dump/)    { $MODE_DUMP   = 1; next; }      # --dump
  if($ARGX =~ /^-+list/)    { $CUSTOM_NAME = shift @ARGV; $MODE_LIST   = 1; next; } # --list
  if($ARGX =~ /^-+detail/)  { $CUSTOM_NAME = shift @ARGV; $MODE_DETAIL = 1; next; } # --detail
  if($ARGX =~ /^-+getoid/)  { $CUSTOM_NAME = shift @ARGV; $MODE_GETOID = 1; $MODE_QUIET = 1; next; } # --getoid
  if($ARGX =~ /^-+set/)     { $CUSTOM_NAME = shift @ARGV; $MODE_SET    = 1; next; } # --set <cust>
  if($ARGX =~ /^-+get/)     {                             $MODE_GET    = 1; next; } # --get / --customer
  if($ARGX =~ /^-+cus/)     {                             $MODE_GET    = 1; next; } # --customer / --get
  if($ARGX =~ /^-+n/)       { $SERVER_NAME = shift @ARGV; $MODE_REF=1; next; }      # --name
  if($ARGX =~ /^-+[hf]/)    { $SERVER_HOST = shift @ARGV; $MODE_REF=1; next; }      # --host / --fqdn
  if($ARGX =~ /^-+[ai]/)    { $SERVER_ADDR = shift @ARGV; $MODE_REF=1; next; }      # --addr / --ip
  if($ARGX =~ /^-+o/)       { $SERVER_OID  = shift @ARGV; $MODE_OID=1; next; }      # --oid
  if($ARGX =~ /^-+s/)       { $SERVER_ALL  = shift @ARGV; $MODE_REF=1; next; }      # --search / --server
  die "#- Error: wrong argument '${ARGX}' !\n";  #<#  5/8
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

$SERVER_MSG = $SERVER_NAME . $SERVER_HOST . $SERVER_ADDR . $SERVER_OID . $SERVER_ALL;
$CUSTOM_MSG = $CUSTOM_NAME . $CUSTOM_OID;

# STOP if something necessary is missing.
die "#- Error: Missing one of arguments (-list/-detail/-get/-set) ?\n"
  unless ( $MODE_LIST or $MODE_DETAIL or $MODE_GET or $MODE_SET or $MODE_GETOID);
die "#- Error: Customer Name/ObjectID required !\n"
  unless ( $CUSTOM_NAME or $MODE_GET );
die "#- Error: missing HPSA login or password !\n"
  unless ( $USER and $PASS );
die "#- Error: None HPSA mesh/proxy configured !\n"
  unless ( $PROXY and $URI );

if($CUSTOM_NAME  =~ /^[0-9]+$/) { 
   $CUSTOM_OID   = $CUSTOM_NAME;
   $CUSTOM_NAME = "";
}
if($SERVER_ALL  =~ /^[0-9]+$/) {
   $SERVER_OID   = $SERVER_ALL;
   $SERVER_NAME  = "";
   $MODE_OID = 1;
   $MODE_REF = 0;
   debug "4","-server parameter contains OID, changing to MODE_OID=1.";
}

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

our $soap_server;                                                                   #<#  8/8
    if($MODE_TIMEOUT) {                                                             #<#
      $soap_server = SOAP::Lite                                                     #<#
         ->uri($URI.'server')                                                       #<#
         ->proxy($PROXY.'server/ServerService?wsdl', timeout => $MODE_TIMEOUT);     #<#
    } else {                                                                        #<#
      $soap_server = SOAP::Lite                                                     #<#
         ->uri($URI.'server')                                                       #<#
         ->proxy($PROXY.'server/ServerService?wsdl');                               #<#
    }                                                                               #<#

our $soap_cust;                                                                     #<#  
    if($MODE_TIMEOUT) {                                                             #<#
      $soap_cust = SOAP::Lite                                                       #<#
         ->uri($URI.'locality')                                                     #<#
         ->proxy($PROXY.'locality/CustomerService?wsdl', timeout => $MODE_TIMEOUT); #<#
    } else {                                                                        #<#
      $soap_cust = SOAP::Lite                                                       #<#
         ->uri($URI.'locality')                                                     #<#
         ->proxy($PROXY.'locality/CustomerService?wsdl');                           #<#
    }                                                                               #<#

our $param;
our $args;
our $result;
our $expression;

####################################################################### }}} 1
## -list handling ##################################################### {{{ 1

if($MODE_LIST) { 

  # composing search expression
  if($CUSTOM_NAME) {
    $EXP = '((CustomerVO.name like "'.$CUSTOM_NAME.'") | '
         . '(CustomerVO.displayName like "'.$CUSTOM_NAME.'") |'
         . '(customer_rc_name like "'.$CUSTOM_NAME.'"))';
  } elsif($CUSTOM_OID) {
    $EXP = 'customer_rc_id = '.$CUSTOM_OID;
  }
  print "#: EXP '${EXP}'\n" unless $MODE_QUIET;
  # building parameters
  $param = SOAP::Data->name('filter')
                     ->attr({ "xmlns:sear" => "http://search.opsware.com"})
                     ->type("sear:Filter")
                     ->value(
                        \SOAP::Data->name('expression')
                                   ->attr({ 'xmlns:soapenc' => 'http://schemas.xmlsoap.org/soap/encoding/'})
                                   ->type('soapenc:string')
                                   ->value($EXP)
                     );

  # communicating to the WebService
  $result = $soap_cust->findCustomerRefs($param)->result;
  foreach my $cust ( sort { $a->{name} cmp $b->{name}} @$result ) {
    my $OID  = $cust->{id};
    my $NAME = $cust->{name};
    print "${OID} = '${NAME}'\n" unless $MODE_QUIET;
  }
  exit 0;
 
}

####################################################################### }}} 1
## ONE Customer name & oid ONLY ! ##################################### {{{ 1

unless($MODE_GET) {
  # composing search expression
  if($CUSTOM_NAME) {
    $EXP = '((CustomerVO.name like "'.$CUSTOM_NAME.'") | '
         . '(CustomerVO.displayName like "'.$CUSTOM_NAME.'") |'
         . '(customer_rc_name like "'.$CUSTOM_NAME.'"))';
    # building parameters
    $param = SOAP::Data->name('filter')
                       ->attr({ "xmlns:sear" => "http://search.opsware.com"})
                       ->type("sear:Filter")
                       ->value(
                          \SOAP::Data->name('expression')
                                     ->attr({ 'xmlns:soapenc' => 'http://schemas.xmlsoap.org/soap/encoding/'})
                                     ->type('soapenc:string')
                                     ->value($EXP)
                       );
    
    # communicating to the WebService
    $result = $soap_cust->findCustomerRefs($param)->result;
    unless($result) {
      die "#- Error: No customer ObjectID found for name '${CUSTOM_NAME}' !\n";
    }
    unless(scalar @$result) {
      die "#- Error: No customer ObjectID found for Name '${CUSTOM_NAME}' !\n";
    }
    if((scalar @$result) != 1) {
      foreach my $custom ( sort { $a->{name} cmp $b->{name}} @$result ) {
        my $OID  = $custom->{id};
        my $NAME = $custom->{name};
        print "#- Customer ${OID} = '${NAME}'\n";
      }
      die "#- Error: More than one customer found for name '${CUSTOM_NAME}' !\n";
    }
    
    $CUSTOM_OID  = $result->[0]->{id};
    $CUSTOM_NAME = $result->[0]->{name};
    print "#: script ${CUSTOM_OID} = '${CUSTOM_NAME}'\n" unless $MODE_QUIET;
  } elsif($CUSTOM_OID) {
    $param = SOAP::Data->name('self')
                       ->attr({'xmlns:loc'=> 'http://locality.opsware.com'})
                       ->type('loc:CustomerRef')
                       ->value(
                           \SOAP::Data->name('id')
                                      ->value($CUSTOM_OID)
                       );
    $result = $soap_cust->getCustomerVO($param)->result;
    unless($result) {
      die "#- Error: No customer found for ObjectID '${CUSTOM_OID}' !\n";
    }
    $CUSTOM_NAME = $result->{name};
    if($MODE_DETAIL) {
      print Dumper $result;
      exit 0;
    }
  }
}

####################################################################### }}} 1
## -detail handling ################################################### {{{ 1

if($MODE_GETOID) {
  print $CUSTOM_OID;
  if( -t STDOUT) { print "\n"; }
  exit 0;
}

if($MODE_DETAIL) {

  $param = SOAP::Data->name('self')
                     ->attr({'xmlns:loc'=>'http://locality.opsware.com' })
                     ->type('loc:CustomerRef')
                     ->value(
                         \SOAP::Data->name('id')
                                    ->value($CUSTOM_OID)
                     );
  $result = $soap_cust->getCustomerVO($param);
  print Dumper $result;
  exit 0;
}
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
    die "#- Error: No server found for name '${SERVER_MSG}' !\n";
  }
  unless(scalar @$result) {
    die "#- Error: No server found for name '${SERVER_MSG}' !\n";
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
    die "#- Error: More than one server found for name '${SERVER_MSG}' !\n";
  }
  
}


####################################################################### }}} 1
## MAIN - getServerVO  - MODE_OID==1 ################################## {{{ 1

# That part is used when we translate
# HPSA ObjectID --into--> name,HostName,IP...
#if($MODE_OID) {
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
    die "#- Error: No server found for ObjectID '${SERVER_MSG}' !\n";
  }
  push @AOID,$SERVER_OID;
  if($MODE_DUMP) { 
     print Dumper $result; 
  } else { 
    my $NAME = $result->{name};
    print "#: server ${SERVER_OID} = '${NAME}'\n" if $MODE_OID;
  }
#}

####################################################################### }}} 1
## -get handling ###################################################### {{{ 1


$SERVER_NAME = $result->{name};
$QCUST_NAME  = $result->{customer}->{name};
$QCUST_OID   = $result->{customer}->{id};

print "#: found customer ${QCUST_OID} = '${QCUST_NAME}'\n";
#print Dumper $result->{customer};

####################################################################### }}} 1
## -set handling ###################################################### {{{ 1

if($MODE_SET) {
$param = SOAP::Data->name('self')
                   ->attr({ 'xmlns:ser' => "http://server.opsware.com"})
                   ->type('ser:ServerRef')
                   ->value(
                       \SOAP::Data->name('id')
                                  ->value($SERVER_OID)
                   );
$args = SOAP::Data->name('customer')
                   ->attr({ 'xmlns:loc' => "http://locality.opsware.com"})
                   ->type('loc:CustomerRef')
                   ->value(
                       \SOAP::Data->name('id')
                                  ->value($CUSTOM_OID)
                   );
print "#: Setting Customer to ${CUSTOM_OID} '${CUSTOM_NAME}' .\n";
$result = $soap_server->setCustomer($param,$args)->result;

$result = $soap_server->getServerVO($param)->result;
print "#: Customer is now set to ".$result->{customer}->{id}
     ." '".$result->{customer}->{name}."'\n";
}
####################################################################### }}} 1
