#!/usr/bin/perl
# HPSA-Server - Utility to manage server related HPSA data
# 20160427, Ing. Ondrej DURAS (dury)
# vpc-automation/Examples-Soap/1hpsa-server.pl

## MANUAL ############################################################# {{{ 1

our $VERSION = 2016.110301;
our $MANUAL  = <<__END__;
NAME: HPSA Search Server Utility
FILE: hpsa-server.pl

DESCRIPTION:
  This utility should help to translate
  the server name into HPSA ObjectID at
  any time of the migration process.

USAGE:
  ./hpsa-server -server myserver
  ./hpsa-server -name myserver  -detail
  ./hpsa-server -host myserver.domain
  ./hpsa-server -addr 1.2.3.4 -dump
  ./hpsa-server -oid 12345678
  ./hpsa-server -lab
  ./hpsa-server -name myserver -deactivate -remove
  ./hpsa-server -name myserver -setattr "SNMP_CONTACT" "DC ADM"
  ./hpsa-server -name myserver -oneattr "SNMP_CONTACT" -quiet
  ./hpsa-server -name myserver -remattr "SNMP_CONTACT"
  ./hpsa-server -name myserver -getattr
  ./hpsa-server -name myserver -getattr > backup.txt
  ./hpsa-server -name myserver -backup  > restore.sh
  . restore.sh
  

PARAMETERS:
  -name    - Name of the server
  -host    - HostName of the server
  -addr    - IP address of the server
  -oid     - HPSA ObjectID
  -server  - Name/HostName/IP/OID of the server
  -detail  - Provides Server Object Values
  -dump    - Lists PERL internal structure/s
  -quiet   - suppress standard output   
  -lab     - provides a list of our
             servers for testing
  -deact   - deactivates a server in HPSA
  -remove  - removes a server from HPSA
  -setattr - sets a particular custom attribute
  -remattr - removes a particular custom attribute
  -getattr - list all Custom Attributes into text
  -oneattr - provide a value of one custom attribute
  -backup  - list all Custom Attributes into script
  -getoid  - Provides HPSA Object ID only (for scripts)
  -timeout - timeout of SOAP session in seconds

RE-ACTIVATION:
  
  REM Registers Windows HW\&SW onto HPSA
  "%ProgramFiles%\\Opsware\\agent\\pylibs\\cog\\bs_hardware.bat"
  "%ProgramFiles%\\Opsware\\agent\\pylibs\\cog\\bs_software.bat"

  # Registers Linux HW\&SW onto HPSA
  /opt/opsware/agent/pylibs/cog/bs_hardware # <<<
  /opt/opsware/agent/pylibs/cog/bs_software # <<<

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
#use SOAP::Lite +trace=>'debug';
use PWA;

# Prototypes
sub warn(;$);                               #<#  2/8
sub die(;$$);                               #<#
sub printServerVO($);

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
our $SEARCH_NAME = "";
our $SEARCH_HOST = "";
our $SEARCH_ADDR = "";
our $SEARCH_ALL  = "";
our $SEARCH_OID  = "";
our $SEARCH_BACK = ""; # backup of string
our $CUSTOM_ATTR = ""; 
our $CUSTOM_VALUE= "";

our $MODE_REF    = 0;  # set for NAME,HOST,ADDR,ALL  - findServerRefs
our $MODE_OID    = 0;  # set for OID                 - getServerVO
our $MODE_HOTOUT = 2;  # 0=OFF 1=ON 2=TBD caching STDOUT  -hot / -no-hot  #<#  3/8
our $MODE_TIMEOUT= 0;  # 0=OFF 0>... timeout in seconds                   #<#
our $MODE_LAB    = 0;  # for development - do not care
our $MODE_DUMP   = 0;  # Provides whole retrieved data
our $MODE_QUIET  = 0;  # may be for server deletion .. ? or troubleshooting
our $MODE_DETAIL = 0;  # dot-nice output of usefull server details
our $MODE_DEACT  = 0;  # deactivates a server in HPSA
our $MODE_REMOVE = 0;  # deletes a server from HPSA
our $MODE_BACKUP = 0;  # lists all Custom Attributes into script
our $MODE_GETATTR= 0;  # lists all Custom Attributes into text STDOUT
our $MODE_SETATTR= 0;  # sets a particular CUSTOM_ATTR by CUSTOM_VALUE
our $MODE_REMATTR= 0;  # removes a particular CUSTOM_ATTR
our $MODE_ONEATTR= 0;  # retrieves a value of one particular CUSTOM_ATTR
our $MODE_GETOID = 0;  # provides a HPSA_ObjectID of the server (for script purposes)
our $MODE_COLOR  = 0;  # not important for now
our $EXP         = ""; # EXPression composed at many points within the script
our @AOID        = (); # List of HPSA ObjectIDs found in search

