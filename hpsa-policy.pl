#!/usr/bin/perl
# HPSA-Policy - HPSA Policy Management Utility
# 20160428, Ing. Ondrej DURAS (dury)

## MANUAL ############################################################# {{{ 1

our $VERSION = 2016.081502;
our $MANUAL  = <<__END__;
NAME: HPSA Software Policy Management Utility
FILE: hpsa-policy.pl

DESCRIPTION:
  Allows to manage HPSA software policies onto server.
  Script works in one of a few modes.
  - list all software policies found on HPSA MESH
  - list policies applicable onto server (platform)
  - list applied/attached software policies onto server
  - apply & remediate software policy onto server
  - install package/s onto server
  - uninstall package/s from the server
  - remove policy from the server

USAGE:
  ./hpsa-policy -list "linux%"
  ./hpsa-policy -detail "linux patch%"
  ./hpsa-policy -compliant "linux" -on 1234567
  ./hpsa-policy -compliant 1234 -on myserver1
  ./hpsa-policy -compliant "%" -on myserver1
  ./hpsa-policy -compliant "%" -platform "%linux%"
  ./hpsa-policy -is "linux" -on 1234567
  ./hpsa-policy -policies -on myserver1
  ./hpsa-policy -attach "linux patch%" -on myserver1
  ./hpsa-policy -attach 1234 -on myserver1 -force
  ./hpsa-policy -install "linux patch%" -on myserver1
  ./hpsa-policy -uninstall "linux patch%" -on myserver1
  ./hpsa-policy -remove 1234 -on 1234567 -timeout 30
  ./hpsa-policy -remove 1234 -on 1234567 -force

