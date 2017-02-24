#
# VPC2.pm - Q/A & C/R API for Utility to VPC migrations
# 20160229, Ing. Ondrej DURAS (dury)
# ~/bin/lib/VPC.pm
#

## Interface ########################################################## {{{ 1

package VPC2;

use strict;
use warnings;
use Exporter;
use File::Basename;
use IPC::Open3;
use IO::Handle;
use IO::Socket;
use IO::Select;
use Term::ReadKey;
use subs 'die';
use subs 'warn';

our $VERSION = 2016.112201;
our @ISA     = qw(
  Exporter
  File::Basename
  IPC::Open3
  IO::Handle
  IO::Socket
  Term::ReadKey
);

our @EXPORT = qw(
  $CONFIG
  $MODE_DEBUG
  $MODE_COLOR
  $MODE_STOP

  $TAKE_FROM
  $DATA_CONF
  $DATA_FOLD
  $DATA_LOGS
  $DATA_SITE

  $CRED_USER
  $CRED_TOOL
  $CRED_SUDO
  $CRED_ROOT
  $CRED_ADMIN
 
  colorOut
  colorPOD
  colorPrompt
  colorQMark

  println
  printdot
  cprint
  debug
  warn
  die
  ping
  port
  resolve

  crSshUser
  crSshTool
  crSshSudo
  crSshRoot

  cmdSshUser
  cmdSshUser
  cmdSshTool
  cmdSshSudo

  putScpUser
  putScpRoot
  putScpSudo
  putScpTool

  getScpUser
  getScpRoot
  getScpSudo
  getScpTool

  crWmiUser
  crWmiAdmin
  crCmdUser
  crCmdAdmin
  cmdWmiUser
  cmdWmiAdmin
  cmdWmiShell
  putSmbUser
  getSmbUser
  putSmbAdmin
  getSmbAdmin

  crVersion  
  crHostname
  crService
  crEnvAll
  crEnv
  crListenTcpAll
  crListenTcp
  crInstalledAll
  crInstalled
  crHpreportCheck

  qaEncrypt
  qaDecrypt
  qaLoad
  qaSave
  qaAttrib
  qaInput
  qaExec
  qaShell
  qaSecrets
  qaLogin
  qaPassword
  qaMethod
  qaServer

  qaRef
  qaKey
  qaDevip
  qaHname
  qaFQDN
  qaRLI
  qaHPSA_OID
  qaHPSA_GW_ADDR
  qaWave
  qaCustomer
  qaPlatform
  qaHpsatoolAddr
  qaHpsatoolName
  qaOmupAddr
  qaOmupName
  qaOmupCert
  qaHpreport
  qaOrchip
  qaLinux
  qaWindows
  qaType
  qaDpcell
  qaOPSFILE
  qaOpswareFile
  qaMcafeeAttr
);

####################################################################### }}} 1
## Defaults ########################################################### {{{ 1

our $CONFIG     = {};   # list of all configuration settings
our $MODE_DEBUG = "";   # regular expression to filter troubleshooting messages
our $MODE_COLOR = 2;    # TTY colors 0=OFF 1=ON 2=TBD
our $MODE_STOP  = 1;    # 1=STOP 0=Continue ...command-line parameters set this to zero

our $TAKE_FROM  = "";   # directory where from the script is started
our $DATA_CONF  = "";   # folder of all configuration files
our $DATA_FOLD  = "";   # folder of work data
our $DATA_LOGS  = "";   # folder for Logging
our $DATA_SITE  = "";   # web URI of remote configuration

our $CRED_USER  = "";   # User Credetials 
our $CRED_TOOL  = "";   # "hpsatool" credentials (login/key)
our $CRED_SUDO  = "";   # nsu/sudo credentials (nothing for now)
our $CRED_ROOT  = "";   # customer's server root & password
our $CRED_ADMIN = "";   # hplocaladmin login & password for windows


####################################################################### }}} 1
## Prototypes ######################################################### {{{ 1

# funny / zero level functions
sub colorOut($);        #o $TTY = colorOut($MSG);    colors/or does not color a message
sub colorPOD($);        #o $TTY = colorPOD($MSG);    of various type
sub colorPrompt($);     #o $TTY = colorPrompt($MSG);
sub colorQMark($);      #o $TTY = colotQMark($MSG);

# zero level functions
sub println(@);         #o prints more lines of output over cprint
sub printdot($$;$);     #- printdot($NAME,$VALUE;$COTNUM); # nice output "name .... value" 
sub cprint($);          #o colored or plain message
sub debug(;$);          #o provides a debug message
sub warn(;$);           #o provides a warning
sub die(;$);            #o provides a warning and exits
sub ping($);            #o $CTPING=ping($HOST); pings a server by external tool
sub port($;$$);         #o $STATUS=port($HOST,$PORT;$TIMEOUT);
sub resolve($);         #o ($DEVIP,$HNAME,$FQDN)=resolve($DEVIP/$HNAME/$FQDN) ...useing resolver

# 1st level function to work on remote servers / they are used by 2nd level bellow
sub crSshUser($$;%);    #o @OUT=crSshUser($HOST,$CMD;$OPT);  # [Secret.user] as default
sub crSshTool($$;%);    #o @OUT=crSshTool($HOST,$CMD;$OPT);  # [Secret.tool] as default
sub crSshSudo($$;%);    #o @OUT=crSshSudo($HOST,$CMD;$OPT);  # [Secret.sudo] as default
sub crSshRoot($$;%);    #o @OUT=crSshRoot($HOST,$CMD;$OPT);  # [Secret.root] as default

sub cmdSshUser($$;%); #i @OUT = cmdSshUser($HOST,$COMMANDS;%OPT); # multiline
sub cmdSshUser($$;%); #i @OUT = cmdSshTool($HOST,$COMMANDS;%OPT); # without an 
sub cmdSshTool($$;%); #i @OUT = cmdSshSudo($HOST,$COMMANDS;%OPT); # interaction
sub cmdSshSudo($$;%); #i @OUT = cmdSshRoot($HOST,$COMMANDS;%OPT);

# unix/linux file transfer upload
sub putScpUser($$$;%);  #o $RESULT=putScpUser($HOST,$LOCAL_FILE,$REMOTE_FILE;%OPT);
sub putScpRoot($$$;%);  #i $RESULT=putScpRoot($HOST,$LOCAL_FILE,$REMOTE_FILE;%OPT);       
sub putScpSudo($$$;%);  #i $RESULT=putScpSudo($HOST,$LOCAL_FILE,$REMOTE_FILE;%OPT);
sub putScpTool($$$;%);  #i $RESULT=putScpTool($HOST,$LOCAL_FILE,$REMOTE_FILE;%OPT);

# unix/linux file transfer download
sub getScpUser($$$;%);  #i $RESULT=getScpUser($HOST,$LOCAL_FILE,$REMOTE_FILE;%OPT);
sub getScpRoot($$$;%);  #i $RESULT=getScpRoot($HOST,$LOCAL_FILE,$REMOTE_FILE;%OPT);
sub getScpSudo($$$;%);  #i $RESULT=getScpSudo($HOST,$LOCAL_FILE,$REMOTE_FILE;%OPT);
sub getScpTool($$$;%);  #i $RESULT=getScpTool($HOST,$LOCAL_FILE,$REMOTE_FILE;%OPT);

# all windows related functions
sub crWmiUser($$;%);    #o @OUT=crWmiUser($HOST,$CMD;%OPT);   # single command over WMI with
sub crWmiAdmin($$;%);   #o @OUT=crWmiAdmin($HOST,$CMD;%OPT);  # more reiable results
sub crCmdUser($$;%);    #o @OUT=crWmiUser($HOST,$CMD;%OPT);   # multiple commands over WMI>CMD.exe
sub crCmdAdmin($$;%);   #o @OUT=crWmiAdmin($HOST,$CMD;%OPT);

sub cmdWmiUser($$;%);   #i @OUT=cmdWmiUser($HOST,$COMMANDS;%OPT);  # multiple commands on Windows
sub cmdWmiAdmin($$;%);  #i @OUT=cmdWmiAdmin($HOST,$COMMANDS;%OPT); # multiple commands on Windows /Admin
sub cmdWmiShell($;$%);  #i cmdWmiShell($HOST;$COMMAND,%OPT);       # cmd.exe launched onto a server
sub putSmbUser($$$;%);  #i $RESULT=putSmbUser($HOST,$LOCAL_FILE,$REMOTE_FILE;%OPT); # file transfer over 
sub getSmbUser($$$;%);  #i $RESULT=getSmbUser($HOST,$LOCAL_FILE,$REMOTE_FILE;%OPT); # Simple Message Block (SMB)
sub putSmbAdmin($$$;%); #i $RESULT=putSmbAdmin($HOST,$LOCAL_FILE,$REMOTE_FILE;%OPT);
sub getSmbAdmin($$$;%); #i $RESULT=getSmbAdmin($HOST,$LOCAL_FILE,$REMOTE_FILE;%OPT);

# 2nd level functions to interact the Windows servers / all use wmi 1st level functions
sub crVersion($;%);     #o $VERSION=crVersion($HOST); # provides a Operating Version of the Server $HOST
sub crEnvAll($;%);      #i \%ENVIRONMENT=crEnvAll($HOST;%OPT);  # takes whole system environment from server
sub crEnv($$;%);        #i $VALUE=crListenTCP($HOST,$VARIABLE;%OPT); # gives value of server's variable
sub crListenTcpAll($;%);#w \@OUTREF=crListenTCP($HOST;%OPT);  # Takes all ports they are in Listening status
sub crListenTcp($$;%);  #w $HPORTS=crListenTCP($HOST,$PORT;%OPT); # 1=if server listens on tcp/$PORT
sub crService($$;%);    #w $HSERVICES=crServices($HOST,$SERVICE_REGEX;%OPT); # returns a a number of running services
sub crInstalledAll($;%);#i \@INSTALLED=crInstalledAll($HOST;%OPT); # takes all installed software on server
sub crInstalled($$;%);  #i $VERSION=crInstalled($HOST,$SOFTWARE;%OPT); # returns a version of installed software
sub crHostname($;%);    #w $HNAME=crHostname($HOST;$LOGIN,$PASSWORD);  # returns a detected hostname of server
sub crHpreportCheck($;%);#i $BOOL=crHpreportCheck($HOST;%OPT); # checks whether the server is registered in hpreporter

# Q/A communication / left side of each script user/dispatcher <=> interpretor/server interaction
sub qaEncrypt($);       #- $CODE=qaEncrypt($TEXT);  # standard string encryption
sub qaDecrypt($);       #- $TEXT=qaDecrypt($CODE);  # standard string decryption 
sub qaLoad($$);         #o $RESULT=qaLoas($CONFIG,$FILE_CONF); # loading configuration into %$CONFIG
sub qaSave($$);         #o $RESULT=qaSave($CONFIG,$FILE_CONF); # storing configuration onto disk
sub qaAttrib($$);       #- $RESULT=qa($ARGX,\@ARGV); # handles standard commandline attributes
sub qaInput($$);        #- $LINE=qaInput($PROMPT);   # queries used/dispatcher for a string
sub qaExec($$);         #- $RESULT=qaExec($LINE,$RULES); # executes entered commandline
sub qaShell($);         #- $RESULT=qaExec($RULES);       # multiple line interaction at the left side
sub qaSecret($);        #- ($METHOD,$LOGIN,$PASSWORD)=qaSecret($USER); # disassembles a secret to provide creddentials
sub qaLogin($);         #- $LOGIN=qaLogin($USER); # provides a login (a part of credentials)
sub qaPassword($);      #- $PASSWORD=qaPassword($USER); # provides a password (a part of credentials)
sub qaMethod($);        #- $METGHOD=qaMethod($USER);    # provides an authentication method (a part of ccredentials)
sub qaServer($;$);      #o $SERVER=qaHostStr(\%CONFIG,$DEVIP/$HNAME/$FQDN) # returns details of server from config

sub qaRef($);           #o \%POINTER=qaRef($HOST);      # qaServer based, gives a server reference pointer to $CONFIG
sub qaKey($);           #o $HOST_KEY=qaKey($HOST);      # qaServer based, gives a server HOST_KEY to $CONFIG
sub qaDevip($);         #o $DEVIP=qaDevip($HOST);       # qaServer based, gives an IP of server
sub qaHname($);         #o $HNAME=qaHname($HOST);       # qaServer based, gives a HostName of server
sub qaFQDN($);          #o $FQDN=qaFQDN($HOST);         # qaServer based, gives a FQDN of server
sub qaRLI($);           #o $RLI=qaRLI($HOST);           # qaServer based, gives a RLI of server
sub qaHPSA_OID($);      #o $HSPA_OID=qaHPSA_OID($HOST); # qaServer based, gives a HSPA_OID of a server
sub qaHPSA_GW_ADDR($);  #i $HPSA_GW_ADDR=qaHPSA_GW_ADDR($HOST); #qaServer based 
sub qaWave($);          #o $WAVE=qaWave($HOST);         # qaServer based, gives a Wavwe name
sub qaCustomer($);      #o $CUSTOMER=qaCustomer($HOST); # qaServer based, gives a Customer name
sub qaPlatform($);      #o $PLATFORM=qaPlatform($HOST); # qaServer based, gives a Platform details
sub qaHpsatoolAddr($);  #i $HPSATOOL_ADDR=qaHpsatoolAddr($HOST); # qaServer based
sub qaHpsatoolName($);  #i $HPSATOOL_NAME=qaHpsatoolName($HOST); # qaServer based
sub qaOmupAddr($);      #o $OMUPADDR=qaOmupAddr($HOST); # qaServer based, gives an IP address of OMU-P
sub qaOmupName($);      #o $OMUPNAME=qaOmupName($HOST); # qaServer based, gives an FQDN of OMU-P
sub qaOmupCert($);      #o $OMUPCERT=qaOmupName($HOST); # qaServer based, gives an FQDN of OMU
sub qaHpreport($);      #o $DEVIP=qaHpreport($HOST);    # qaServer based, gives an IP of HP-Reporter
sub qaOrchip($);        #o $DEVIP=qaOrchip($HOST);      # qaServer based, gives an IP of Orchestrator
sub qaLinux($);         #o $BOOL=qaLinux($HOST);        # qaServer based, gives 1 if host is Linux
sub qaWindows($);       #o $BOOL=qaWindows($HOST);      # qaServer based, gives 1 if host is Windows
sub qaType($);          #o $BOOL=qaType($HOST);         # qaServer based, gives a Type of server {OS,DB/SAP}
sub qaDpcell($);        #o $DPCELL=qaType($HOST);       # qaServer based, gives a DPCELL of server {OS,DB/SAP}
sub qaOPSFILE($);       #w $FILE=qaOPSFILE($HOST);      # qaServer based, gives an Opsware Installation File
sub qaOpswareFile($);   #w $FILE=qaOpswareFile($HOST);  # qaServer based, gives an Opsware Installation File
sub qaMcafeeAttr($);    #i $MCAFEE_ATTR=qaMcafeeAttr($);# qaServer based, gives an Attribute for McAfee antivirus installation