# collect parameters from the command-line
while(my $ARGX = shift @ARGV) {
  if($ARGX =~ /^-+hot/)     { $MODE_HOTOUT = 1;     next; }  # --hot               #<#  4/8
  if($ARGX =~ /^-+no-?hot/) { $MODE_HOTOUT = 0;     next; }  # --no-hot            #<#
  if($ARGX =~ /^-+tim/)     { $MODE_TIMEOUT= shift; next; }  # --timeout <second>  #<#
  if($ARGX =~ /^-+no-?tim/) { $MODE_TIMEOUT= 0;     next; }  # --no-timeout        #<#
  if($ARGX =~ /^-+dump/)    { $MODE_DUMP   = 1;           next; }  # --dump
  if($ARGX =~ /^-+det/)     { $MODE_DETAIL = 1;           next; }  # --detail
  if($ARGX =~ /^-+back/)    { $MODE_BACKUP = 1;           next; }  # --backup
  if($ARGX =~ /^-+getat/)   { $MODE_GETATTR= 1;           next; }  # --getattr
  if($ARGX =~ /^-+oneat/)   { $MODE_ONEATTR= 1;                    # --oneattr
                              $CUSTOM_ATTR = shift @ARGV; next; }
  if($ARGX =~ /^-+remat/)   { $MODE_REMATTR= 1;                    # --remattr
                              $CUSTOM_ATTR = shift @ARGV; next; }
  if($ARGX =~ /^-+setat/)   { $MODE_SETATTR= 1;                    # --setattr
                              $CUSTOM_ATTR = shift @ARGV; 
                              $CUSTOM_VALUE= shift @ARGV; next; }  # --getoid
  if($ARGX =~ /^-+getoi/)   { $MODE_GETOID = 1; 
                              $MODE_QUIET  = 1;           next; }
  if($ARGX =~ /^-+q/)       { $MODE_QUIET  = 1;           next; }  # --quiet
  if($ARGX =~ /^-+lab/)     { $MODE_LAB    = 1;           next; }  # --lab
  if($ARGX =~ /^-+deact/)   { $MODE_DEACT  = 1;           next; }  # --deactivate
  if($ARGX =~ /^-+remove/)  { $MODE_REMOVE = 1;           next; }  # --remove
  if($ARGX =~ /^-+n/)       { $SEARCH_NAME = shift @ARGV; $SEARCH_BACK = "-name ".$SEARCH_NAME;  next; }
  if($ARGX =~ /^-+h/)       { $SEARCH_HOST = shift @ARGV; $SEARCH_BACK = "-host ".$SEARCH_HOST;  next; }
  if($ARGX =~ /^-+[ai]/)    { $SEARCH_ADDR = shift @ARGV; $SEARCH_BACK = "-addr ".$SEARCH_ADDR;  next; }
  if($ARGX =~ /^-+s/)       { $SEARCH_ALL  = shift @ARGV; $SEARCH_BACK = "-server ".$SEARCH_ALL; next; }
  if($ARGX =~ /^-+oid/)     { $SEARCH_OID  = shift @ARGV; $SEARCH_BACK = "-oid ".$SEARCH_OID;    next; }
  die "#- Error: wrong argument '${ARGX}' !\n";    #<# 5/8
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
  # print "#: proxy '${PROXY}'\n";
}
debug "4","PROXY = '${PROXY}'";  

# Entered parameters translated to mode of script operation
if($SEARCH_NAME or $SEARCH_HOST 
or $SEARCH_ADDR or $SEARCH_ALL) {
  $MODE_REF = 1;
}
if($MODE_LAB) {
  $MODE_REF = 1;
}
if($SEARCH_OID) {
  $MODE_OID = 1;
}

# STOP if something necessary is missing.
die "#- Error: arguments required !\n"
  unless ( $MODE_REF or $MODE_OID );
die "#- Error: missing HPSA login or password !\n"
  unless ( $USER and $PASS );