PARAMETERS:
  -list      - complete or filtered list of software policies
  -getoid    - provides ObjectID of ONE Software Policy for scipts
  -detail    - details related to ONE particular software policy 
  -compliant - filtered list of software policies compliant to server
  -platform  - particular platform of compliancy (replaces a server)
  -is        - filtered list of software policies applied already on server
  -on        - ONE server defined by Hostname, HPSA Name or Object ID
  -name      - HPSA name of the affected server
  -oid       - HPSA ObjectID of affected server
  -host      - HostName of the affected server
  -addr      - IP address of the server
  -server    - any of above server search related (it's the same than -on)
  -policies  - list of all software policies applied on the server
  -attach    - adds the software policy to a server
  -install   - installs software policy related packages onto server
  -uninstall - uninstall software policy related packes from server
  -remove    - removes ONE whole software policy from the server
  -force     - does not ask in case of intrusive action (install/attach)
  -timeout   - timeout of SOAP session in seconds

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
our $MODE_REF    = 0;  # 1= when findServerRefs is used
our $MODE_OID    = 0;  # 1= when getServerVO is used to confirm existence of the server

# modes of the script operation
our $MODE_LIST   = 0;  # listing all/filtered policies
our $MODE_GETOID = 0;  # provides one policy ObjectID
our $MODE_DETAIL = 0;  # list particular ONE policy in detail
our $MODE_CHECK  = 0;  # check whether a a policy is compliant to server
our $MODE_SHOW   = 0;  # shows a (filtered) list of attached policies
our $MODE_ATTACH = 0;  # attach and remediate a policy onto server
our $MODE_INST   = 0;  # install software - troubleshooting purposes only
our $MODE_UNIN   = 0;  # uninstall software - troubleshooting purposes only
our $MODE_REMOVE = 0;  # remove policy from from the server (server from policy in practice)
our $MODE_FORCE  = 0;  # causes the intrusive actions will be proceeded without confirmation

# SOAP function related attributes
our $SERVER_NAME = ""; # HPSA name of the server %
our $SERVER_HOST = ""; # FQDN of the server
our $SERVER_ADDR = ""; # Management IP address of the server
our $SERVER_OID  = ""; # HPSA ObjectID of the server
our $SERVER_ALL  = ""; # any of above server related

our $PROCESS_OID = 0;  # JobID to track the Job
our $POLICY_NAME = ""; # HPSA Software Policy Name or Regular expression
our $POLICY_OID  = ""; # HPSA unique Object ID indentifing ONE Software Policy
our $SEPLAT_NAME = ""; # HPSA Server Platform Name / %like%
our $SEPLAT_OID  = ""; # HPSA Server Platform ObjectID
our $EXP = "";         # expression to 'self' in get<something>VO
our @AOID        = (); # list of HPSA ObjectIDs /by findServerRefs

our @hJobStatus = qw(
  ABORTED ACTIVE CANCELED DELETED FAILURE
  PENDING SUCCESS UNKNOWN WARNING TAMPERED STALE
  BLOCKED RECURRING EXPIRED ZOMBIE TERMINATING
  TERMINATED
);
sub trackJob($$);      # Tracks a Job

# collect parameters from the command-line
while(my $ARGX = shift @ARGV) {
  if($ARGX =~ /^-+hot/)     { $MODE_HOTOUT = 1;     next; }  # --hot               #<#  4/8
  if($ARGX =~ /^-+no-?hot/) { $MODE_HOTOUT = 0;     next; }  # --no-hot            #<#
  if($ARGX =~ /^-+tim/)     { $MODE_TIMEOUT= shift; next; }  # --timeout <second>  #<#
  if($ARGX =~ /^-+no-?tim/) { $MODE_TIMEOUT= 0;     next; }  # --no-timeout        #<#
  if($ARGX =~ /^-+dump/)      { $MODE_DUMP = 1; next; }
  if($ARGX =~ /^-+f(orce)?/)  { $MODE_FORCE= 1; next; }
  if($ARGX =~ /^-+list/)      { $MODE_LIST = 1; $POLICY_NAME = shift @ARGV; next; }
  if($ARGX =~ /^-+getoid/)    { $MODE_GETOID=1; $POLICY_NAME = shift @ARGV; next; }
  if($ARGX =~ /^-+all/)       { $MODE_LIST = 1; $POLICY_NAME = '%';         next; }
  if($ARGX =~ /^-+det/)       { $MODE_DETAIL=1; $POLICY_NAME = shift @ARGV; next; }
  if($ARGX =~ /^-+com/)       { $MODE_CHECK= 1; $POLICY_NAME = shift @ARGV; next; }
  if($ARGX =~ /^-+(is|show)$/){ $MODE_SHOW = 1; $POLICY_NAME = shift @ARGV; next; }
  if($ARGX =~ /^-+whatis/)    { $MODE_SHOW = 1; $POLICY_NAME = '%';         next; }
  if($ARGX =~ /^-+pol/)       { $MODE_SHOW = 1; $POLICY_NAME = '%';         next; }
  if($ARGX =~ /^-+showall/)   { $MODE_SHOW = 1; $POLICY_NAME = '%';         next; }
  if($ARGX =~ /^-+attach/)    { $MODE_ATTACH=1; $POLICY_NAME = shift @ARGV; next; }
  if($ARGX =~ /^-+ins/)       { $MODE_INST = 1; $POLICY_NAME = shift @ARGV; next; }
  if($ARGX =~ /^-+unins/)     { $MODE_UNIN = 1; $POLICY_NAME = shift @ARGV; next; }
  if($ARGX =~ /^-+remove/)    { $MODE_REMOVE=1; $POLICY_NAME = shift @ARGV; next; }
  if($ARGX =~ /^-+delete/)    { $MODE_REMOVE=1; $POLICY_NAME = shift @ARGV; next; }
  if($ARGX =~ /^-+plat/)      { $SEPLAT_NAME = shift @ARGV; next; }
  if($ARGX =~ /^-+name/)      { $SERVER_NAME = shift @ARGV; $MODE_REF = 1; next; }
  if($ARGX =~ /^-+host/)      { $SERVER_HOST = shift @ARGV; $MODE_REF = 1; next; }
  if($ARGX =~ /^-+(addr|ip)$/){ $SERVER_ADDR = shift @ARGV; $MODE_REF = 1; next; }
  if($ARGX =~ /^-+oid$/)      { $SERVER_OID  = shift @ARGV; $MODE_OID = 1; next; }
  if($ARGX =~ /^-+server/)    { $SERVER_ALL  = shift @ARGV; $MODE_REF = 1; next; }
  if($ARGX =~ /^-+on/)        { $SERVER_ALL  = shift @ARGV; $MODE_REF = 1; next; }
  die "#- Error: wrong argument '${ARGX}' !\n";     #<#  5/8
}


if($MODE_HOTOUT == 2) {                        #<#  6/8
  unless( -t STDOUT) { $MODE_HOTOUT = 1; }     #<#
  else               { $MODE_HOTOUT = 0; }     #<#
}                                              #<#
if($MODE_HOTOUT) {                             #<#
  # http://perl.plover.com/FAQs/Buffering.html #<#
  select((select(STDOUT), $|=1)[0]);           #<#
}                                              #<#


if($MODE_LIST and $SERVER_NAME) { 
   $MODE_LIST = 0; $MODE_SHOW = 1; 
}
if($POLICY_NAME =~ /^[0-9]+$/) {
   $POLICY_OID  = $POLICY_NAME;
   $POLICY_NAME = "";
}
if($SERVER_ALL  =~ /^[0-9]+$/) {
   $SERVER_OID  = $SERVER_ALL;
   $SERVER_ALL  = "";
   $MODE_OID    = 1;
   $MODE_REF    = 0;
}
if($SEPLAT_NAME =~ /^[0-9]+$/) {
   $SEPLAT_OID  = $SEPLAT_NAME;
   $SEPLAT_NAME = "";
}

# PROXY  settings
unless($PROXY =~ /^https?:\/\// ) {
  $PROXY = "https://".$PROXY."/osapi/com/opsware/";
  debug "4","PROXY '${PROXY}'";
}

# STOP if something necessary is missing.
die "#- Error: What should I do (-list/-detail/-check/-attach/-remove...) ?\n"
  unless ( $MODE_LIST   or $MODE_GETOID or $MODE_DETAIL 
        or $MODE_CHECK  or $MODE_SHOW   or $MODE_ATTACH 
        or $MODE_INST   or $MODE_UNIN   or $MODE_REMOVE );

die "#- Error: arguments required !\n"
  unless ( $POLICY_NAME or $POLICY_OID );
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

our $soap_server;                                                                        #<#  8/8
    if($MODE_TIMEOUT) {                                                                  #<#
      $soap_server = SOAP::Lite                                                          #<#
         ->uri($URI.'server')                                                            #<#
         ->proxy($PROXY.'server/ServerService?wsdl', timeout => $MODE_TIMEOUT);          #<#
    } else {                                                                             #<#
      $soap_server = SOAP::Lite                                                          #<#
         ->uri($URI.'server')                                                            #<#
         ->proxy($PROXY.'server/ServerService?wsdl');                                    #<#
    }                                                                                    #<#

our $soap_job;                                                                           #<#
    if($MODE_TIMEOUT) {                                                                  #<#
      $soap_job = SOAP::Lite                                                             #<#
         ->uri($URI.'job')                                                               #<#
         ->proxy($PROXY.'job/JobService?wsdl', timeout => $MODE_TIMEOUT);                #<#
    } else {                                                                             #<#
      $soap_job = SOAP::Lite                                                             #<#
         ->uri($URI.'job')                                                               #<#
         ->proxy($PROXY.'job/JobService?wsdl');                                          #<#
    }                                                                                    #<#

our $soap_policy;                                                                        #<#
    if($MODE_TIMEOUT) {                                                                  #<#
      $soap_policy = SOAP::Lite                                                          #<#
         ->uri($URI.'swmgmt')                                                            #<#
         ->proxy($PROXY.'swmgmt/SoftwarePolicyService?wsdl', timeout => $MODE_TIMEOUT);  #<#
    } else {                                                                             #<#
      $soap_policy = SOAP::Lite                                                          #<#
         ->uri($URI.'swmgmt')                                                            #<#
         ->proxy($PROXY.'swmgmt/SoftwarePolicyService?wsdl');                            #<#
    }                                                                                    #<#

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
  if($POLICY_NAME) {
    $EXP = 'SoftwarePolicyVO.name like "'.$POLICY_NAME.'"';
  } elsif($POLICY_OID) {
    $EXP = 'software_policy_folder_id = '.$POLICY_OID; #< that's a temporary bullshit
  }

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
  $result = $soap_policy->findSoftwarePolicyRefs($param)->result;
  unless(scalar @$result) {
    die "#- Error: None policy has been found !\n";
  }
  if($MODE_GETOID) {
    unless((scalar @$result) == 1) {
      die "#- Error: More than one policy has been found !\n";
    }
    print @$result[0]->{id};
    if( -t STDOUT) { print "\n"; }
    exit 0;
  }
  if($MODE_DUMP) {
    print Dumper $result;
  } else {
    foreach my $policy ( sort { $a->{name} cmp $b->{name}} @$result ) {
      my $OID  = $policy->{id};
      my $NAME = $policy->{name};
      print "${OID} = '${NAME}'\n";
    }
  }
  exit 0;
 
}