####################################################################### }}} 1
## Colors on Terminal ################################################# {{{ 1


#FUNCTION:  
#  $TTY = colorOut($MSG);    
#PARAMETERS:
#  $TTY - message with color TTY escape sequences
#  $MSG - plain text message without colors
#DESCRIPTION:
#  based on $MODE_COLOR colors/or does not color a message $MSG
#  Message $MSG should contain a standard output of remotelly
#  performed commands, warnings, errors and/or debug messages


sub colorOut($) {
  my $MSG = shift;
  unless($MODE_COLOR) { 
    return $MSG; 
  }
  $MSG =~ s/^#:.*$/\033[0;34m$&\033[m/mg;
  $MSG =~ s/^#-.*$/\033[1;31m$&\033[m/mg;
  $MSG =~ s/^#+.*$/\033[1;32m$&\033[m/mg;
  $MSG =~ s/^[ a-zA-Z0-9].*$/\033[0;33m$&\033[m/mg;
  return $MSG;
}

#FUNCTION:
#  $TTY = colorPOD($MSG);
#PARAMETERS:
#  $TTY - message with color TTY escape sequences
#  $MSG - plain text message without colors
#DESCRIPTION:
#  based on $MODE_COLOR it colors or not a message $MSG
#  $MSG should contain POD formated manual
#CONTENT:
#  ./  - commands
#  -   - command line parameters
#  XY: - labels of sections

sub colorPOD($) {
  my $MSG = shift;
  unless($MODE_COLOR) { 
    return $MSG; 
  }
  $MSG =~ s/^[A-Z].*:.*$/\033[1;36m$&\033[m/mg;
  $MSG =~ s/^\s+[A-Za-z0-9].*$/\033[0;36m$&\033[m/mg;
  $MSG =~ s/^\s+\.\/.*$/\033[1;32m$&\033[m/mg;
  $MSG =~ s/^\s+-.*$/\033[1;32m$&\033[m/mg;
  return $MSG;
}       

#FUNCTION:
#  $TTY = colorPrompt($MSG);
#PARAMETERS:
#  $TTY - message with color TTY escape sequences
#  $MSG - plain text message without colors
#DESCRIPTION:
#  gives a color to prompt/s only

sub colorPrompt($) {
  my $MSG = shift;
  unless($MODE_COLOR) { 
    return $MSG; 
  }
  $MSG =~ s/^.*>> $/\033[1;33m$&\033[m/; 
  return $MSG;
}

#FUNCTION:
#  $TTY = colotQMark($MSG);
#PARAMETERS:
#  $TTY - message with color TTY escape sequences
#  $MSG - plain text message without colors
#DESCRIPTION:
#  colors manual trigered by ? on the command-line
#  $MSG should contains list of commands - description

sub colorQMark($) {
  my $MSG = shift;
  unless($MODE_COLOR) { 
    return $MSG; 
  }
  $MSG =~ s/^(\S.*)( +- +)(\S.*)$/\033[1;32m$1\033[1;36m$2\033[0;32m$3\033[m/mg;
  $MSG =~ s/^(\S.*)( +\.{3,} +)(\S.*[A-Z]+\!.*)$/\033[0;31m$1\033[0;33m$2\033[1;31m$3\033[m/mg;
  $MSG =~ s/^(\S.*)( +\.{3,} +)(\S.*)$/\033[0;32m$1\033[1;36m$2\033[1;32m$3\033[m/mg;
  return $MSG;
}

####################################################################### }}} 1
## Common functions ################################################### {{{ 1

#FUNCTION:
#  cprint $MSG;
#PARAMETER:
#  $MSG - message colored by tty escape sequences
#DESCRIPTION:
#  based on $MODE_COLOR provides $MSG to the terminal
#  as-is or suppresses the escape sequences

sub cprint($) {
  my $MSG = shift;

  unless($MODE_COLOR) {
    $MSG =~ s/\033[;0-9]*m//mg;
  }
  print $MSG;
}

#FUNCTION:
#  println @AMSG;
#PARAMETERS:
#  @AMSG - is an array of colored messages
#DESCRIPTION:
#  prints more lines of output over cprint

sub println(@) {
  my @AMSG = @_;
  my $TEXT  = "";
  my $OUT;

  foreach my $LINE (@AMSG) {
    $OUT  =  $LINE;
    $OUT  =~ s/\s+$//;
    $TEXT .= $OUT."\n";
  }
  cprint $TEXT;
}

#FUNCTION:
#  printdot($NAME,$VALUE;$DOTLENGTH);
#PARAMETERS:
#  $NAME  - string displayed on the left side of output
#  $VALUE - string/value displayed on the right side 
#  $DOTLENGTH - default 50 - number of dots
sub printdot($$;$) {
  my($NAME,$VALUE,$DOTLENGTH) = @_;
           #123456789.123456789.123456789.'
  my $DOTS='..............................'
          .'....................';
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

#FUNCTION:
#  debug $MSG;
#PARAMETERS:
#  $MSG - plain troubleshooting message
#DESCRIPTION:
#  if $MSG matches $MODE_DEBUG, then the
#  message is issues to terminal/log
#  otherwise nothing goes to output

sub debug(;$) {
  my $MSG = shift;

  return unless $MODE_DEBUG;
  return unless $MSG =~ /${MODE_DEBUG}/;
  $MSG =~ s/^/#:/mg;
  print colorOut $MSG;
}

#FUNCTION:
#  warn $MSG;
#PARAMETER:
#  $MSG - warning message
#DESCRIPTION:
#  issues a warning message

sub warn(;$) {
  my $MSG = shift;

  chomp $MSG;
  $MSG =~ s/^/#- /mg;
  print colorOut $MSG."\n";
}

#FUNCTION:
#  die $MSG;$ERR;
#USAGE:
#  die "something wrong !"
#  die "something wrong !",2;
#PARAMETER:
#  $MSG - error message
#  $ERR - error code for a parent process
#DESCRIPTION:
#  handles unsucessfull script termination

sub die(;$$) {
  my ($MSG,$ERR) = @_;
  $ERR = 1 unless $ERR;
  warn $MSG;
  exit $ERR;
}

#FUNCTION:
#  $RESULT=ping($HOST);
#USAGE:
#  $RECHABLE=ping($SERVER);
#PARAMETERS:
#  $REACHABLE - 1=if 3 ICMP responces received, 0=otherwise
#  $HOST      - IP address, Hostname, FQDN of network device/server we would like to ping
#DESCRIPTION:
#  sends ICMP queries and returns 1(yes/reachable) if rever responds correctly
#  otherwise returns 0(no/unreachable)

sub ping($) {          # $CTPING=ping($HOST); pings a server by external tool
  my $HOST = shift;
  unless($HOST =~ /\S/) { return 0; }
  my @OUT = grep /bytes from.*icmp_seq=.*time=/,`ping -c3 -i0.3 ${HOST}`;
  my $RESULT=0;
     $RESULT=1 if scalar(@OUT) >= 3;
  return $RESULT;
}


#FUNCTION:
#  $STATUS=port($HOST,$PORT;$TIMEOUT);
#USAGE:
#  port("1.2.3.4","5555",5)?"open":"closed"
#  $STATUS  - 1=open 0-closed/filtered/unusable
#  $HOST    - IP address, FQDN, resolvable HostaName ... something resolvable
#  $PORT    - TCP port you want to check, default is tcp/22 (SSH)
#  $TIMEOUT - timeout to open socket, default is 2 (seconds)

sub port($;$$) {
  my($DEST,$PORT,$TIMEOUT) = @_;
  $PORT = 22 unless $PORT;
  $TIMEOUT = 2 unless $TIMEOUT;
  my $FLAG = 0;
  my $socket = IO::Socket::INET->new(
           PeerAddr => $DEST ,
           PeerPort => $PORT ,
           Proto => 'tcp' ,
           Timeout => $TIMEOUT
     );
  if($socket) {
    $FLAG =1;
    shutdown($socket,1) if $socket;
    shutdown($socket,2) if $socket;
    close($socket) if $socket;
  }
  return $FLAG;
}

#FUNCTION:
#  ($DEVIP,$HNAME,$FQDN)=resolve($HOST);
#PARAMETERS:
#  $DEVIP   - returned IP address
#  $HNAME   - returned HostName
#  $FQDN    - returned FQDN
#  $HOST    - what ever ... IP,Hostname or FQDN
#DECSRIPTION:
#  Translates whatever resolvable into three things
#  to IP address, HostName and Fully Qualified DomainName
#  In case of something wrong will happen, the function
#  returns three empty strings.
#

sub resolve($) {        # ($DEVIP,$HNAME,$FQDN)=resolve($DEVIP/$HNAME/$FQDN) ...useing resolver
  my $HOST = shift;
  my ($DEVIP,$HNAME,$FQDN, $ADDR);


  if($HOST =~ /^[0-9]{1,3}(\.[0-9]{1,3}){3}$/) {
    $DEVIP = $HOST;
    $ADDR = inet_aton($DEVIP);   # IP address to FQDN translation
    $FQDN = gethostbyaddr($ADDR, AF_INET);
    unless($FQDN) {
            warn "#- Wrong IP address ${HOST} !\n";
            return("","","");
    }
    $HNAME = $FQDN;
    $HNAME =~ s/\..*//;
    return ($DEVIP,$HNAME,$FQDN);
  } else {
    $FQDN = $HNAME = $HOST;    # FQDN to IP address translation
    $HNAME =~ s/\..*//;
    $ADDR = gethostbyname($FQDN);
    unless($ADDR) {
      warn "#- Wrong FQDN ${HOST} !\n";
      return ("","","");
    }
    $DEVIP = inet_ntoa($ADDR);
    return($DEVIP,$HNAME,$FQDN);
  }
}

####################################################################### }}} 1
## SSH - C/R communication ############################################ {{{ 1

#FUNCTION:
#  @OUTPUT=crSshUser($HOST,$COMMAND;$USER);
#PARAMETERS:
#  @OUTPUT  - whole output, each line does NOT contain <CR><LF>
#  $HOST    - a server where to apply a command
#  $COMMAND - command to be applied
#  $USER    - actual user used, but may be changed
#DESCRIPTION:
#  performs a command remotely, on the $HOST server


sub crSshUser($$;%) {  # @OUT=crSshUser($HOST,$CMD;$USER);  # [Secret.user] as default
  my ($HOST,$COMMAND,%OPT) = @_;
  my ($RDR,$WTR,$ERR);
  my @OUT=();
  my $USER=$OPT{"login"};

  unless($USER) {
    if(exists($ENV{"USER"})) { $USER=$ENV{"USER"}; }
    elsif(exists($ENV{"USERNAME"})) { $USER=$ENV{"USERNAME"}; }
  }
  #$COMMAND .="\n"; $COMMAND =~ s/\n\n\Z/\n/m;
  #$PID = open2($RDR,$WTR,"winexe","-U",'hplocaladmin%ucstemp01'
  my $LINE;
  my $PID = open3($WTR,$RDR,$ERR,"ssh","-q",
                  "-oStrictHostKeyChecking=no","-oUserKnownHostsFile=/dev/null",
                  "-l",$USER,$HOST,$COMMAND);
  #my $PID = open3($WTR,$RDR,$ERR,"ssh","-q",$HOST,"/bin/ls","-la");
  #my $PID = open3($WTR,$RDR,$ERR,"ssh","-q",$HOST,"/bin/ls -la");
  unless($PID) { die "SSH failure !\n"; }


  while($RDR and ($LINE=<$RDR>)) {
    chomp $LINE;
    unless($LINE =~ /\S/) { next; }
    #if($LINE =~ /^Unknown parameter encountered: "/) { next; }
    #if($LINE =~ /^Ignoring unknown parameter "/) { next; }
    push @OUT,$LINE;
    #print "#: ${HOST}: ${LINE}\n";
  }
  while($ERR and ($LINE=<$ERR>)) {
    chomp $LINE;
    unless($LINE =~ /\S/) { next; }
    push @OUT,"#- ".$LINE;
    #print "#: ${HOST}: ${LINE}\n";
  }

  if($ERR) { close $ERR; }
  if($WTR) { close $WTR; }
  if($RDR) { close $RDR; }
  waitpid($PID,0);
  return @OUT;
}

#FUNCTION:
#  @OUTPUT=crSshTool($HOST,$COMMAND;$USER);
#PARAMETERS:
#  @OUTPUT  - whole output, each line does NOT contain <CR><LF>
#  $HOST    - a server where to apply a command
#  $COMMAND - command to be applied
#  $USER    - actual user used, but may be changed
#DESCRIPTION:
#  performs a command remotely, on the $HOST server
#  Tool - is associated with account/login used within MMI fo migration.

sub crSshTool($$;%) {  # @OUT=crSshTool($HOST,$CMD;$USER);  # [Secret.tool] as default
  my ($HOST,$COMMAND,%OPT) = @_;
  my ($RDR,$WTR,$ERR);
  my @OUT=();
  my $USER=$OPT{"login"};

  unless($USER) {
    $USER = "hpsatool";
  }

  #$COMMAND .="\n"; $COMMAND =~ s/\n\n\Z/\n/m;
  #$PID = open2($RDR,$WTR,"winexe","-U",'hplocaladmin%ucstemp01'
  my $LINE;
  my $PID = open3($WTR,$RDR,$ERR,"ssh","-q",
                  "-oStrictHostKeyChecking=no","-oUserKnownHostsFile=/dev/null",
                  "-l",$USER,$HOST,$COMMAND);
  #my $PID = open3($WTR,$RDR,$ERR,"ssh","-q",$HOST,"/bin/ls","-la");
  #my $PID = open3($WTR,$RDR,$ERR,"ssh","-q",$HOST,"/bin/ls -la");
  unless($PID) { die "SSH failure !\n"; }


  while($RDR and ($LINE=<$RDR>)) {
    chomp $LINE;
    unless($LINE =~ /\S/) { next; }
    #if($LINE =~ /^Unknown parameter encountered: "/) { next; }
    #if($LINE =~ /^Ignoring unknown parameter "/) { next; }
    push @OUT,$LINE;
    #print "#: ${HOST}: ${LINE}\n";
  }
  while($ERR and ($LINE=<$ERR>)) {
    chomp $LINE;
    unless($LINE =~ /\S/) { next; }
    push @OUT,"#- ".$LINE;
    #print "#: ${HOST}: ${LINE}\n";
  }

  if($ERR) { close $ERR; }
  if($WTR) { close $WTR; }
  if($RDR) { close $RDR; }
  waitpid($PID,0);
  return @OUT;
}

#FUNCTION:
#  @OUTPUT=crSshSudo($HOST,$COMMAND;$USER);
#PARAMETERS:
#  @OUTPUT  - whole output, each line does NOT contain <CR><LF>
#  $HOST    - a server where to apply a command
#  $COMMAND - command to be applied
#  $USER    - actual user used, but may be changed
#DESCRIPTION:
#  performs a command remotely, on the $HOST serveri as a root
#  Sudo - is associated with root account in MMI.

sub crSshSudo($$;%) {  # @OUT=crSshSudo($HOST,$CMD;$USER);  # [Secret.sudo] as default
  my ($HOST,$COMMAND,%OPT) = @_;
  my ($RDR,$WTR,$ERR);
  my @OUT=();

  #$COMMAND .="\n"; $COMMAND =~ s/\n\n\Z/\n/m;
  #$PID = open2($RDR,$WTR,"winexe","-U",'hplocaladmin%ucstemp01'
  my $LINE;

  ## Solution1: Direct connection as root
  #my $PID = open3($WTR,$RDR,$ERR,"ssh","-q",
  #                "-oStrictHostKeyChecking=no","-oUserKnownHostsFile=/dev/null",
  #                "-l","root",
  #                $HOST,$COMMAND);
  ##my $PID = open3($WTR,$RDR,$ERR,"ssh","-q",$HOST,"/bin/ls","-la");
  ##my $PID = open3($WTR,$RDR,$ERR,"ssh","-q",$HOST,"/bin/ls -la");
  #unless($PID) { die "SSH failure !\n"; }

  ## Solution2: connect as hpsatool; then sudo su -
  my $PID = open3($WTR,$RDR,$ERR,"ssh","-q",
                  "-oStrictHostKeyChecking=no","-oUserKnownHostsFile=/dev/null",
                  "-l","hpsatool",
                  $HOST);
  unless($PID) { die "SSH failure !\n"; }
  print $WTR "sudo su -\n";
  print $WTR "${COMMAND}\n";
  print $WTR "exit\n";

  while($RDR and ($LINE=<$RDR>)) {
    chomp $LINE;
    unless($LINE =~ /\S/) { next; }
    #if($LINE =~ /^Unknown parameter encountered: "/) { next; }
    #if($LINE =~ /^Ignoring unknown parameter "/) { next; }
    push @OUT,$LINE;
    #print "#: ${HOST}: ${LINE}\n";
  }
  while($ERR and ($LINE=<$ERR>)) {
    chomp $LINE;
    unless($LINE =~ /\S/) { next; }
    push @OUT,"#- ".$LINE;
    #print "#: ${HOST}: ${LINE}\n";
  }

  if($ERR) { close $ERR; }
  if($WTR) { close $WTR; }
  if($RDR) { close $RDR; }
  waitpid($PID,0);
  return @OUT;
}



#FUNCTION:
#  @OUTPUT=crSshRoot($HOST,$COMMAND;$USER);
#PARAMETERS:
#  @OUTPUT  - whole output, each line does NOT contain <CR><LF>
#  $HOST    - a server where to apply a command
#  $COMMAND - command to be applied
#  $USER    - actual user used, but may be changed
#DESCRIPTION:
#  performs a command remotely, on the $HOST serveri as a root
#  Sudo - is associated with root account in MMI.

sub crSshRoot($$;%) {  # @OUT=crSshRoot($HOST,$CMD;$USER);  # [Secret.root] as default
  my ($HOST,$COMMAND,%OPT) = @_;
  my ($RDR,$WTR,$ERR,$USER,$PASSWORD);
  my @OUT=();

  unless($USER=$OPT{"login"}) { 
    $USER="root"; 
  }

  unless($PASSWORD=$OPT{"password"}) { 
    if(exists($ENV{SSHPASS})) { 
      $PASSWORD=$ENV{SSHPASS}; 
    } else { 
      $PASSWORD=""; 
    }
  }
  #$COMMAND .="\n"; $COMMAND =~ s/\n\n\Z/\n/m;
  #$PID = open2($RDR,$WTR,"winexe","-U",'hplocaladmin%ucstemp01'
  my $LINE;
  my $PID = open3($WTR,$RDR,$ERR,"sshpass","-e","ssh","-q",
                  "-oStrictHostKeyChecking=no","-oUserKnownHostsFile=/dev/null",
                  "-l",$USER,
                  $HOST,$COMMAND);
  #my $PID = open3($WTR,$RDR,$ERR,"ssh","-q",$HOST,"/bin/ls","-la");
  #my $PID = open3($WTR,$RDR,$ERR,"ssh","-q",$HOST,"/bin/ls -la");
  unless($PID) { die "SSH failure !\n"; }


  while($RDR and ($LINE=<$RDR>)) {
    chomp $LINE;
    unless($LINE =~ /\S/) { next; }
    #if($LINE =~ /^Unknown parameter encountered: "/) { next; }
    #if($LINE =~ /^Ignoring unknown parameter "/) { next; }
    push @OUT,$LINE;
    #print "#: ${HOST}: ${LINE}\n";
  }
  while($ERR and ($LINE=<$ERR>)) {
    chomp $LINE;
    unless($LINE =~ /\S/) { next; }
    push @OUT,"#- ".$LINE;
    #print "#: ${HOST}: ${LINE}\n";
  }

  if($ERR) { close $ERR; }
  if($WTR) { close $WTR; }
  if($RDR) { close $RDR; }
  waitpid($PID,0);
  return @OUT;
}


####################################################################### }}} 1
## SSH - C/R communication cmdSsh(User|Tool|Sudo|Root) ################ {{{ 1

#FUNCTION:
#  @OUT = cmdSshUser($HOST,$COMMAND,%OPT);
#PARAMETERS:
#  @OUT  - output in lines
#  $HOST - IP/Hostname/FQDN of server
#  $CMD  - multiline command /sequence of commands
#  %OPT  - intended extension for later purposes
#DESCRIPTION:
#  Persorms a command or sequence of commands
#  on Server over SSH protocol
#  By default if uses actual user and returns the
#  output in array of lines.

sub cmdSshUser($$;%) {
  my ($HOST,$COMMAND,%OPT) = @_;
  my $CMD ="cat <<__END__ | ssh -q ${HOST} 2>&1\n"
          ."${COMMAND}\n"
          ."exit\n";
  return  `${CMD}`;
}

#FUNCTION:
#  @OUT = cmdSshTool($HOST,$COMMAND,%OPT);
#PARAMETERS:
#  @OUT  - output in lines
#  $HOST - IP/Hostname/FQDN of server
#  $CMD  - multiline command /sequence of commands
#  %OPT  - intended extension for later purposes
#DESCRIPTION:
#  Persorms a command or sequence of commands
#  on Server over SSH protocol
#  By default if uses credentials for automation
#  It returns the output in array of lines.

sub cmdSshTool($$;%) {
  my ($HOST,$COMMAND,%OPT) = @_;
  my $CMD ="cat <<__END__ | ssh -q -l hpsatool ${HOST} 2>&1\n"
          ."${COMMAND}\n"
          ."exit\n";
  return  `${CMD}`;
}

#FUNCTION:
#  @OUT = cmdSshSudo($HOST,$COMMAND,%OPT);
#PARAMETERS:
#  @OUT  - output in lines
#  $HOST - IP/Hostname/FQDN of server
#  $CMD  - multiline command /sequence of commands
#  %OPT  - intended extension for later purposes
#DESCRIPTION:
#  Persorms a command or sequence of commands
#  on Server over SSH protocol
#  By default it uses a super user privilege
#  It takes a root privilege by "sudo su -"
#  It returns the output in array of lines.

sub cmdSshSudo($$;%) {
  my ($HOST,$COMMAND,%OPT) = @_;
  my $CMD ="cat <<__END__ | ssh -q -l hpsatool ${HOST} 2>&1\n"
          ."sudo su -\n"
          ."${COMMAND}\n"
          ."exit\n";
  return  `${CMD}`;
}

#FUNCTION:
#  @OUT = cmdSshRoot($HOST,$COMMAND,%OPT);
#PARAMETERS:
#  @OUT  - output in lines
#  $HOST - IP/Hostname/FQDN of server
#  $CMD  - multiline command /sequence of commands
#  %OPT  - intended extension for later purposes
#DESCRIPTION:
#  Persorms a command or sequence of commands
#  on Server over SSH protocol
#  By default it uses Customer's root account.
#  It takes a root privilege by password from SSHPASS
#  It returns the output in array of lines.

sub cmdSshRoot($$;%) {
  my ($HOST,$COMMAND,%OPT) = @_;
  my $CMD ="cat <<__END__ | sshpass -e ssh -q -l root ${HOST} 2>&1\n"
          ."${COMMAND}\n"
          ."exit\n";
  return  `${CMD}`;
}

####################################################################### }}} 1
## SSH - C/R file uploads ############################################# {{{ 1


#FUNCTION:
#  $RESULT=putScpUser($HOST,$LOCAL_FILE,$REMOTE_FILE;%OPT);
#PARAMETERS:
#  $RESULT  - returned value 1-if successfull, otherwise 0
#  $HOST    - IP addres, hostname. fqdn of destination host
#  $LOCAL   - local file name with whole path if necessary
#  $REMOTE  - filename on the destination $HOST
#DESCRIPTION:
#  function delivers file onto server $HOST


sub putScpUser($$$;%) { # $RESULT=putScpUser($HOST,$LOCAL_FILE,$REMOTE_FILE;$LOGIN,$PASSWORD);
  my ($HOST,$LOCAL,$REMOTE,%OPT) = @_;
  my ($LOGIN,$PASSWORD);
  unless( -f $LOCAL ) { 
    warn "Local file '${LOCAL}' is unreachable !\n";
    return 0;
  }
  my $DEST="${HOST}:${REMOTE}";
  if ($LOGIN=$OPT{"login"}) { $DEST="${LOGIN}\@${DEST}"; }
  my $COMMAND="scp ${LOCAL} ${DEST}";
  if ($PASSWORD=$OPT{"password"}) { 
    $ENV{SSHPASS}=$PASSWORD; 
    $COMMAND="sshpass -e | ${COMMAND}"; 
  }
  system($COMMAND);
  return 1;
}

#FUNCTION:
#  $RESULT=putScpRoot($HOST,$LOCAL_FILE,$REMOTE_FILE;%OPT);
#PARAMETERS:
#  $RESULT  - returned value 1-if successfull, otherwise 0
#  $HOST    - IP addres, hostname. fqdn of destination host
#  $LOCAL   - local file name with whole path if necessary
#  $REMOTE  - filename on the destination $HOST
#DESCRIPTION:
#  function delivers file onto server $HOST

sub putScpRoot($$$;%) { # $RESULT=putScpRoot($HOST,$LOCAL_FILE,$REMOTE_FILE;%OPT);       
  my ($HOST,$LOCAL,$REMOTE,%OPT) = @_;
  my ($LOGIN,$PASSWORD);
  unless( -f $LOCAL ) { 
    warn "Local file '${LOCAL}' is unreachable !\n";
    return 0;
  }
  unless ($LOGIN=$OPT{"login"}) { $LOGIN="root"; }
  my $DEST="${LOGIN}\@${HOST}:${REMOTE}";
  my $COMMAND="scp ${LOCAL} ${DEST}";
  if ($PASSWORD=$OPT{"password"}) { 
    $ENV{SSHPASS}=$PASSWORD; 
    $COMMAND="sshpass -e | ${COMMAND}"; 
  }
  system($COMMAND);
  return 1;
}

#FUNCTION:
#  $RESULT=putScpSudo($HOST,$LOCAL_FILE,$REMOTE_FILE;%OPT);
#PARAMETERS:
#  $RESULT  - returned value 1-if successfull, otherwise 0
#  $HOST    - IP addres, hostname. fqdn of destination host
#  $LOCAL   - local file name with whole path if necessary
#  $REMOTE  - filename on the destination $HOST
#DESCRIPTION:
#  function delivers file onto MMI server $HOST

sub putScpSudo($$$;%) { # $RESULT=putScpSudo($HOST,$LOCAL_FILE,$REMOTE_FILE;%OPT);
  my ($HOST,$LOCAL,$REMOTE,%OPT) = @_;
  my ($LOGIN,$PASSWORD);
  unless( -f $LOCAL ) { 
    warn "Local file '${LOCAL}' is unreachable !\n";
    return 0;
  }
  unless ($LOGIN=$OPT{"login"}) { $LOGIN="root"; }
  my $DEST="${LOGIN}\@${HOST}:${REMOTE}";
  my $COMMAND="scp ${LOCAL} ${DEST}";
  if ($PASSWORD=$OPT{"password"}) { 
    $ENV{SSHPASS}=$PASSWORD; 
    $COMMAND="sshpass -e | ${COMMAND}"; 
  }
  system($COMMAND);
  return 1;
}

#FUNCTION:
#  $RESULT=putScpTool($HOST,$LOCAL_FILE,$REMOTE_FILE;$LOGIN,$PASSWORD);
#PARAMETERS:
#  $RESULT  - returned value 1-if successfull, otherwise 0
#  $HOST    - IP addres, hostname. fqdn of destination host
#  $LOCAL   - local file name with whole path if necessary
#  $REMOTE  - filename on the destination $HOST
#DESCRIPTION:
#  function delivers file onto MMI server $HOST as 'hpsatool' user

sub putScpTool($$$;%) { # $RESULT=putScpTool($HOST,$LOCAL_FILE,$REMOTE_FILE;$LOGIN);
  my ($HOST,$LOCAL,$REMOTE,%OPT) = @_;
  my ($LOGIN,$PASSWORD);
  unless( -f $LOCAL ) { 
    warn "Local file '${LOCAL}' is unreachable !\n";
    return 0;
  }
  unless ($LOGIN=$OPT{"login"}) { $LOGIN="hpsatool"; }
  my $DEST="${LOGIN}\@${HOST}:${REMOTE}";
  my $COMMAND="scp ${LOCAL} ${DEST}";
  if ($PASSWORD=$OPT{"password"}) { 
    $ENV{SSHPASS}=$PASSWORD; 
    $COMMAND="sshpass -e | ${COMMAND}"; 
  }
  system($COMMAND);
  return 1;
}

####################################################################### }}} 1
## SSH - C/R file download ############################################ {{{ 1

#FUNCTION:
#  $RESULT=getScpUser($HOST,$LOCAL_FILE,$REMOTE_FILE;%OPT);
#PARAMETERS:
#  $RESULT  - returned value 1-if successfull, otherwise 0
#  $HOST    - IP addres, hostname. fqdn of destination host
#  $LOCAL   - local file name with whole path if necessary
#  $REMOTE  - filename on the destination $HOST
#DESCRIPTION:
#  function delivers file from server $HOST


sub getScpUser($$$;%) { # $RESULT=getScpUser($HOST,$LOCAL_FILE,$REMOTE_FILE;%OPT);
  my ($HOST,$LOCAL,$REMOTE,%OPT) = @_;
  my ($LOGIN,$PASSWORD);

  my $DEST="${HOST}:${REMOTE}";
  if ($LOGIN=$OPT{"login"}) { $DEST="${LOGIN}\@${DEST}"; }
  my $COMMAND="scp ${DEST} ${LOCAL}";
  if ($PASSWORD=$OPT{"password"}) { 
    $ENV{SSHPASS}=$PASSWORD; 
    $COMMAND="sshpass -e | ${COMMAND}"; 
  }
  system($COMMAND);
  unless( -f $LOCAL ) { 
    warn "Remote file '${DEST}' is unreachable !\n";
    return 0;
  }
  return 1;
}

#FUNCTION:
#  $RESULT=getScpRoot($HOST,$LOCAL_FILE,$REMOTE_FILE;%OPT);
#PARAMETERS:
#  $RESULT  - returned value 1-if successfull, otherwise 0
#  $HOST    - IP addres, hostname. fqdn of destination host
#  $LOCAL   - local file name with whole path if necessary
#  $REMOTE  - filename on the destination $HOST
#DESCRIPTION:
#  function delivers file from server $HOST

sub getScpRoot($$$;%) { # $RESULT=getScpRoot($HOST,$LOCAL_FILE,$REMOTE_FILE;%OPT);       
  my ($HOST,$LOCAL,$REMOTE,%OPT) = @_;
  my ($LOGIN,$PASSWORD);

  unless ($LOGIN=$OPT{"login"}) { $LOGIN="root"; }
  my $DEST="${LOGIN}\@${HOST}:${REMOTE}";
  my $COMMAND="scp ${DEST} ${LOCAL}";
  if ($PASSWORD=$OPT{"password"}) { 
    $ENV{SSHPASS}=$PASSWORD; 
    $COMMAND="sshpass -e | ${COMMAND}"; 
  }
  system($COMMAND);
  unless( -f $LOCAL ) { 
    warn "Remote file '${DEST}' is unreachable !\n";
    return 0;
  }
  return 1;
}

#FUNCTION:
#  $RESULT=getScpSudo($HOST,$LOCAL_FILE,$REMOTE_FILE;%OPT);
#PARAMETERS:
#  $RESULT  - returned value 1-if successfull, otherwise 0
#  $HOST    - IP addres, hostname. fqdn of destination host
#  $LOCAL   - local file name with whole path if necessary
#  $REMOTE  - filename on the destination $HOST
#DESCRIPTION:
#  function delivers file from MMI server $HOST

sub getScpSudo($$$;%) { # $RESULT=getScpSudo($HOST,$LOCAL_FILE,$REMOTE_FILE;%OPT);
  my ($HOST,$LOCAL,$REMOTE,%OPT) = @_;
 my ($LOGIN,$PASSWORD);

  unless ($LOGIN=$OPT{"login"}) { $LOGIN="root"; }
  my $DEST="${LOGIN}\@${HOST}:${REMOTE}";
  my $COMMAND="scp ${DEST} ${LOCAL}";
  if ($PASSWORD=$OPT{"password"}) { 
    $ENV{SSHPASS}=$PASSWORD; 
    $COMMAND="sshpass -e | ${COMMAND}"; 
  }
  system($COMMAND);
  unless( -f $LOCAL ) { 
    warn "Remote file '${DEST}' is unreachable !\n";
    return 0;
  }
  return 1;
}

#FUNCTION:
#  $RESULT=getScpTool($HOST,$LOCAL_FILE,$REMOTE_FILE;%OPT);
#PARAMETERS:
#  $RESULT  - returned value 1-if successfull, otherwise 0
#  $HOST    - IP addres, hostname. fqdn of destination host
#  $LOCAL   - local file name with whole path if necessary
#  $REMOTE  - filename on the destination $HOST
#DESCRIPTION:
#  function delivers file from MMI server $HOST as 'hpsatool' user

sub getScpTool($$$;%) { # $RESULT=getScpTool($HOST,$LOCAL_FILE,$REMOTE_FILE;%OPT);
  my ($HOST,$LOCAL,$REMOTE,%OPT) = @_;
  my ($LOGIN,$PASSWORD);

  unless ($LOGIN=$OPT{"login"}) { $LOGIN="hpsatool"; }
  my $DEST="${LOGIN}\@${HOST}:${REMOTE}";
  my $COMMAND="scp ${DEST} ${LOCAL}";
  if ($PASSWORD=$OPT{"password"}) { 
    $ENV{SSHPASS}=$PASSWORD; 
    $COMMAND="sshpass -e | ${COMMAND}"; 
  }
  system($COMMAND);
  unless( -f $LOCAL ) { 
    warn "Remote file '${DEST}' is unreachable !\n";
    return 0;
  }
  return 1;
}

####################################################################### }}} 1
## WMI/SMB - C/R with Windows ######################################### {{{ 1

#FUNCTION:
#  @OUTPUT=crWmiUser($HOST,$CMD;%OPT);
#PARAMETERS:
#  @OUTPUT   - lines of raw output, each without <RC><LF> at its end
#  $HOST     - IP address/ Hostname/ FQDN of the server
#  $CMD      - command, performed on the server
#  $LOGIN    - Login name, optional, hplocaladmin used if empty
#  $PASSWORD - Password, optional, <hplocaladmin_password> used if empty
#DESCRIPTION:
#  Performs a command on remote server.
#  Uses a default user

sub crWmiUser($$;%) {   # @OUT=crWmiUser($HOST,$CMD;%OPT);
  my ($HOST,$COMMAND,%OPT) = @_;
  my ($RDR,$WTR,$ERR);
  my @OUT=();

  #$COMMAND .="\n"; $COMMAND =~ s/\n\n\Z/\n/m;
  #$PID = open2($RDR,$WTR,"winexe","-U",'login%password'
  my $LINE;
  my $PID = open3($WTR,$RDR,$ERR,"winexe","-U",$CRED_USER
               ,"//${HOST}",$COMMAND);
  unless($PID) { die "WMI failure !\n"; }


  while($RDR and ($LINE=<$RDR>)) {
    chomp $LINE;
    unless($LINE =~ /\S/) { next; }
    if($LINE =~ /^Unknown parameter encountered: "/) { next; }
    if($LINE =~ /^Ignoring unknown parameter "/) { next; }
    push @OUT,$LINE;
    #print "#: ${HOST}: ${LINE}\n";
  }
  while($ERR and ($LINE=<$ERR>)) {
    chomp $LINE;
    unless($LINE =~ /\S/) { next; }
    push @OUT,"#- ".$LINE;
    #print "#: ${HOST}: ${LINE}\n";
  }

  if($ERR) { close $ERR; }
  if($WTR) { close $WTR; }
  if($RDR) { close $RDR; }
  waitpid($PID,0);
  return @OUT;
}


#FUNCTION:
#  @OUTPUT=crWmiAdmin($HOST,$CMD;%OPT);
#PARAMETERS:
#  @OUTPUT   - lines of raw output, each without <RC><LF> at its end
#  $HOST     - IP address/ Hostname/ FQDN of the server
#  $CMD      - command, performed on the server
#  $LOGIN    - Login name, optional, hplocaladmin used if empty
#  $PASSWORD - Password, optional, <hplocaladmin_password> used if empty
#DESCRIPTION:
#  Performs a command on remote server.
#  Uses an Administrator user

sub crWmiAdmin($$;%) {  # @OUT=crWmiAdmin($HOST,$CMD;$USER);
  my ($HOST,$COMMAND,%OPT) = @_;
  my ($RDR,$WTR,$ERR);
  my @OUT=();

  #$COMMAND .="\n"; $COMMAND =~ s/\n\n\Z/\n/m;
  #$PID = open2($RDR,$WTR,"winexe","-U",'login%password'
  my $LINE;
  my $PID = open3($WTR,$RDR,$ERR,"winexe","-U",$CRED_ADMIN
               ,"//${HOST}",$COMMAND);
  unless($PID) { die "WMI failure !\n"; }


  while($RDR and ($LINE=<$RDR>)) {
    chomp $LINE;
    unless($LINE =~ /\S/) { next; }
    if($LINE =~ /^Unknown parameter encountered: "/) { next; }
    if($LINE =~ /^Ignoring unknown parameter "/) { next; }
    push @OUT,$LINE;
    #print "#: ${HOST}: ${LINE}\n";
  }
  while($ERR and ($LINE=<$ERR>)) {
    chomp $LINE;
    unless($LINE =~ /\S/) { next; }
    push @OUT,"#- ".$LINE;
    #print "#: ${HOST}: ${LINE}\n";
  }

  if($ERR) { close $ERR; }
  if($WTR) { close $WTR; }
  if($RDR) { close $RDR; }
  waitpid($PID,0);
  return @OUT;
}


#FUNCTION:
#  @OUTPUT=cmdWmiUser($HOST,$COMMANDS;%OPT);
#PARAMETERS:
#  @OUTPUT   - replied lines of output of commands
#  $COMMANDS - Commands to be performed onto server,
#              multiline as one scalar string
#  $LOGIN    - optional - Login to authenticate onto server
#  $PASSWORD - optional - Password to authenticate onto server
#DESCRIPTION:
#  Performs more commands given to fuction as a single 
#  (even multiline) string. Output is collected and returned back
#  Disadvantage of this function is, it relies onto correct 
#  prompt, what may be unusable in some cases.
#  Advantage is more commands given into a single cmd session.

sub cmdWmiUser($$;%) {
  my ($HOST,$TCMDS,%OPT) = @_;
  my ($WRT,$RDR,$ERR,$PID);
  my @RESULT = ();
  my $LINE;
  my @READY;
  my $PROMPTKEY = '3787187834719';

  #$WRT = new IO::Handle;
  #$RDR = new IO::Handle;
  #$ERR = new IO::Handle;
  $PID = open3($WRT,$RDR,$ERR,"winexe","-U",
         $CRED_ADMIN,"//${HOST}","cmd.exe");
  unless($PID) {
    warn "#- WMI trouble with '${HOST}' !\n";
    return;
  }
  #$RDR->autoflush(1);
  my $select = IO::Select->new();
  $select->add($RDR);

  # cutting jam
  $LINE=<$RDR>;
  while(@READY = $select->can_read(1)) {
    getc($RDR);
  }

  # setting prompt
  print $WRT "prompt \$_${PROMPTKEY}\$G\$_\n";
  while(@READY = $select->can_read(1)) {
    getc $RDR;
  }

  $TCMDS .= "\n \n";
  foreach my $CMD (split (/\n/,$TCMDS)) {
    debug ">${CMD}\n";
    print $WRT $CMD."\n";
    my $FIRST=1;
    #while ($LINE=<$RDR>) {
    while (1) {
      $LINE=<$RDR>;
      chomp $LINE;
      next if $LINE =~ /^\s*$/;
      last if $LINE=~/${PROMPTKEY}>\s*$/;
      push @RESULT,$LINE;
      debug " ${LINE}\n";
    }
  }
  print  $WRT "exit\n";
  if($WRT) { close  $WRT; }
  if($RDR) { close  $RDR; }
  if($ERR) { close  $ERR; }
  waitpid $PID,0;
  return @RESULT;
}


#FUNCTION:
#  @OUTPUT=cmdWmiAdmin($HOST,$COMMANDS;%OPT);
#PARAMETERS:
#  @OUTPUT   - replied lines of output of commands
#  $COMMANDS - Commands to be performed onto server,
#              multiline as one scalar string
#  $LOGIN    - optional - Login to authenticate onto server
#  $PASSWORD - optional - Password to authenticate onto server
#DESCRIPTION:
#  Performs more commands given to fuction as a single 
#  (even multiline) string. Output is collected and returned back
#  Disadvantage of this function is, it relies onto correct 
#  prompt, what may be unusable in some cases.
#  Advantage is more commands given into a single cmd session.

sub cmdWmiAdmin($$;%) {
  my ($HOST,$TCMDS,%OPT) = @_;
  my ($WRT,$RDR,$ERR,$PID);
  my @RESULT = ();
  my $LINE;
  my @READY;
  my $PROMPTKEY = '3787187834719';

  #$WRT = new IO::Handle;
  #$RDR = new IO::Handle;
  #$ERR = new IO::Handle;
  $PID = open3($WRT,$RDR,$ERR,"winexe","-U",
         $CRED_ADMIN,"//${HOST}","cmd.exe");
  unless($PID) {
    warn "#- WMI trouble with '${HOST}' !\n";
    return;
  }
  #$RDR->autoflush(1);
  my $select = IO::Select->new();
  $select->add($RDR);

  # cutting jam
  $LINE=<$RDR>;
  while(@READY = $select->can_read(1)) {
    getc($RDR);
  }

  # setting prompt
  print $WRT "prompt \$_${PROMPTKEY}\$G\$_\n";
  while(@READY = $select->can_read(1)) {
    getc $RDR;
  }

  $TCMDS .= "\n \n";
  foreach my $CMD (split (/\n/,$TCMDS)) {
    debug ">${CMD}\n";
    print $WRT $CMD."\n";
    my $FIRST=1;
    #while ($LINE=<$RDR>) {
    while (1) {
      $LINE=<$RDR>;
      chomp $LINE;
      next if $LINE =~ /^\s*$/;
      last if $LINE=~/${PROMPTKEY}>\s*$/;
      push @RESULT,$LINE;
      debug " ${LINE}\n";
    }
  }
  print  $WRT "exit\n";
  if($WRT) { close  $WRT; }
  if($RDR) { close  $RDR; }
  if($ERR) { close  $ERR; }
  waitpid $PID,0;
  return @RESULT;
}

#FUNCTION:
#  cmdWmiShell($HOST;$COMMAND,%OPT);
#PARAMETERS
#  ----     - function does not reply any value
#  $HOST    - IP/HostName/FQDN of a server
#  $COMMAND - command / prompt or something to be 
#              executed before a start of cmd.exe

sub cmdWmiShell($;$%) {
 my ($HOST,$COMMAND,%OPT) = @_;
 unless($COMMAND) { $COMMAND='prompt $G%COMPUTERNAME%$G$S'; }
 system("winexe -U ".$CRED_ADMIN." //${HOST} 'cmd.exe /K ${COMMAND}'");
}

#FUNCTION:
#  $STAT=putSmbUser($HOST,$LOCAL,$REMOTE;$LOGIN,$PASSWORD);
#PARAMETERS:
#  $STAT     - returned value, if 0-then file has not been transfered
#  $HOST     - IP/HostName/FQDN of server
#  $LOCAL    - path to the local file
#  $REMOTE   - path where the file is going to be deployed onto server
#  $LOGIN    - optional - Login to authenticate
#  $PASSWORD - optional - password to authenticate
#DESCRIPTION:
#  copies a file from local onto server

sub putSmbUser($$$;%) { # $RESULT=putSmbUser($HOST,$LOCAL_FILE,$REMOTE_FILE);
  my($HOST,$LOCAL,$REMOTE,%OPT) = @_;
  unless( -f $LOCAL ) {
    warn "File '${LOCAL}' does not exist !\n";
    return 0;
  }
  my $CMD="smbclient //${HOST}/C\$ -U ${CRED_ADMIN} "
         ."-c \"put ${LOCAL} ${REMOTE}\"";
  system($CMD);
  return 1;
}

#FUNCTION:
#  $STAT=getSmbUser($HOST,$LOCAL,$REMOTE;%OPT);
#PARAMETERS:
#  $STAT     - returned value, if 0-then file has not been transfered
#  $HOST     - IP/HostName/FQDN of server
#  $LOCAL    - path to the local file
#  $REMOTE   - path where the file is going to be deployed onto server
#  $LOGIN    - optional - Login to authenticate
#  $PASSWORD - optional - password to authenticate
#DESCRIPTION:
#  copies a file from remote server onto local

sub getSmbUser($$$;%) { # $RESULT=getSmbUser($HOST,$LOCAL_FILE,$REMOTE_FILE);
  my($HOST,$REMOTE,$LOCAL,%OPT) = @_;
  my $CMD="smbclient //${HOST}/C\$ -U ${CRED_ADMIN} "
         ."-c \"get ${REMOTE} ${LOCAL}\"";
  system($CMD);
  return 1;
}

#FUNCTION:
#  $STAT=putSmbAdmin($HOST,$LOCAL,$REMOTE;%OPT);
#PARAMETERS:
#  $STAT     - returned value, if 0-then file has not been transfered
#  $HOST     - IP/HostName/FQDN of server
#  $LOCAL    - path to the local file
#  $REMOTE   - path where the file is going to be deployed onto server
#  $LOGIN    - optional - Login to authenticate
#  $PASSWORD - optional - password to authenticate
#DESCRIPTION:
#  copies a file from local onto server

sub putSmbAdmin($$$;%) { # $RESULT=putSmbAdmin($HOST,$LOCAL_FILE,$REMOTE_FILE);
  my($HOST,$LOCAL,$REMOTE,%OPT) = @_;
  unless( -f $LOCAL ) {
    warn "File '${LOCAL}' does not exist !\n";
    return 0;
  }
  my $CMD="smbclient //${HOST}/C\$ -U ${CRED_ADMIN} "
         ."-c \"put ${LOCAL} ${REMOTE}\"";
  system($CMD);
  return 1;
}

#FUNCTION:
#  $STAT=getSmbAdmin$HOST,$LOCAL,$REMOTE;%OPT);
#PARAMETERS:
#  $STAT     - returned value, if 0-then file has not been transfered
#  $HOST     - IP/HostName/FQDN of server
#  $LOCAL    - path to the local file
#  $REMOTE   - path where the file is going to be deployed onto server
#  $LOGIN    - optional - Login to authenticate
#  $PASSWORD - optional - password to authenticate
#DESCRIPTION:
#  copies a file from remote server onto local

sub getSmbAdmin($$$;%) { # $RESULT=getSmbAdmin($HOST,$LOCAL_FILE,$REMOTE_FILE;%OPT);
  my($HOST,$REMOTE,$LOCAL,%OPT) = @_;
  my $CMD="smbclient //${HOST}/C\$ -U ${CRED_ADMIN} "
         ."-c \"get ${REMOTE} ${LOCAL}\"";
  system($CMD);
  return 1;
}

####################################################################### }}} 1
## crVersion ########################################################## {{{ 1

#FUNCTION:
#  $VERSION=crVersion($HOST);
#PARAMETERS:
#  $VERSION  - returned string of server's version
#  $HOST     - IP/HostName/FQDN of server
#DESCRIPTION:
#  provides a string of $HOST server version.
#  Version does not include a spaces.
#  Version string provides 
#  OStype, Kernel, Architecture, Distro
#  separated by "_" .

sub crVersion($;%) {
  my ($HOST,%OPT) = @_;
  unless($HOST =~ /\S/) { return ""; }

  my @OUT     = (); # command-line output
  my $OSTYPE  = ""; # Linux or Windows
  my $KERNEL  = ""; # something like 6.1.7601 or 2.6.9 ...
  my $ARCHIT  = ""; # 64-bit or 32-bit
  my $PATCH   = ""; # "3" for Linux SuSE, "Service Pack 1" for Windows 
  my $DISTRO  = ""; # Windows Caption, or 1st line of /etc/(redhat|SuSE)-release
  my $VERSION = ""; # final string including version

  if(qaWindows($HOST)) {
    @OUT=grep /=/,crWmiAdmin($HOST,
      "wmic os get Caption,Version,OSArchitecture,CSDVersion /format:list");
  } elsif(qaLinux($HOST)) {
    @OUT=crSshRoot($HOST,
      "(uname -a;cat /etc/redhat-release;cat /etc/SuSE-release)");
  }


  foreach my $XLINE (@OUT) {
    my $LINE=$XLINE; 
       $LINE=~s/^\s+//; $LINE=~s/\s+$//;

    if($LINE =~ /^Linux .* #1 SMP/) {
      $OSTYPE="Linux";
      $KERNEL=(split(/\s+/,$LINE))[2];
      if($LINE =~ "x86_64") { $ARCHIT="64-bit"; }
      else                  { $ARCHIT="32-bit"; }
      if($KERNEL =~ /el[56]/) { $DISTRO = "Red Hat"; }
      next;
    }

    if($LINE =~ /^Red Hat/) { 
      $OSTYPE="Linux";
      $DISTRO = $LINE; 
      next; 
    }

    if($LINE =~ /^SUSE/) { 
      $OSTYPE="Linux";
      $DISTRO = $LINE; 
      next; 
    }

    if(($LINE =~ /^PATCHLEVEL\s+=/) and ($DISTRO =~ /^SUSE/)) { 
      $PATCH=$LINE; 
      $PATCH=~s/^.*=\s+//; 
      next; 
    }

    if($LINE =~ /^Caption=/) { 
      $OSTYPE="Windows";
      $DISTRO=$LINE; 
      $DISTRO=~s/^\S+=//; 
      next; 
    }

    if($LINE =~ /^CSDVersion=/) { 
      $OSTYPE="Windows";
      $PATCH=$LINE; 
      $PATCH=~s/^\S+=//; 
      next; 
    }

    if($LINE =~ /^OSArchitecture=/) { 
      $OSTYPE="Windows";
      $ARCHIT=$LINE; 
      $ARCHIT=~s/^\S+=//; 
      if($ARCHIT=~/64/) { 
        $ARCHIT="64-bit"; 
      } else {
        $ARCHIT="32-bit"; 
      }
      next;
    }

    if($LINE =~ /^Version=/) { 
      $OSTYPE="Windows";
      $KERNEL=$LINE; 
      $KERNEL=~ s/^\S+=//; 
      next; 
    }
  } # end of @OUT analysis

  $VERSION = "UNKNOWN!";
  unless($OSTYPE =~ /Linux|Windows/) { return $VERSION; }
  unless($ARCHIT =~ /(32|64)-bit/)   { return $VERSION; }
  $KERNEL =~ s/_/-/g;
  $PATCH  =~ s/ |_/-/g; 
  $DISTRO =~ s/ |_/-/g; $DISTRO =~ s/\(|\)|\[|\]|;|,//g;
  $VERSION="${OSTYPE}_${KERNEL}_${ARCHIT}_${DISTRO}_${PATCH}";
  $VERSION=~s/_$//;
  
  my $PT=qaRef($HOST);
  $PT->{".ver"} = $VERSION;
  return $VERSION; 
    
}

####################################################################### }}} 1
## crService crHostname ############################################### {{{ 1


#FUNCTION:
#  $BOOL=crService($HOST,$SERVICE,%OPT)
#PARAMETERS:
#  $BOOL  - 1=if service is running 0=otherwise
#  $HOST  - Hostname/IP/FQDN of server
#DESCRIPTION:
#  Checks whether the servioce is
#  running on the server or not.

sub crService($$;%) {  # $HSERVICES=crService($HOST,$SERVICE);
  my ($HOST,$SERV,%OPT) = @_;
  my $PT=qaRef($HOST);
  unless($PT) { return 0; }

  if(qaWindows($HOST)) {
    my @OUT_SERV = crWmiAdmin($HOST,"sc query ${SERV}");
    my @OUT_CONF = crWmiAdmin($HOST,"sc qc ${SERV}");
    my $RESULT   = 0;
       $RESULT   = 1 if
                   (scalar(grep /^\s+STATE\s+:\s+[0-9]+\s+RUNNING/,@OUT_SERV) > 0)
                   #and (scalar(grep /^\s+START_TYPE\s+:\s+[0-9]+\s+AUTO_START/,@OUT_CONF) > 0)
                   ;
    if($OPT{verbose}) { println (@OUT_SERV,@OUT_CONF); }
    return $RESULT;
  } elsif (qaLinux($HOST)) {
    warn "crService is not implemented for Linux platform yet !";
    return 0;
  }
}


#FUNCTION:
#  $HNAME=crHostname($HOST;%OPT);
#PARAMETERS:
#  $HNAME   - detected hostname ... configuret onto server
#  $HOST    - resolvable Hostname / IP / FQDN of server
#DESCRIPTION:
#  returns the hostname configured onto server
#  uses WMI or SSH and usual `hostname` command
#  to detect a name

sub crHostname($;%){    # $HNAME=crHostname($HOST;%OPT);
  my ($HOST,%OPT) = @_;
  my $PT=qaRef($HOST);
  unless($PT) { return 0; }

  if(qaWindows($HOST)) {
  my $RESULT = join ('',crWmiAdmin($HOST,'cmd.exe /C echo %COMPUTERNAME%'));
     $RESULT =~ s/^\s+//; $RESULT =~ s/\s+$//;
  return $RESULT;
  } elsif (qaLinux($HOST)) {
    warn "crHostname is not implemented for Linux platform yet !";
    return "";
  }
}

####################################################################### }}} 1
## crEnv crEnvAll ##################################################### {{{ 1


#FUNCTION:
#  \%PT=crEnvAll($HOST;%OPT);
#PARAMETERS:
#  $PT    - returned pointer to HASH including whole Environment
#  $HOST  - IP/ Hostname/ FQDN of server
#  %OPT   - will see later
#DESCRIPTION:
#  Takes all server system environment variables into HASH
#  HASH is stored in $CONFIG->{NODE_<server>}->{.Env}
#  So details can be taken by
#  $PROMPT = $CONFIG->{NODE_<server>}->{.Env}->{PROMPT};

sub crEnvAll($;%) {
  my ($HOST,%OPT) = @_;
  my $PT=qaRef($HOST);
  unless($PT) { return undef; }

  # obtaining Environment from Server
  my @OUT = ();
  if(qaWindows($HOST)) {
    @OUT=crWmiAdmin($HOST,"set");
  } elsif(qaLinux($HOST)) {
    @OUT=crSshRoot($HOST,"set");
  }
  
  # Parsing the Output
  my $NEW = $PT->{".Env"} = {};
  foreach my $ITEM (@OUT) {
    next unless $ITEM=~/^\S+=/;
    my ($KEY,$VAL) = split(/=/,$ITEM,2);
    $NEW->{$KEY} = $VAL;
  }

  # Returning result
  return $NEW;
}

#FUNCTION:
#  $BOOL=crListenTcp($HOST,$PORT;%OPT);
#PARAMETERS:
#  $BOOL  - returned value 1=Listening 0=NOT_Listening
#  $HOST  - IP/ Hostname/ FQDN of server
#  $PORT  - TCP port to be checked
#  %OPT   - will see later
#DESCRIPTION:
#  Checks localy on server whether it listens on TCP $PORT.
#  If server listens, the function returns a true(1).
#  Else the function returns a false (0).

sub crEnv($$;%) { # $HPORTS=crListenTCP($HOST,$KEY;%OPT);
  my ($HOST,$KEY,%OPT) = @_;
  unless($KEY) { return ""; }
  my $PT=qaRef($HOST);
  unless($PT)  { return ""; }
  my $PX;
  my $RESULT = "";

  # geting/refreshing Environment from server
  if($OPT{"fetch"}) { 
    crEnvAll($HOST,%OPT); 
  } elsif ( not exists $PT->{".Env"}) {
    crEnvAll($HOST,%OPT); 
  }

  # getting value of particular variable
  $PX  = $PT->{".Env"};
  unless($PX) { return ""; }
  unless($RESULT= $PX->{$KEY}) { return ""; }

  # returning result
  return $RESULT;

}


####################################################################### }}} 1
## crListenTcp crListenTcpAll ######################################### {{{ 1


#FUNCTION:
#  $BOOL=crListenTcpAll($HOST;%OPT);
#PARAMETERS:
#  $BOOL  - returned value 1=Listening 0=NOT_Listening
#  $HOST  - IP/ Hostname/ FQDN of server
#  %OPT   - will see later
#DESCRIPTION:
#  Checks localy on server whether it listens on TCP $PORT.
#  If server listens, the function returns a true(1).
#  Else the function returns a false (0).

sub crListenTcpAll($;%) {
  my ($HOST,%OPT) = @_;
  my $PT=qaRef($HOST);
  unless($PT) { return undef; }

  my @OUT = ();
  if(qaWindows($HOST)) {
    @OUT=crWmiAdmin($HOST,"netstat -an");
  } elsif(qaLinux($HOST)) {
    @OUT=crSshRoot($HOST,"netstat -antu");
  }

  my $XA = $PT->{".ListenTcp"} = [];
  @$XA = @OUT;
  return $XA;
}

#FUNCTION:
#  $BOOL=crListenTcp($HOST,$PORT;%OPT);
#PARAMETERS:
#  $BOOL  - returned value 1=Listening 0=NOT_Listening
#  $HOST  - IP/ Hostname/ FQDN of server
#  $PORT  - TCP port to be checked
#  %OPT   - will see later
#DESCRIPTION:
#  Checks localy on server whether it listens on TCP $PORT.
#  If server listens, the function returns a true(1).
#  Else the function returns a false (0).

sub crListenTcp($$;%) { # $HPORTS=crListenTCP($HOST,$PORT);
  my ($HOST,$PORT,%OPT) = @_;
  my $PT=qaRef($HOST);
  my $PX;
  my @OUT = ();
  my $RESULT = 0;
  unless($PT) { return 0; }

  if($OPT{"fetch"}) { 
    crListenTcpAll($HOST,%OPT); 
  } elsif ( not exists $PT->{".ListenTcp"}) {
    crListenTcpAll($HOST,%OPT); 
  }
  $PX  = $PT->{".ListenTcp"};
  @OUT = @$PX;

  if(qaWindows($HOST)) {
    $RESULT = scalar grep /^\s+TCP\s+\S+:${PORT}\s+\S+\s+LISTENING/,@OUT;
    $RESULT = 1 if $RESULT > 0;
    return $RESULT;

  } elsif(qaLinux($HOST)) {
    warn "crListenTCP is not implemented for Linux platform yet !";
    return 0;
  }
}


####################################################################### }}} 1
## crInstalled crInstalledAll ######################################### {{{ 1

#FUNCTION:
#  $BOOL=crInstalledAll($HOST;%OPT);
#PARAMETERS:
#  $BOOL  - returned value 1=Listening 0=NOT_Listening
#  $HOST  - IP/ Hostname/ FQDN of server
#  %OPT   - will see later
#DESCRIPTION:
#  Collects all software installed onto server

sub crInstalledAll($;%) {
  my ($HOST,%OPT) = @_;
  my $PT=qaRef($HOST);
  unless($PT) { return undef; }

  # initiation of local variables
  my @OUT  = ();
  my @NEW  = ();
  my $NAME = "";
  my $VER  = "";
  my $ITEM = "";

  # handling Windows WMI Products
  if(qaWindows($HOST)) {
    @OUT=crWmiAdmin($HOST,"wmic product get Name,Version /format:list",%OPT);
    foreach $ITEM (@OUT) {
      if($ITEM =~ /^Name=/) { 
         $NAME=$ITEM; 
         next; 
      } elsif($ITEM =~ /^Version=/) { 
         $VER=$ITEM; 
         push @NEW, "${NAME};${VER}"; 
         next; 
      }
    }

  # handling Linux RPM packages
  } elsif(qaLinux($HOST)) {
    @OUT=crSshRoot($HOST,"rmp -qa",%OPT);
    foreach $ITEM (@OUT) {
     ($NAME,$VER) = $ITEM =~ m/^(.*)-([^-]+-[^-]+)$/;
     push @NEW, "Name=${NAME};Version=${VER}";
    }
  }

  # putting collected data into 
  # $CONFIG->{HOST_<server>}->{.Installed}
  my $XA = $PT->{".Installed"} = [];
  @$XA = @NEW;
  return $XA;
}


#FUNCTION:
#  $VERSION=crInstalled($HOST,$SOFTWARE;%OPT);
#PARAMETERS:
#  $VERSION  - returned string including a software version
#  $HOST     - IP/HNAME/FQDN of server
#DESCRIPTION:
#  Provides a version of installed software
#  or empty string if software has not been installed yet.

sub crInstalled($$;%) { # $VERSION=crInstalled($HOST,$SOFWARE;%OPT);
  my ($HOST,$SOFTWARE,%OPT) = @_;

  # Chasing the server details
  my $PT=qaRef($HOST);
  unless($PT) { return 0; }

  # initiation
  my $PX;
  my @OUT = ();
  my $RESULT = 0;

  # fetching collected packages
  if($OPT{"fetch"}) { 
    crInstalledAll($HOST,%OPT); 
  } elsif ( not exists $PT->{".Installed"}) {
    crInstalledAll($HOST,%OPT); 
  }
  $PX  = $PT->{".Installed"};
  #@OUT = @$PX;

  foreach my $ITEM (@$PX) {
    my ($NAME,$VER) = split(/\s*;Version=\s*/,$ITEM,2);
    $NAME =~ s/^Name=//;
    $VER  =~ s/\s//g;
    if($NAME =~ /${SOFTWARE}/) { return $VER; }
  }
  return "";
}


####################################################################### }}} 1
## crHpreportCheck #################################################### {{{ 1

#FUNCTION:
#  $COUNT=crHpreportCheck($HOST;%OPT);
#PARAMETERS:
#  $COUNT  - answers how many time the FQDN has been found  in HPreporter
#  $HOST   - IP/Hname/FQDN of server
#DESCRIPTION:
#  performs the check whether the server has been found in HPreporter

sub crHpreportCheck($;%) {
  my ($HOST,%OPT) = @_;
  unless($HOST) { return ""; }
  my %DATA  = qaServer($CONFIG,$HOST);  
  unless(%DATA) { return ""; }

  my $FQDN = $DATA{"FQDN"}; 
  unless($FQDN) { return ""; }

  my $HPREPORT = $DATA{"HPREPORT_ADDR"};
  unless($HPREPORT =~ /\S+/) { $HPREPORT=$DATA{"SITE"}."-hpreport"; }

  my $QUERY = "select systemname from reporter.dbo.systems where systemname ='${FQDN}';";  
  my @OUT = crWmiUser($HPREPORT,"sqlcmd -U openview -P openview -Q \"${QUERY};\"",%OPT);

  my $RESULT = join ("", grep( /${FQDN}/,@OUT ));
  $RESULT =~ s/\s//g;
  return $RESULT;
}
####################################################################### }}} 1
## Q/A API - config related ########################################### {{{ 1

#FUNCTION: 
#  $LOADED_COUNT=qaLoad(\%CONFIG,$FILE_NAME)
#PARAMETERS:
#  $LOADED_COUNT - number of valid sections loaded
#  \%CONFIG      - reference to hash where a config should be loaded
#  $FILE_NAME    - File Name of Configuration file
#DESCRIPTION:
#  Simply reads a .INI (Windows 3) style configuration file into HASH

sub qaLoad($$) {     # $LOADED_COUNT=qaLoad($CONFIG,$FILE_CONF);
  my ($CONF,$FNAME) = @_;
  my $FILE;
  my $PREFIX="";

  # Opening a file
  unless( -f $FNAME ) {
    warn "File ${FNAME} unreachable !";
    return 0;
  }
  unless(open($FILE,"<",$FNAME)) {
    warn "File ${FNAME} unreachable ! Check its attributes. \n";
    return 0;
  }
  debug "Configuration File '${FNAME}' opened.";

  # Main cycle of reading
  while(my $LINE=<$FILE>) {
    # handling line
    chomp $LINE;
    next if $LINE=~/^\s*$/;
    next if $LINE=~/^\s*#/;
    next if $LINE=~/^\s*\./; # /^\./ are reserved for (memory) internal purposes
    # spliting the laft and right side of line
    $LINE =~ s/^\s+//; $LINE =~ s/\s+$//;

    # handling new prefix
    if($LINE =~/^\[\s*\S+\s*\]$/) {
      $PREFIX = uc $LINE;
      $PREFIX =~ s/^\[\s*//;
      $PREFIX =~ s/\s*\]$//;
      unless(exists $CONF->{$PREFIX}) {
        $CONF->{$PREFIX}={};
        debug "creating PREFIX '${PREFIX}'";
      }
      debug "PREFIX changed to '${PREFIX}'";
      next;
    }

    # standard lines key=value
    my($KEY,$VALUE) = split(/\s*=\s*/,$LINE);
    unless($KEY) {
      warn "wrong syntax at '${LINE}' !";
      next;
    }
    $KEY = uc $KEY;

    # adding details to the config file
    if($PREFIX) {
      $CONF->{$PREFIX}->{$KEY} = $VALUE;
    } else {
      $CONF->{$KEY} = $VALUE;
    }
  }

  # closure  of configureation file
  close $FILE;
  return scalar keys %$CONF;
}


#FUNCTION:
#  $COUNT=qaSave(\%CONFIG,$FILE_NAME);
#PARAMETERS:
#  $COUNT   - number of items written (0 in case of error)
#  \%CONFIG - reference/pointer to configuration we would like to write
#  $FILE_NAME  - File Name of saved configuration
#DESCRIPTION:
#  Function saves the HASH including 2-level configuration into file

sub qaSave($$) {     # $RESULT=qaSave($CONFIG,$FILE_CONF);
  my($CONFIG,$FILE_NAME) = @_;
  my $FH;

  unless(open($FH,">",$FILE_NAME)) {
    die "Error ! Not possible to write a file '${FILE_NAME}' !\n";
  }
  foreach my $PREFIX (sort keys %$CONFIG) {

    next if $PREFIX =~ /^\./;
    # scalars outside of sections
    unless(ref ($CONFIG->{$PREFIX})) {
      my $VALUE = $CONFIG->{$PREFIX};
      print $FH "${PREFIX}=${VALUE}\n";

    # whole sections
    } else {
      my $REF=$CONFIG->{$PREFIX};
      print $FH "[${PREFIX}]\n";
      foreach my $ITEM (sort keys %$REF) {
        next if $ITEM =~ /^\./;  # /^\./ should be in memory only
        my $VALUE = $REF->{$ITEM};
        print $FH "  ${ITEM}=${VALUE}\n";
      }
      print $FH "\n";
    }
  }
  close $FH;
}

#FUNCTION:
#  %SERVER=qaServer($HOST);
#PARAMETERS:
#  %SERVER  - Hash including all details about the server
#  $HOST    - resolvable IP address, Hostname, FQDN ($CONFIG HOST_hostname) of the server
#DESCRIPTION:
#  provides all known details about HOST_server.
#  If the server's section includes a SITE=<site_name>, then
#  qaServer extends returned Hash by related SITE details.

sub qaServer($;$) {      # %SERVER=qaServer(\%CONFIG,$DEVIP/$HNAME/$FQDN) ...taking from HOSTS.ini
  my ($CONF,$REFSRV) = @_;
  my %RESULT = ();
  my $REFSIT = "";
  my $FLAG = 0;

  # if refference to config item had been provided
  if(($REFSRV =~ /^HOST_/i) and (exists $CONF->{uc $REFSRV})) {
    %RESULT = %{$CONF->{uc $REFSRV}};
    if(exists $RESULT{"SITE"}) {
      my $REFSIT = uc $RESULT{"SITE"};
      if(exists $CONF->{"SITE_".$REFSIT}) {
        %RESULT = ( %RESULT,%{$CONF->{"SITE_".$REFSIT}});
      }
    }
    return %RESULT;
  }

  $REFSRV = lc $REFSRV;
  foreach my $ITEM (keys %$CONF) {

    next unless($ITEM =~ /^HOST_/);
    my $P = $CONF->{$ITEM};

    $FLAG = 1 if ($REFSRV eq (lc($P->{"FQDN"})));
    $FLAG = 1 if ($REFSRV eq (lc($P->{"HNAME"})));
    $FLAG = 1 if ($REFSRV eq (lc($P->{"DEVIP"})));
    $FLAG = 1 if ($REFSRV eq (lc($P->{"SHORT"})));
    $FLAG = 1 if ($REFSRV eq (lc($P->{"RLI"})));

    if($FLAG){
      %RESULT = %$P;
      $RESULT{".ref"} = $P;       # internal - for efficiency purposes
      $RESULT{".key"} = $ITEM;  # internal - for efficiency purposes
      $REFSIT = uc $P->{"SITE"};
      debug "server found '${ITEM}'";
      last;
    }
  }

  # if case the server SITE exists, the
  # server details are extended by them.
  if(exists $CONF->{"SITE_".$REFSIT}) {
    #%RESULT = ( %RESULT,%{$CONF->{"SITE_".$REFSIT}});
    %RESULT = ( %{$CONF->{"SITE_".$REFSIT}}, %RESULT);
  }

  # returning server details
  #if($FLAG) {
     return %RESULT;
  #} else {
  #  return undef;
  #}
}

####################################################################### }}} 1
## Q/A API - credentials related ###################################### {{{ 1

sub qaEncrypt($);      # $CODE=qaEncrypt($TEXT);
sub qaDecrypt($);      # $TEXT=qaDecrypt($CODE);
sub qaLogin($);        # $LOGIN=qaLogin($USER);
sub qaPassword($);     # $PASSWORD=qaPassword($USER);
sub qaMethod($);       # $METGHOD=qaMethod($USER);    # provides an authentication method (a part of ccredentials)

####################################################################### }}} 1
## Q/A API - Interpretor related ###################################### {{{ 1

sub qaAttrib($$);      # $RESULT=qa($ARGX,\@ARGV); 
sub qaInput($$);       # $LINE=qaInput($PROMPT);
sub qaExec($$);        # $RESULT=qaExec($LINE,$RULES);
sub qaShell($);        # $RESULT=qaExec($RULES);
sub qaSecret($);       # ($LOGIN,$PASSWORD)=qaSecret($USER);

####################################################################### }}} 1
## Q/A API - qaServer related ######################################### {{{ 1


#FUNCTION:
#  \%PT=qaRef($HOST);
#USAGE:
#  crVersion($HOST);
#  my $VX3   = qaRef($HOST)->{".ver"}; 
#PARAMETERS:
#  $PT    - Pointer to hash containing all server related details in $CONFIG
#  $HOST  - hostname, IP address, FQDN, Server_Reference ...
#           what ever related to the particular server $HOST
#DESCRIPTION:
#  Provides a pointer reference to the hash with all server details in $CONFIG

sub qaRef($) {
  my $HOST = shift;
  my %DETAILS = qaServer($CONFIG,$HOST);
  if(exists $DETAILS{".ref"}) {
    return $DETAILS{".ref"};
  } else {
    return undef;
  }
}


#FUNCTION:
#  $HOST_KEY=qaKey($HOST);
#USAGE:
#  crVersion($HOST);
#  my $VX2   = $CONFIG->{qaKey($HOST)}->{".ver"};
#PARAMETERS:
#  $HOST_KEY - Key usable as refference $TP=$CONFIG{$HOST_KEY} ....
#  $HOST  - hostname, IP address, FQDN, Server_Reference ...
#           what ever related to the particular server $HOST
#DESCRIPTION:
#  provides an IP address of required server

sub qaKey($) {
  my $HOST = shift;
  my %DETAILS = qaServer($CONFIG,$HOST);
  if(exists $DETAILS{".key"}) {
    return $DETAILS{".key"};
  } else {
    return "";
  }
}


#FUNCTION:
#  $DEVIP=qaDevip($HOST);
#PARAMETERS:
#  $DEVIP - IP address of server
#  $HOST  - hostname, IP address, FQDN, Server_Reference ...
#           what ever related to the particular server $HOST
#DESCRIPTION:
#  provides an IP address of required server

sub qaDevip($) {
  my $HOST = shift;
  my %DETAILS = qaServer($CONFIG,$HOST);
  if(exists $DETAILS{"DEVIP"}) {
    return $DETAILS{"DEVIP"};
  } else {
    return "";
  }
}

#FUNCTION:
#  $DEVIP=qaHname($HOST);
#PARAMETERS:
#  $DEVIP - IP address of server
#  $HOST  - hostname, IP address, FQDN, Server_Reference ...
#           what ever related to the particular server $HOST
#DESCRIPTION:
#  provides hostname of required server

sub qaHname($) {
  my $HOST = shift;
  my %DETAILS = qaServer($CONFIG,$HOST);
  if(exists $DETAILS{"HNAME"}) {
    return $DETAILS{"HNAME"};
  } else {
    return "";
  }
}

#FUNCTION:
#  $DEVIP=qaFQDN($HOST);
#PARAMETERS:
#  $DEVIP - IP address of server
#  $HOST  - hostname, IP address, FQDN, Server_Reference ...
#           what ever related to the particular server $HOST
#DESCRIPTION:
#  provides fully qualified domain name of required server

sub qaFQDN($) {
  my $HOST = shift;
  my %DETAILS = qaServer($CONFIG,$HOST);
  if(exists $DETAILS{"FQDN"}) {
    return $DETAILS{"FQDN"};
  } else {
    return "";
  }
}

#FUNCTION:
#  $DEVIP=qaRLI($HOST);
#PARAMETERS:
#  $DEVIP - IP address of server
#  $HOST  - hostname, IP address, FQDN, Server_Reference ...
#           what ever related to the particular server $HOST
#DESCRIPTION:
#  provides RLI of required server

sub qaRLI($) {
  my $HOST = shift;
  my %DETAILS = qaServer($CONFIG,$HOST);
  if(exists $DETAILS{"RLI"}) {
    return $DETAILS{"RLI"};
  } else {
    return "";
  }
}

#FUNCTION:
#  $DEVIP=qaHSPA_OID($HOST);
#PARAMETERS:
#  $DEVIP - IP address of server
#  $HOST  - hostname, IP address, FQDN, Server_Reference ...
#           what ever related to the particular server $HOST
#DESCRIPTION:
#  provides  HSPA_OID for required server

sub qaHPSA_OID($) {
  my $HOST = shift;
  my %DETAILS = qaServer($CONFIG,$HOST);
  if(exists $DETAILS{"HPSA_OID"}) {
    return $DETAILS{"HPSA_OID"};
  } else {
    return "";
  }
}

#FUNCTION:
#  $DEVIP=qaHSPA_OID($HOST);
#PARAMETERS:
#  $DEVIP - IP address of server
#  $HOST  - hostname, IP address, FQDN, Server_Reference ...
#           what ever related to the particular server $HOST
#DESCRIPTION:
#  provides  HSPA_GW_ADDR for required server
#  HPSA_GW_ADDR is defined per site

sub qaHPSA_GW_ADDR($) {
  my $HOST = shift;
  my %DETAILS = qaServer($CONFIG,$HOST);
  if(exists $DETAILS{"HPSA_GW_ADDR"}) {
    return $DETAILS{"HPSA_GW_ADDR"};
  } else {
    return "";
  }
}

#FUNCTION:
#  $WAVE=qaWave($HOST);
#PARAMETERS:
#  $WAVE  - the name of wave in format CUSTOMER-waveM.m,
#  $HOST  - hostname, IP address, FQDN, Server_Reference ...
#           what ever related to the particular server $HOST
#DESCRIPTION:
#  provides  the mane of Migration Wave.
#  It's usefull to construct some file names

sub qaWave($) {
  my $HOST = shift;
  my %DETAILS = qaServer($CONFIG,$HOST);
  if(exists $DETAILS{"WAVE"}) {
    return $DETAILS{"WAVE"};
  } elsif ($CONFIG->{"COMMON"}->{"WAVE"}) {
    return $CONFIG->{"COMMON"}->{"WAVE"};
  } else {
    return "";
  }
}

#FUNCTION:
#  $CUSTOMER=qaCustomer($HOST);
#PARAMETERS:
#  $CUSTOMER - customer name (have a look to `hppw -a` to list them all)
#  $HOST     - hostname, IP address, FQDN, Server_Reference ...
#           what ever related to the particular server $HOST
#DESCRIPTION:
#  provides a name of customer. That name may be used to
#  find a root password onto customer systems etc.
#  To list all customers, please use a command `hppw -a`
#  or `hppw -a | sed 's/^root-password-//'` to list
#  customer names only.

sub qaCustomer($) {
  my $HOST = shift;
  my %DETAILS = qaServer($CONFIG,$HOST);
  if(exists $DETAILS{"CUSTOMER"}) {
    return $DETAILS{"CUSTOMER"};
  } elsif ($CONFIG->{"COMMON"}->{"CUSTOMER"}) {
    return $CONFIG->{"COMMON"}->{"CUSTOMER"};
  } else {
    return "";
  }
}


#FUNCTION:
#  $PLATFORM=qaPlatform($HOST);
#PARAMETERS:
#  $PLATFORM - returned platform details
#  $HOST     - hostname, IP address, FQDN, Server_Reference ...
#           what ever related to the particular server $HOST
#DESCRIPTION:
#  Provides a platform details

sub qaPlatform($) {
  my $HOST = shift;
  my %DETAILS = qaServer($CONFIG,$HOST);
  if(exists $DETAILS{"PLATFORM"}) {
    return $DETAILS{"PLATFORM"};
  } elsif ($CONFIG->{"COMMON"}->{"PLATFORM"}) {
    return $CONFIG->{"COMMON"}->{"PLATFORM"};
  } else {
    return "";
  }
}





#FUNCTION:
#  $HPSA_ADDR=qaHpsatooAddr($HOST);
#PARAMETERS:
#  $OMUP_ADDR - IP address of related OMU-P server
#  $HOST      - hostname, IP address, FQDN, Server_Reference ...
#           what ever related to the particular server $HOST
#DESCRIPTION:
#  provides an IP address of HPSA Tool Server

sub qaHpsatoolAddr($) {
  my $HOST = shift;
  my %DETAILS = qaServer($CONFIG,$HOST);
  if(exists $DETAILS{"HPSATOOL_ADDR"}) {
    return $DETAILS{"HPSATOOL_ADDR"};
  } else {
    return "";
  }
}

#FUNCTION:
#  $OMUP_ADDR=qaHpsatoolName($HOST);
#PARAMETERS:
#  $OMUP_ADDR - IP address of related OMU-P server
#  $HOST      - hostname, IP address, FQDN, Server_Reference ...
#           what ever related to the particular server $HOST
#DESCRIPTION:
#  provides an FQDN of HPSA Tool Server

sub qaHpsatoolName($) {
  my $HOST = shift;
  my %DETAILS = qaServer($CONFIG,$HOST);
  if(exists $DETAILS{"HPSATOOL_NAME"}) {
    return $DETAILS{"HPSATOOL_NAME"};
  } else {
    return "";
  }
}

#FUNCTION:
#  $OMUP_ADDR=qaOmupAddr($HOST);
#PARAMETERS:
#  $OMUP_ADDR - IP address of related OMU-P server
#  $HOST      - hostname, IP address, FQDN, Server_Reference ...
#           what ever related to the particular server $HOST
#DESCRIPTION:
#  provides an IP address of OMU-Primary server

sub qaOmupAddr($) {
  my $HOST = shift;
  my %DETAILS = qaServer($CONFIG,$HOST);
  if(exists $DETAILS{"OMUP_ADDR"}) {
    return $DETAILS{"OMUP_ADDR"};
  } else {
    return "";
  }
}

#FUNCTION:
#  $OMUP_ADDR=qaOmupName($HOST);
#PARAMETERS:
#  $OMUP_ADDR - IP address of related OMU-P server
#  $HOST      - hostname, IP address, FQDN, Server_Reference ...
#           what ever related to the particular server $HOST
#DESCRIPTION:
#  provides an FQDN of OMU-Primary server

sub qaOmupName($) {
  my $HOST = shift;
  my %DETAILS = qaServer($CONFIG,$HOST);
  if(exists $DETAILS{"OMUP_NAME"}) {
    return $DETAILS{"OMUP_NAME"};
  } else {
    return "";
  }
}

#FUNCTION:
#  $OMUP_CERT=qaOmupCert($HOST);
#PARAMETERS:
#  $OMUP_ADDR - IP address of related OMU-P server
#  $HOST      - hostname, IP address, FQDN, Server_Reference ...
#           what ever related to the particular server $HOST
#DESCRIPTION:
#  provides a Certificate of OMU-[PS] to be monitored

sub qaOmupCert($) {
  my $HOST = shift;
  my %DETAILS = qaServer($CONFIG,$HOST);
  if(exists $DETAILS{"OMUP_CERT"}) {
    return $DETAILS{"OMUP_CERT"};
  } else {
    return "";
  }
}

#FUNCTION:
#  $REPORT=qaHpreport($HOST);
#PARAMETERS:
#  $REPORT - IP address of related HP-Reporter server
#  $HOST   - hostname, IP address, FQDN, Server_Reference ...
#           what ever related to the particular server $HOST
#DESCRIPTION:
#  provides an IP address of HP-Reporter server

sub qaHpreport($) {
  my $HOST = shift;
  my %DETAILS = qaServer($CONFIG,$HOST);
  if(exists $DETAILS{"HPREPORT_ADDR"}) {
    return $DETAILS{"HPREPORT_ADDR"};
  } else {
    return "";
  }
}

#FUNCTION:
#  $ORCHIP=qaOrchip($HOST);
#PARAMETERS:
#  $ORCHIP - IP address of related Orchestrator server
#  $HOST   - hostname, IP address, FQDN, Server_Reference ...
#           what ever related to the particular server $HOST
#DESCRIPTION:
#  provides an IP address of HP-Reporter server

sub qaOrchip($) {
  my $HOST = shift;
  my %DETAILS = qaServer($CONFIG,$HOST);
  if(exists $DETAILS{"ORCHESTRATOR_ADDR"}) {
    return $DETAILS{"ORCHESTRATOR_ADDR"};
  } else {
    return "";
  }
}

#FUNCTION:
#  $BOOL=qaLinux($HOST);
#PARAMETERS:
#  $BOOL   - returned value 1=if linux, otherwise 0
#  $HOST   - IP/ Hostname/ FQDN of server
#DESCRIPTION:
#  answers true if HOSTS.ini contains 'linux' within
#  the PLATFORM value of $HOST server section
#  Otherwise the function returns 0.
#  Function is intended to speed-up OS detection of
#  the server.

sub qaLinux($) {       #$BOOL=qaLinux($HOST);        # qaServer based, gives 1 if host is Linux
  my $HOST = shift;
  my %DETAILS = qaServer($CONFIG,$HOST);
  unless(exists $DETAILS{"PLATFORM"}) {
    if(exists $DETAILS{"PLAX"}) {
      if($DETAILS{"PLAX"} =~ /^lnx/i) {
        return 1;
      }
    }
    return 0;
  }
  if( $DETAILS{"PLATFORM"} =~ /linux/i) {
    return 1;
  } elsif( $DETAILS{"PLATFORM"} =~ /^lnx/i) {
    return 1;
  } else {
    return 0;
  }
}

#FUNCTION:
#  $BOOL=qaWindows($HOST);
#PARAMETERS:
#  $BOOL   - returned value 1=if linux, otherwise 0
#  $HOST   - IP/ Hostname/ FQDN of server
#DESCRIPTION:
#  answers true if HOSTS.ini contains 'windows' within
#  the PLATFORM value of $HOST server section
#  Otherwise the function returns 0.
#  Function is intended to speed-up OS detection of
#  the server.

sub qaWindows($) {    #$BOOL=qaWindows($HOST);      # qaServer based, gives 1 if host is Windows
  my $HOST = shift;
  my %DETAILS = qaServer($CONFIG,$HOST);
  unless(exists $DETAILS{"PLATFORM"}) {
    if(exists $DETAILS{"PLAX"}) {
      if($DETAILS{"PLAX"} =~ /^win/i) {
        return 1;
      }
    }
    return 0;
  }
  if( $DETAILS{"PLATFORM"} =~ /windows/i) {
    return 1;
  } elsif( $DETAILS{"PLATFORM"} =~ /^win/i) {
    return 1;
  } else {
    return 0;
  }
}

#FUNCTION:
#  $TYPE=qaType($HOST);
#PARAMETERS:
#  $TYPE   - returned value ... usually OS,DB or SAP
#  $HOST   - hostname, IP address, FQDN, Server_Reference ...
#           what ever related to the particular server $HOST
#DESCRIPTION:
#  provides an IP address of HP-Reporter server

sub qaType($) {
  my $HOST = shift;
  my %DETAILS = qaServer($CONFIG,$HOST);
  if(exists $DETAILS{"TYPE"}) {
    return $DETAILS{"TYPE"};
  } else {
    return "";
  }
}

#FUNCTION:
#  $DPCELL=qaDpcell($HOST);
#PARAMETERS:
#  $DPCELL - returned value ... usually OS,DB or SAP
#  $HOST   - hostname, IP address, FQDN, Server_Reference ...
#           what ever related to the particular server $HOST
#DESCRIPTION:
#  provides an IP address of HP-Reporter server

sub qaDpcell($) {
  my $HOST = shift;
  my %DETAILS = qaServer($CONFIG,$HOST);
  if(exists $DETAILS{"DPCELL"}) {
    return $DETAILS{"DPCELL"};
  } else {
    return "";
  }
}

#FUNCTION:
#  $OPSFILE=qaOPSFILE($HOST);
#PARAMETERS:
#  $OPSFILE - returned value ... usually OS,DB or SAP
#  $HOST    - hostname, IP address, FQDN, Server_Reference ...
#             what ever related to the particular server $HOST
#DESCRIPTION:
#  simply it return a OPSFILE

sub qaOPSFILE($) {
  my $HOST = shift;
  my %DETAILS = qaServer($CONFIG,$HOST);
  if(exists $DETAILS{"OPSFILE"}) {
    return "Install/".$DETAILS{"OPSFILE"};
  } else {
    return "";
  }
}

#FUNCTION:
#  $FILE=qaOpswareFile($HOST);
#PARAMETERS:
#  $FILE  - OpsWare Installation File
#  $HOST  - IP/Hostname/FQDN of server
#DESCRIPTION:
#  Translates version of Operating Systems, detected
#  on the server directly into an Opsware Installation File
#  Also it checks whether the file is reachable.
#  If the OS version is unknown or if the file for detected
#  version is not found in a local Install/ sub-folder,
#  then an empty string is returned.
#NOTE:
#  Before you use qaOpswareFile, you MUST perform crVersion
#  or somehow to fullfil the $CONFIG{HOST_server}->{".ver"},
#  by correct OS Version String related to the server.

sub qaOpswareFile($) {
  my $HOST = shift;
  my $VER  = "";
  my $FILE = "";
  my ($OSTYPE,$KERNEL,$PLATFORM,$DISTRO,$PATCH);

  # Obtaining the OS Version ... taken previously by crVersion from the server
  # and decomposition of OS_VERSION string onto 5 inportant details
  # my $XVER = "60.0.64851.2";
  my $XVER = "*";
  my %DETAILS = qaServer($CONFIG,$HOST);
  if(exists $DETAILS{"OPSFILE"}) {
    $FILE=$DETAILS{"OPSFILE"};
    if( -f "Install/${FILE}") { 
      return "Install/${FILE}"; 
    }
    if( -f $ENV{"HOME"}."/HPSA-Agent-Install/${FILE}") { 
      return $ENV{"HOME"}."/HPSA-Agent-Install/${FILE}"; 
    }
  }
  if((exists $DETAILS{"PLAX"}) or (exists $DETAILS{"PLATFORM"})){
    my $PLAX;
    if(exists $DETAILS{"PLATFORM"}) { $PLAX=$DETAILS{"PLATFORM"}; }
    if(exists $DETAILS{"PLAX"})     { $PLAX=$DETAILS{"PLAX"}; }

    if($PLAX eq  "LnxRHEL5x32"  ) { $FILE="opsware-agent-${XVER}-linux-5SERVER";        }
    if($PLAX eq  "LnxRHEL5x64"  ) { $FILE="opsware-agent-${XVER}-linux-5SERVER-X86_64"; }
    if($PLAX eq  "LnxRHEL6x32"  ) { $FILE="opsware-agent-${XVER}-linux-6SERVER";        }
    if($PLAX eq  "LnxRHEL6x64"  ) { $FILE="opsware-agent-${XVER}-linux-6SERVER-X86_64"; }
    if($PLAX eq  "LnxSUSE11x32" ) { $FILE="opsware-agent-${XVER}-linux-SLES-11";        }
    if($PLAX eq  "LnxSUSE11x64" ) { $FILE="opsware-agent-${XVER}-linux-SLES-11-X86_64"; }
    if($PLAX eq  "Win2008r0x32" ) { $FILE="opsware-agent-${XVER}-win32-6.0.exe";        }
    if($PLAX eq  "Win2008r0x64" ) { $FILE="opsware-agent-${XVER}-win32-6.0-X64.exe";    }
    if($PLAX eq  "Win2008r2x64" ) { $FILE="opsware-agent-${XVER}-win32-6.1-X64.exe";    }
    if($PLAX eq  "Win2012r0x64" ) { $FILE="opsware-agent-${XVER}-win32-6.2-X64.exe";    }
    if($PLAX eq  "Win2012r2x64" ) { $FILE="opsware-agent-${XVER}-win32-6.3-X64.exe";    }

    my @AFILE=(glob("Intsall/${FILE}"),glob($ENV{"HOME"}."/HPSA-Agent-Install/${FILE}"));
    $FILE=pop @AFILE;
    if( -f $FILE) { return $FILE; }
  }

  if(exists $DETAILS{".ver"}) {
    $VER = $DETAILS{".ver"};
    ($OSTYPE,$KERNEL,$PLATFORM,$DISTRO,$PATCH) = split( /_/,$VER,5);

    # handling all Windows DISTROs here
    if($OSTYPE eq "Windows") {
      if(($KERNEL =~ /^6\.1\./) and ($PLATFORM eq "64-bit")) {
        $FILE = "Install/opsware-agent-${XVER}-win32-6.1-X64.exe";
      } elsif (($KERNEL =~ /^6\.0\./) and ($PLATFORM eq "32-bit")) {
        $FILE = "Install/opsware-agent-${XVER}-win32-6.0.exe";
      } elsif (($KERNEL =~ /^6\.0\./) and ($PLATFORM eq "64-bit")) {
        $FILE = "Install/opsware-agent-${XVER}-win32-6.0-X64.exe";
      } elsif (($KERNEL =~ /^6\.2\./) and ($PLATFORM eq "64-bit")) {
        $FILE = "Install/opsware-agent-${XVER}-win32-6.2-X64.exe";
      } elsif (($KERNEL =~ /^6\.3\./) and ($PLATFORM eq "64-bit")) {
        $FILE = "Install/opsware-agent-${XVER}-win32-6.2-X64.exe";
      } else {
        warn "UNKNOWN OS VERSION `${VER}` !";
      }
    
    # handling all  Linux DISTROs here
    } elsif ($OSTYPE eq "Linux") {
      if(($DISTRO =~ /^Red-Hat/) and ($KERNEL =~ /\.el5/) and ($PLATFORM eq "64-bit")) {
        $FILE = "Install/opsware-agent-${XVER}-linux-5SERVER-X86_64";
      } elsif (($DISTRO =~ /^Red-Hat/) and ($KERNEL =~ /\.el5/) and ($PLATFORM eq "32-bit")) {
        $FILE = "Install/opsware-agent-${XVER}-linux-5SERVER";

      } elsif (($DISTRO =~ /^Red-Hat/) and ($KERNEL =~ /\.el6/) and ($PLATFORM eq "64-bit")) {
        $FILE = "Install/opsware-agent-${XVER}-linux-6SERVER-X86_64";
      } elsif (($DISTRO =~ /^Red-Hat/) and ($KERNEL =~ /\.el6/) and ($PLATFORM eq "32-bit")) {
        $FILE = "Install/opsware-agent-${XVER}-linux-6SERVER";

      } elsif (($DISTRO =~ /^SUSE-Linux-Enterprise-Server-11/) and ($PLATFORM eq "64-bit"))   {
        $FILE = "Install/opsware-agent-${XVER}-linux-SLES-11-X86_64";
      } elsif (($DISTRO =~ /^SUSE-Linux-Enterprise-Server-11/) and ($PLATFORM eq "32-bit"))   {
        $FILE = "Install/opsware-agent-${XVER}-linux-SLES-11";
      } else {
        warn "UNKNOWN OS VERSION `${VER}` !";
      }
    }
    my @AFILE = glob($FILE);
    $FILE=pop @AFILE;
    # Checking existence of Installer File
    if( -f $FILE ) {
      return $FILE;
    } else {
      warn "Opsware Installation File '${FILE}' is unreachable !";
      return "";
    }

  # handling error if crVersion($HOST) hes not been performed yet.
  } else {
    warn "perform crVersion before qaOpswareFile !";
    return "";
  }
  
}


#FUNCTION:
#  $MCAFEE_ATTR=qaMcafeeAttr($HOST);
#PARAMETERS:
#  $MCAFEE_ATTR - McAfee rfelated attribute for the antivirus installation
#  $HOST        - hostname, IP address, FQDN, Server_Reference ...
#                 what ever related to the particular server $HOST
#DESCRIPTION:
#  simply it return a OPSFILE

sub qaMcafeeAttr($) {  #i $MCAFEE_ATTR=qaMcafeeAttr($);# qaServer based, gives an Attribute for McAfee antivirus installation
  my $HOST = shift;
  my %DETAILS = qaServer($CONFIG,$HOST);
  if(exists $DETAILS{"MCAFEE_ATTR"}) {
    return $DETAILS{"MCAFEE_ATTR"};
  } else {
    return "";
  }
}

####################################################################### }}} 1
## Initialization ##################################################### {{{ 1

if( -t STDOUT) { $MODE_COLOR=1; }
else           { $MODE_COLOR=0; }

$TAKE_FROM  = dirname (__FILE__); 

if( -f "HOSTS.ini" ) { qaLoad($CONFIG,"HOSTS.ini"); }

if(exists($ENV{"CRED_ADMIN"})) { 
  $CRED_ADMIN=$ENV{"CRED_ADMIN"}; 
} else {
  warn "Environment variable 'CRED_ADMIN' id not set !";
}
if(exists($ENV{"CRED_USER"})) {
  $CRED_USER=$ENV{"CRED_USER"};
} else {
  warn "Environment variable 'CRED_USER' is not set (OMC) !";
}
if(exists($ENV{"SSHPASS"})) {
} else {
  warn "Environment variable SSHPASS is not set !";
}

1;

####################################################################### }}} 1

# --- end ---