die "#- Error: have a look into HPSA references !\n"
  unless ( $PROXY and $URI );

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
## SOAP Initiation #################################################### {{{ 1


sub SOAP::Transport::HTTP::Client::get_basic_credentials {
  return $USER => $PASS;
}

our $soap_server;                                                           #<#  8/8
if($MODE_TIMEOUT) {                                                         #<#
  $soap_server = SOAP::Lite                                                 #<#
     ->uri($URI.'server')                                                   #<#
     ->proxy($PROXY.'server/ServerService?wsdl', timeout => $MODE_TIMEOUT); #<#
  print "#: using proxy = ${PROXY} (timeout=${MODE_TIMEOUT}sec)\n";         #<#
} else {                                                                    #<#
  $soap_server = SOAP::Lite                                                 #<#
     ->uri($URI.'server')                                                   #<#
     ->proxy($PROXY.'server/ServerService?wsdl');                           #<#
  print "#: using proxy = ${PROXY}\n";                                      #<#
}                                                                           #<#

our $expression;
our $result;
our $param;
our $allpar;
our $self;

####################################################################### }}} 1
## MAIN - findServerRefs - MODE_REF==1 ################################ {{{ 1

# That part is used when we translate 
# name/fqdn/something --into--> HPSA_ObjectID
if($MODE_REF) {

  # Builds a EXPression for query
  if($MODE_LAB) {
    $EXP = '((ServerVO.hostName like "engreq348-0132%") | '
         . '(ServerVO.hostName  like "engreq296-0194%") | '
         . '(ServerVO.hostName  like "engreq298-0195%") | '
         . '(ServerVO.hostName  like "engreq297-0192%") | '
         . '(ServerVO.hostName  like "engreq297-0105%") | '
         . '(ServerVO.hostName  like "engreq309-0176%"))';
  } elsif($SEARCH_NAME) {
    $EXP = 'ServerVO.name like "'.$SEARCH_NAME.'"';
  } elsif($SEARCH_HOST) {
    $EXP = 'ServerVO.HostName like "'.$SEARCH_HOST.'"';
  } elsif($SEARCH_ADDR) {
    $EXP = '((device_interface_ip = "'.$SEARCH_ADDR.'") | '
         . '(device_management_ip = "'.$SEARCH_ADDR.'"))';
  } elsif($SEARCH_ALL)  {
    $EXP = '((ServerVO.name like "'.$SEARCH_ALL.'") | '
         . '(ServerVO.hostName like "'.$SEARCH_ALL.'") | '
         . '(device_interface_ip = "'.$SEARCH_ALL.'") | '
         . '(device_management_ip = "'.$SEARCH_ALL.'"))';
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
    my $OID  = $server->{id}; 
    my $NAME = $server->{name};
    push @AOID,$OID;
    unless($MODE_QUIET or $MODE_DETAIL or $MODE_DUMP) {
      print "#: server ${OID} = ${NAME}\n";
    }
  }
}

####################################################################### }}} 1
## MAIN - getServerVOs - MODE_REF==1 ################################## {{{ 1

# That part is used to display details of
# servers they have been found
if($MODE_REF and (scalar @AOID) and $MODE_DETAIL) {

  my @data = ();
  foreach my $OID (@AOID) {
     
    my $object = SOAP::Data->name('item')
                           ->type('ser:ServerRef')
                           ->value(
                              \SOAP::Data->name('id')
                                         ->type('long')
                                         ->value($OID)
                              );
    push @data,$object;
  }
  
  my $selves = SOAP::Data->name('selves')
                         ->attr({ 'xmlns:ser' => 'http://server.opsware.com'})
                         ->type('ser:ArrayOfServerRef')
                         ->value( 
                             \SOAP::Data->name("elements" => @data) 
                           );

  $result = $soap_server->getServerVOs($selves)->result;
  unless($result) {
    die "#- Error: None server/s details found !\n";
  }
  foreach my $server ( @$result ) {
    printServerVO($server); 
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
                                    ->value($SEARCH_OID)
                     );
  $result = $soap_server->getServerVO($param)->result;
  unless($result) {
    die "#- Error: None server found (${SEARCH_OID}) !\n";
  }
  push @AOID,$SEARCH_OID;
  printServerVO($result);
}

####################################################################### }}} 1
## sub printServerVO($result) ######################################### {{{ 1