####################################################################### }}} 1
## ONE server name & oid ONLY ! ####################################### {{{ 1

#FUNCTION:
#  (SERVER_NAME,$SERVER_OID)=getServerRef(;$POLICY_NAME,$POLICY_OID);
#PARAMETERS:
#  $SERVER_NAME - HPSA name of the Server or %LIKE% string including a part of the name
#  $SERVER_OID  - Unique ObjectID, identifying the Server
#DESCRIPTION:
#  Returns a single one pair of HPSA Server Name & HPSA ObjectID.
#  If none found, or if more than one Server found, the
#  function fails and exists the script with the error message.

sub getServerRef(;$$) {
  my ($XSERVER_NAME,$XSERVER_OID) = @_;
  # $XSERVER_NAME = $SERVER_NAME unless defined($XSERVER_NAME); 
  # $XSERVER_OID  = $SERVER_OID  unless defined($XSERVER_OID);
  # my $param;


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
    print "#: EXP = ${EXP}\n";
    
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
    $SERVER_NAME = $result->{name};
    push @AOID,$SERVER_OID;
    if($MODE_DUMP) { 
       print Dumper $result; 
    } else { 
      print "#: server ${SERVER_OID} = ${SERVER_NAME}\n";
    }
  }
  
  ####################################################################### }}} 1


  return ($SERVER_NAME,$SERVER_OID);
}

#FUNCTION:
#  $PlatformID = getPlatformID($SERVER_OID);
#PARAMETERS:
#  $PlatformID - Unique HPSA Platform ObjectID
#  $SERVER_OID - HPSA Server Object ID
#DESCRIPTION:
#  Gets the server's Platform ID for Policies
sub getPlatformID(;$) {
  my $XSERVER_OID = shift;
  $XSERVER_OID = $SERVER_OID unless $XSERVER_OID;
  unless($XSERVER_OID =~ /^[0-9]+$/) { return 0; }
  if($SEPLAT_OID) { return $SEPLAT_OID; }
  
  my $param = SOAP::Data->name('self')
                        ->attr({"xmlns:ser" => "http://server.opsware.com"})
                        ->type('ser:ServerRef')
                        ->value(
                            \SOAP::Data->name('id')
                                       ->type('long')
                                       ->value($XSERVER_OID)
                          );
    $result = $soap_server->getServerVO($param)->result;
    unless($result) { return 0; }
    $SEPLAT_OID = $result->{platform}->{id};
    return $SEPLAT_OID;     
}
 
#getServerRef($SERVER_NAME,$SERVER_OID);
#getServerRef();


####################################################################### }}} 1
## ONE Software Policy name & OID ONLY ! ############################## {{{ 1