#FUNCTION:
#  printdot($NAME,$VALUE;$DOTLENGTH);
#PARAMETERS:
#  $NAME  - string displayed on the left side of output
#  $VALUE - string/value displayed on the right side
#  $DOTLENGTH - default 50 - number of dots
sub printdot($$;$) {
  my($NAME,$VALUE,$DOTLENGTH) = @_;
           #123456789.123456789.123456789.'
  my $DOTS='........................';
  my $LEN = length($DOTS);
  if($DOTLENGTH) { $LEN=$DOTLENGTH; };
  $LEN = $LEN - length($NAME);
  if($LEN < 3) { $LEN=3; }
  my $OUT = "";
  if($MODE_COLOR) {
    if($VALUE =~/\!$/) {
      $OUT = "\033[0;31m${NAME} \033[0;35m"
           . substr($DOTS,0,$LEN)
           . "\033[1;31m ${VALUE}\033[m\n";
    } else {
      $OUT = "\033[0;32m${NAME} \033[0;36m"
           . substr($DOTS,0,$LEN)
           . "\033[1;32m ${VALUE}\033[m\n";
    }
  } else {
    $OUT = "${NAME} ".substr($DOTS,0,$LEN)." ${VALUE}\n";
  }
  print $OUT;
}

sub printServerVO($) {
  my $result = shift;

  if($MODE_QUIET) {
    return;
  }
  if($MODE_DUMP) {
    print Dumper $result;
    return;
  }
  if($MODE_DETAIL) {
    printdot "HPSA ObjectID" ,$result->{ref}->{id};
    printdot "Management IP" ,$result->{managementIP};
    printdot "Server Name"   ,$result->{name};
    printdot "OS Version"    ,$result->{osVersion};
    printdot "Customer"      ,$result->{customer}->{name};
    print    "\n";
    return;
  }
  print "#; "
      . $result->{ref}->{id}    ." ; "
      . $result->{managementIP} ." ; "
      . $result->{name}         ." ; "
      . $result->{osVersion}    ." ; "
      . $result->{customer}->{name} ."\n";

}

####################################################################### }}} 1
## -getoid ############################################################ {{{ 1

if($MODE_GETOID) {
  unless((scalar @AOID) == 1) {
    die "#- Exactly one server (valid OID) must be found\n";
  }
  my $OID=$AOID[0];
  print $OID;
  if( -t STDOUT ) { print "\n"; }
}

####################################################################### }}} 1
## -deactivate ######################################################## {{{ 1

if($MODE_DEACT) {
  unless((scalar @AOID) == 1) {
    die "#- Exactly one server (valid OID) must be found\n"
      . "#- to allow the server deactivation !\n";
  }
  my $OID=$AOID[0];
  # ServerService.decommission()  - deactivation 
  # ServerService.remove()        - removal
  $param = SOAP::Data->name('self')
                     ->attr({ 'xmlns:ser' => 'http://server.opsware.com'})
                     ->type('ser:ServerRef')
                     ->value(
                         \SOAP::Data->name('id')
                                    ->type('long')
                                    ->value($OID)
                     );

  $soap_server->decommission($param)->result;
  print "#: Server OID=${OID} deactivated from HPSA mesh.\n";
}

####################################################################### }}} 1
## -remove ############################################################ {{{ 1

if($MODE_REMOVE) {
  unless((scalar @AOID) == 1) {
    die "#- Exactly one server (valid OID) must be found\n"
      . "#- to allow the server deactivation !\n";
  }
  my $OID=$AOID[0];
  # ServerService.decommission()  - deactivation 
  # ServerService.remove()        - removal
  $param = SOAP::Data->name('self')
                     ->attr({ 'xmlns:ser' => 'http://server.opsware.com'})
                     ->type('ser:ServerRef')
                     ->value(
                         \SOAP::Data->name('id')
                                    ->type('long')
                                    ->value($OID)
                     );

  $soap_server->remove($param)->result;
  print "#: Server OID=${OID} removed from HPSA mesh.\n";
}

####################################################################### }}} 1
## -getattr / -backup ################################################# {{{ 1