#FUNCTION:
#  (POLICY_NAME,$POLICY_OID)=getSoftwarePolicyRef(;$POLICY_NAME,$POLICY_OID);
#PARAMETERS:
#  $POLICY_NAME       - name of the Software policy or %LIKE% string including a part of the name
#  $POLICY_OID        - Unique ObjectID, identifying the Software POlicy
#DESCRIPTION:
#  Returns a single one pair of Software Policy Name & ObjectID.
#  If none found, or if more than one Software policy found, the
#  function fails and exists the script with the error message.

sub getSoftwarePolicyRef(;$$) {
  my ($XPOLICY_NAME,$XPOLICY_OID) = @_;
  $XPOLICY_NAME = $POLICY_NAME unless defined($XPOLICY_NAME); 
  $XPOLICY_OID  = $POLICY_OID  unless defined($XPOLICY_OID);
  my $param;

  # composing search expression
  if($POLICY_NAME) {
    $EXP = 'SoftwarePolicyVO.name like "'.$XPOLICY_NAME.'"';

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
    $result = $soap_policy->findSoftwarePolicyRefs($param)->result;
    unless($result) {
      die "#- Error: None Software Policy found (name=${POLICY_NAME}). Which ONE to use ???\n";
    }
    if((scalar @$result) != 1) {
      foreach my $policy ( sort { $a->{name} cmp $b->{name}} @$result ) {
        my $OID  = $policy->{id};
        my $NAME = $policy->{name};
        print "#- server ${OID} = '${NAME}'\n";
      }
    die "#- Error: More than one server found. Which ONE to use ???\n";
    }
    $POLICY_OID  = $result->[0]->{id};
    $POLICY_NAME = $result->[0]->{name};


  } elsif($XPOLICY_OID) {
    $param = SOAP::Data->name('self')
                       ->attr({"xmlns:swm" => "http://swmgmt.opsware.com"})
                       ->type('swm:SoftwarePolicyRef')
                       ->value(
                           \SOAP::Data->name('id')
                                      ->type('long')
                                      ->value($XPOLICY_OID)
                         );
    $result = $soap_policy->getSoftwarePolicyVO($param)->result;
    unless($result) {
      die "#- Error: None Software Policy found (oid). Which ONE to use ???\n";
    }
    $POLICY_OID  = $XPOLICY_OID;
    $POLICY_NAME = $result->{name};

  }

  print "#: policy ${POLICY_OID} '${POLICY_NAME}'\n";
  return ($POLICY_NAME,$POLICY_OID);
}

#getSoftwarePolicyRef();
#getSoftwarePolicyRef($POLICY_NAME,$POLICY_OID);

####################################################################### }}} 1
## -detail handling ################################################### {{{ 1

if($MODE_DETAIL) {

  getSoftwarePolicyRef();
  $param = SOAP::Data->name('self')
                     ->attr({'xmlns:swm'=>'http://swmgmt.opsware.com' })
                     ->type('swm:SoftwarePolicyRef')
                     ->value(
                         \SOAP::Data->name('id')
                                    ->value($POLICY_OID)
                     );
  $result = $soap_policy->getSoftwarePolicyVO($param);
  if($MODE_DUMP) { 
    print Dumper $result;
    exit 0;
  }

  #my $item1=$result->{_content}->[0]->[2]->[2]->[2]->[4];
  my $item1 = $result->{_content}->[2]->[0]->[2]->[0]->[2]->[0]->[4];
  my $item2;
  $item2 = $item1->{'softwarePolicyItems'};
  foreach my $item3 ( @$item2 ) {
    my $SPID = $item3->{id};
    my $SPNM = $item3->{name};
    my $SPTP = $item3->{secureResourceTypeName}; 
    $SPTP =~ s/^software_//;
    print "Item ............. ${SPID} = ${SPNM} (${SPTP})\n";
  }
  print "Items ............ ".(scalar @$item2)."\n";

  $item2 = $item1->{'platforms'};
  foreach my $item3 ( @$item2 ) {
    print "Platform ......... ".$item3->{id}." = ".$item3->{name}."\n";
  }
  print "Platforms ........ ".(scalar @$item2)."\n";
  $item2 = $item1->{'associatedSoftwarePolicies'};
  foreach my $item3 ( @$item2 ) {
    print "Associated SP .... ".$item3->{id}." = ".$item3->{name}."\n";
  }
  print "Associated SP .... ".(scalar @$item2)."\n";
  $item2 = $item1->{'associatedServers'};
  my $TOTAL = scalar @$item2;
  my $COUNT = 0;
  if($SERVER_NAME) {
    foreach my $item3 ( @$item2 ) {
      next unless ($item3->{name} =~ /${SERVER_NAME}/);
      print "Assoc. Server .... ".$item3->{id}." = ".$item3->{name}."\n";
      $COUNT++;
    }
  } else { $COUNT = $TOTAL; }
  print "Assoc. Servers ... ${COUNT} / ${TOTAL}\n";
  if(($item1->{description}) and ($item1->{description} =~ /\S/)) {
    print "Description ...... ".($item1->{description})."\n";
  }
  
  print "Folder ........... ".($item1->{folder}->{name})."\n";
  print "Created .......... ".($item1->{createdDate})." by ".($item1->{createdBy})."\n";
  print "Modified ......... ".($item1->{modifiedDate})." by ".($item1->{modifiedBy})."\n";
  print "Log changes ...... ".($item1->{logChange}==1?"yes":"no")."\n";
  print "Locked ........... ".($item1->{locked}==1?"yes":"no")."\n";
  print "Template ......... ".($item1->{template}==1?"yes":"no")."\n";
  print "Life Cycle ....... ".($item1->{lifecycle})."\n";

  print "#- TempMsg: Use a -dump switch at command-line.\n"; 
  
  exit 0;
}

####################################################################### }}} 1
## -compliant handling ################################################ {{{ 1

if($MODE_CHECK) {
  my $EXP = "";
  if($SEPLAT_OID)     { $EXP = "((SoftwarePolicyVO.name like \"${POLICY_NAME}\") \&amp; "
                             . "(software_policy_platform_id = ${SEPLAT_OID}))"; 
                      }
  elsif($SEPLAT_NAME) { $EXP = "((SoftwarePolicyVO.name like \"${POLICY_NAME}\") \&amp; "
                             . "(software_policy_platform_name like \"${SEPLAT_NAME}\"))"; 
                      }
  elsif($SERVER_OID or $SERVER_NAME) {
    getServerRef;
    unless($SERVER_OID and $SERVER_NAME) { 
      die "#- Server '${SERVER_NAME}'($SERVER_OID) not found !\n";
    }
    getPlatformID;
    unless($SEPLAT_OID) {
      die "#- Platform not found !\n";
    }
    $EXP = "((SoftwarePolicyVO.name like \"${POLICY_NAME}\") \&amp; "
         . "(software_policy_platform_id = ${SEPLAT_OID}))";   
  }

  print "#: EXP = '${EXP}'\n";
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
  $result = $soap_policy->findSoftwarePolicyRefs($param)->result;
  unless($result) {
    die "#- Error: None Compliant Software Policy found !\n";
  }
  foreach my $item ( sort { $a->{name} cmp $b->{name} } @$result ) {
    my $SPID = $item->{id};
    my $SPNM = $item->{name};
    print "Software Policy ... ${SPID} = ${SPNM}\n";
  }
  exit;
}

####################################################################### }}} 1
## -is/-whatis handling ############################################### {{{ 1