if($MODE_GETATTR or $MODE_BACKUP) {
  unless((scalar @AOID) == 1) {
    die "#- Exactly one server (valid OID) must be found\n"
      . "#- to allow work with the custom attributes !\n";
  }
  my $OID=$AOID[0];
  # ServerService.getCustAttrKeys()
  # ... ServerService.getCustAttr()

  $self = SOAP::Data->name('self')
                     ->attr({ 'xmlns:ser' => 'http://server.opsware.com'})
                     ->type('ser:ServerRef')
                     ->value(
                         \SOAP::Data->name('id')
                                    ->type('long')
                                    ->value($OID)
                     );
  $allpar = $soap_server->getCustAttrKeys($self)->result;
  if($MODE_DUMP) { print "getCustAttrKeys\n"; print Dumper $allpar; }

  my $scope = SOAP::Data->name('scope')
                        ->type('boolean')
                        ->value(1);

  my $SCRIPT = $0; $SCRIPT =~ s/^.*(\\|\/)//;

  my %HCUST=();
  foreach my $PAR ( sort @$allpar ) {
    $param = SOAP::Data->name('key')
                       ->type('string')
                       ->value($PAR);

    $result = $soap_server->getCustAttr($self,$param,$scope)->result;
    if($MODE_DUMP) { print $PAR."\n"; print Dumper $result; }
    $HCUST{$PAR}=$result;
    if($MODE_BACKUP) {
      my $value = $result;
      $value =~ s/"/\\"/g;
      print "${SCRIPT} ${SEARCH_BACK} -setattr \"${PAR}\" \"".$value."\"\n";
    } else {
      print $PAR." = '".$result."'\n";
    } 
  }
}

####################################################################### }}} 1
## -oneattr ########################################################### {{{ 1

if($MODE_ONEATTR) {
  unless((scalar @AOID) == 1) {
    die "#- Exactly one server (valid OID) must be found\n"
      . "#- to allow work with the custom attributes !\n";
  }
  my $OID=$AOID[0];
  $self = SOAP::Data->name('self')
                    ->attr({ 'xmlns:ser' => 'http://server.opsware.com'})
                    ->type('ser:ServerRef')
                    ->value(
                      \SOAP::Data->name('id')
                                 ->type('long')
                                 ->value($OID)
                    );
  my $key   = SOAP::Data->name('key')
                        ->type('string')
                        ->value($CUSTOM_ATTR);

  my $scope = SOAP::Data->name('scope')
                        ->type('boolean')
                        ->value(0);

  $result = $soap_server->getCustAttr($self,$key,$scope)->result;
  if($MODE_DUMP) { print Dumper $result; }
  print $result;
  if( -t STDOUT ) { print "\n"; }

}

####################################################################### }}} 1
## -setattr ########################################################### {{{ 1

if($MODE_SETATTR) {
  unless((scalar @AOID) == 1) {
    die "#- Exactly one server (valid OID) must be found\n"
      . "#- to allow work with the custom attributes !\n";
  }
  my $OID=$AOID[0];
  $self = SOAP::Data->name('self')
                    ->attr({ 'xmlns:ser' => 'http://server.opsware.com'})
                    ->type('ser:ServerRef')
                    ->value(
                      \SOAP::Data->name('id')
                                 ->type('long')
                                 ->value($OID)
                    );
  my $key   = SOAP::Data->name('key')
                        ->type('string')
                        ->value($CUSTOM_ATTR);
  my $value = SOAP::Data->name('value')
                        ->type('string')
                        ->value($CUSTOM_VALUE);
  $result = $soap_server->setCustAttr($self,$key,$value)->result;
  if($MODE_DUMP) { print Dumper $result; }
}

####################################################################### }}} 1
## -remattr ########################################################### {{{ 1

if($MODE_REMATTR) {
  unless((scalar @AOID) == 1) {
    die "#- Exactly one server (valid OID) must be found\n"
      . "#- to allow work with the custom attributes !\n";
  }
  my $OID=$AOID[0];
  $self = SOAP::Data->name('self')
                    ->attr({ 'xmlns:ser' => 'http://server.opsware.com'})
                    ->type('ser:ServerRef')
                    ->value(
                      \SOAP::Data->name('id')
                                 ->type('long')
                                 ->value($OID)
                    );
  my $key   = SOAP::Data->name('key')
                        ->type('string')
                        ->value($CUSTOM_ATTR);
  $result = $soap_server->removeCustAttr($self,$key)->result;
  if($MODE_DUMP) { print Dumper $result; }

}

####################################################################### }}} 1
# --- end ---