if($MODE_SHOW) {
  getServerRef;
  unless($SERVER_NAME and $SERVER_OID) {
    die "#- None server found !\n";
  }
  $EXP = "((software_policy_dvc_id = ${SERVER_OID}) \&amp; "
       . "(SoftwarePolicyVO.name like \"${POLICY_NAME}\"))";
 
  print "#: EXP = '${EXP}'\n";
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
  $result = $soap_policy->findSoftwarePolicyRefs($param)->result;
  unless($result) {
    die "#- Error: None Compliant Software Policy found !\n";
  }
  foreach my $item ( sort { $a->{name} cmp $b->{name} } @$result ) {
    my $SPID = $item->{id};
    my $SPNM = $item->{name};
    print "Software Policy ... ${SPID} = ${SPNM}\n";
  }
  exit;
}

####################################################################### }}} 1
## -attach handling ################################################### {{{ 1

if($MODE_ATTACH) {
  getSoftwarePolicyRef;
  unless($POLICY_NAME and $POLICY_OID) {
    die "#- Error: A Software Policy has not been found !\n";
  }
  getServerRef;
  unless($SERVER_NAME and $SERVER_OID) {
    die "#- Error: A Server has not been found !\n";
  }
 
  
  $param = SOAP::Data->name('selves')
                     ->attr({'xmlns:swm'=> "http://swmgmt.opsware.com"})
                     ->type('swm:ArrayOfSoftwarePolicyRef')
                     ->value(
                        \SOAP::Data->name('item')
                                   ->type('swm:SoftwarePolicyRef')
                                   ->value(
                                        \SOAP::Data->name('id')
                                                   ->type('long')
                                                   ->value($POLICY_OID)
                                        )
                     );
  
  $object = SOAP::Data->name('item')
                      ->attr({ 'xmlns:ser' => 'http://server.opsware.com'})
                      ->type('ser:ServerRef')
                      ->value(
                         \SOAP::Data->name('id')
                                    ->type('long')
                                    ->value($SERVER_OID)
                         );
  
  $args = SOAP::Data->name("attachables")
                    ->attr({ 'xmlns:swm' => 'http://swmgmt.opsware.com'})
                    ->type("swm:ArrayOf_xsd_anyType")
                    ->value( \SOAP::Data->name("elements" => ($object))->type("ser:ServerRef")
                             #,\SOAP::Data->name("recalculateServersAtRuntime")->value('1')
                           );
  $soap_policy->attachToPolicies($param,$args)->result;
  $jobref = $soap_policy->startRemediateNow($param,$args)->result;
  unless($jobref) {
    die "#- None job created !\n";
  }

  my $JOB_OID  = $jobref->{id};
  my $JOB_NAME = $jobref->{name};
  trackJob($JOB_OID,$JOB_NAME);
  #print "#: Job ${JOB_OID} = '${JOB_NAME}'\n";

  #$param = SOAP::Data->name('self')
  #                   ->attr({ 'xmlns:job' => 'http://job.opsware.com'})
  #                   ->type('job:JobRef')
  #                   ->value(
  #                      \SOAP::Data->name('id')
  #                                 ->value($JOB_OID)
  #                    );
  #while(my $jobstat = $soap_job->getJobInfoVO($param)->result) {
  #  #print Dumper $job;
  #  my $STAT=$jobstat->{status};
  #  my $STXT=$hJobStatus[$STAT];
  #  #my $STAT=$job->{serverInfo}->[0]->{status};
  #  print "Running ....... ${STXT}(${STAT})\n";
  #  last if ($STAT != 1);
  #  sleep(1);
  #}
  #print "= Results ====================\n";

  #$result = $soap_job->getResult($param)->result;
  #if($MODE_DUMP) { print Dumper $result; }
 
  print "= done. ======================\n";
  exit;

}

####################################################################### }}} 1
## -detach / -remove handling ######################################### {{{ 1

if($MODE_REMOVE) {
  getSoftwarePolicyRef;
  unless($POLICY_NAME and $POLICY_OID) {
    die "#- Error: A Software Policy has not been found !\n";
  }
  getServerRef;
  unless($SERVER_NAME and $SERVER_OID) {
    die "#- Error: A Server has not been found !\n";
  }
 
  
  $param = SOAP::Data->name('selves')
                     ->attr({'xmlns:swm'=> "http://swmgmt.opsware.com"})
                     ->type('swm:ArrayOfSoftwarePolicyRef')
                     ->value(
                        \SOAP::Data->name('item')
                                   ->type('swm:SoftwarePolicyRef')
                                   ->value(
                                        \SOAP::Data->name('id')
                                                   ->type('long')
                                                   ->value($POLICY_OID)
                                        )
                     );
  
  $object = SOAP::Data->name('item')
                      ->attr({ 'xmlns:ser' => 'http://server.opsware.com'})
                      ->type('ser:ServerRef')
                      ->value(
                         \SOAP::Data->name('id')
                                    ->type('long')
                                    ->value($SERVER_OID)
                         );
  
  $args = SOAP::Data->name("attachables")
                    ->attr({ 'xmlns:swm' => 'http://swmgmt.opsware.com'})
                    ->type("swm:ArrayOf_xsd_anyType")
                    ->value( \SOAP::Data->name("elements" => ($object))->type("ser:ServerRef")
                             #,\SOAP::Data->name("recalculateServersAtRuntime")->value('1')
                           );
  $soap_policy->detachFromPolicies($param,$args)->result;
  $jobref = $soap_policy->startRemediateNow($param,$args)->result;
  unless($jobref) {
    warn "#- None job created. ..but check -policy -on server. :-)\n";
  } else {

    my $JOB_OID  = $jobref->{id};
    my $JOB_NAME = $jobref->{name};
    trackJob($JOB_OID,$JOB_NAME);
   # print "#: Job ${JOB_OID} = '${JOB_NAME}'\n";
  
   # $object = SOAP::Data->name('self')
   #                    ->attr({ 'xmlns:job' => 'http://job.opsware.com'})
   #                    ->type('job:JobRef')
   #                    ->value(
   #                       \SOAP::Data->name('id')
   #                                  ->value($JOB_OID)
   #                     );
   # while(my $jobstat = $soap_job->getJobInfoVO($object)->result) {
   #   #print Dumper $job;
   #   my $STAT=$jobstat->{status};
   #   my $STXT=$hJobStatus[$STAT];
   #   #my $STAT=$job->{serverInfo}->[0]->{status};
   #   print "Running ....... ${STXT}(${STAT})\n";
   #   last if ($STAT != 1);
   #   sleep(1);
   # }
   # print "= Results ====================\n";
  
   # $result = $soap_job->getResult($param)->result;
   # if($MODE_DUMP) { print Dumper $result; }
  }
  print "#: removing associations.\n";
  $soap_policy->removePolicyAssociations($param,$args)->result;

  print "= done. ======================\n";
  exit;

}

####################################################################### }}} 1

## SUB - trackJob ##################################################### {{{ 1

sub trackJob($$) {
  my ($PROCESS_OID,$PROCESS_NAME) = @_;
  print "#: Job ${PROCESS_OID} = '${PROCESS_NAME}'\n";

  my $param = SOAP::Data->name('self')
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
  print "== Results ===================\n";
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
    print "Job started ........... ${JSTART}\n"   if $JSTART;
    print "Job ended ............. ${JSTOP}\n"    if $JSTOP;
    print "Reason for Blocked .... ${JBREASON}\n" if $JBREASON;
    print "Reason ofr Canceled ... ${JCREASON}\n" if $JCREASON;
    print "Schedule .............. ${JSCHED}\n"   if $JSCHED;
    print "Notification .......... ${JNOTIFY}\n"  if $JNOTIFY;
  }
  
  my $result = $soap_job->getResult($param)->result;
  if($MODE_DUMP) { print Dumper $result; }
}

####################################################################### }}} 1
# --- end ---

