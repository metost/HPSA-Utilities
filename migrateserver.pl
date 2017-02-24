#!/usr/bin/perl
###############################################
# 
# PE_UTILITY_MIGRATION_WRAPPER_V1M.PL 
# IMPLEMENTED ON DEMAND by Ondrej Duras
#
###############################################

## Defaults ########################################################### {{{ 1

use strict;
use warnings;
use subs 'die';
use subs 'warn';
use subs 'exit';
use POSIX;
use IPC::Open2;
use Data::Dumper;

our $VERSION=2016.113001;
our $HHOSTS={};
our $HSITES={};
our $HTASKS={};
our $HOSSEQ={};
our $DOTS = "...............................";
our $FHOUT;           # Handler for logging
our $FILEOUT = "";    # Filename where logging is stored.
our $MODE_DEBUG = ""; # terminal monitor / terminal no monitor
our $ASK_EXECUTE = 0; # exec prompt (=1); exec no prompt (=0)  ...show exec
our $ASK_EXECID  = 0; # exec desc   (=1); exec no desc   (=0)  ...show exec
our $ASK_BULLSHT = 1; # translates command-line based on requirements from CHE
our $ASK_PATH    = 0; # =0 PATH has not been modified yet, =1 PATH has been mofified already

####################################################################### }}} 1
## Redefinitions ###################################################### {{{ 1

sub exit(;$) {
  my $EXITCODE = shift;
  unless(defined $EXITCODE) { 
    $EXITCODE=0; 
  }
  CORE::exit($EXITCODE);
}

sub warn(;$) {
  my $MSG=shift;
  unless(defined $MSG) { $MSG="Warning !\n"; }
  print STDERR $MSG;
}

sub die($;$) {
  my($MSG,$EXITCODE) = @_;
  unless(defined $MSG) { $MSG="Error !\n"; }
  unless(defined $EXITCODE) { $EXITCODE=1; }
  warn $MSG;
  exit($EXITCODE);
}

sub debug($) {
  my $MSG=shift;
  return unless $MODE_DEBUG;
  print $MSG;
}

####################################################################### }}} 1
## loadHostsIni ####################################################### {{{ 1

sub loadHostsIni() {
  my $FH;
  my $MODE=0;
  my $HOST="";
  my $SITE="";
  my $PT=undef;

  $HHOSTS={};
  $HSITES={};
  open $FH,"<","HOSTS.ini" or die "Unreachable HOSTS.ini !\n";
  while(my $LINE=<$FH>) {
    chomp $LINE;
    next if $LINE=~/^\s*#/;
    next if $LINE=~/^\s*$/;
    $LINE =~ s/^\s+//; $LINE =~ s/\s+$//;
    if($LINE =~ /^\[HOST_\S+/) {
      $HOST = $LINE;
      $HOST =~ s/^\[HOST_//;
      $HOST =~ s/\]$//;
      unless(exists $HHOSTS->{$HOST}) {
        $HHOSTS->{$HOST}={};
      }
      $PT=$HHOSTS->{$HOST};
      $MODE = 1;
      next;
    }
    if($LINE =~ /^\[SITE_\S+/) {
      $SITE = $LINE;
      $SITE =~ s/^\[SITE_//;
      $SITE =~ s/\]$//;
      unless(exists $HSITES->{$SITE}) {
        $HSITES->{$SITE}={};
      }
      $PT=$HSITES->{$SITE};
      $MODE = 2;
      next;
    }
    next unless $MODE;
    next unless $LINE =~ /=/;
    my($KEY,$VAL)=split(/\s*=\s*/,$LINE,2);
    $PT->{$KEY}=$VAL;
  }
  close $FH;
  print "${DOTS} loaded.\rHOSTS.ini \n";
}

####################################################################### }}} 1
## loadRefTasksCfg #################################################### {{{ 1

sub loadRefTasksCfg() {
  my $FH;

  $HTASKS={};
  open $FH,"<","REFTASKS.cfg" or die "Unreachable REFTASKS.cfg !\n";
  while(my $LINE=<$FH>) {
    chomp $LINE;
    next if $LINE=~/^\s*#/;
    next if $LINE=~/^\s*$/;

    $LINE =~ s/^\s+//; $LINE =~ s/\s+$//;
    my($ID,$DESC,$CMD)=split(/\s*;\s*/,$LINE,3);
    $HTASKS->{$ID}={};
    $HTASKS->{$ID}->{"DESC"}=$DESC;
    $HTASKS->{$ID}->{"CMD"}=$CMD;
  }
  close $FH;
  print "${DOTS} loaded.\rREFTASKS.cfg \n";
}

####################################################################### }}} 1
## loadTaskListCfg #################################################### {{{ 1

sub loadTaskListCfg() {
  my $FH;

  $HOSSEQ={};
  open $FH,"<","TASKLIST.cfg" or die "Unreachable TASKLIST.cfg !\n";
  while(my $LINE=<$FH>) {
    chomp $LINE;
    next if $LINE=~/^\s*#/;
    next if $LINE=~/^\s*$/;

    $LINE =~ s/^\s+//; $LINE =~ s/\s+$//;
    my($KEY,$VAL)=split(/\s*;\s*/,$LINE,2);
    $HOSSEQ->{$KEY}=$VAL;
  }
  close $FH;
  print "${DOTS} loaded.\rTASKLIST.cfg \n";
}

####################################################################### }}} 1
## getServer getSequence getRef ####################################### {{{ 1


sub getRef($) {
  my $SEARCH=shift;
  my %SERVER=();
  my $PT;
  my $REF = "";
  unless(exists($HHOSTS->{$SEARCH})) { 
   foreach my $ITEM ( keys %$HHOSTS) {
     my $PT = $HHOSTS->{$ITEM};
     if(    $PT->{"DEVIP"} eq $SEARCH) { $REF = $ITEM; last; }
     elsif( $PT->{"HNAME"} eq $SEARCH) { $REF = $ITEM; last; }
     elsif( $PT->{"FQDN"}  eq $SEARCH) { $REF = $ITEM; last; }
     elsif( $PT->{"RLI"}   eq $SEARCH) { $REF = $ITEM; last; }
   }
   unless($REF) { return ""; }
  } else { 
    $REF=$SEARCH; 
  }
  return $REF
}


sub getServer($) {
  my $SEARCH=shift;
  my %SERVER=();
  my $PT;
  my $REF = "";
  unless(exists($HHOSTS->{$SEARCH})) { 
   foreach my $ITEM ( keys %$HHOSTS) {
     my $PT = $HHOSTS->{$ITEM};
     if(    $PT->{"DEVIP"} eq $SEARCH) { $REF = $ITEM; last; }
     elsif( $PT->{"HNAME"} eq $SEARCH) { $REF = $ITEM; last; }
     elsif( $PT->{"FQDN"}  eq $SEARCH) { $REF = $ITEM; last; }
     elsif( $PT->{"RLI"}   eq $SEARCH) { $REF = $ITEM; last; }
     elsif( $PT->{"SHORT"} eq $SEARCH) { $REF = $ITEM; last; }
   }
   unless($REF) { return ""; }
  } else { 
    $REF=$SEARCH; 
  }
  $PT = $HHOSTS->{$REF};
  %SERVER = %$PT;
  if((exists $SERVER{"SITE"}) and (exists $HSITES->{$SERVER{"SITE"}})) {
    $PT=$HSITES->{$SERVER{"SITE"}};
    %SERVER = (%SERVER,%$PT);
  }
  return %SERVER;
}

sub getSequence($) {
  my $REF=shift;
  my @ASEQ = ();
  unless(exists $HHOSTS->{$REF}) { return @ASEQ; }
  
  my %SERVER=getServer($REF);
  my $SEQ="";
  if(defined $SERVER{"PLATFORM"}) { 
    $SEQ = $SERVER{"PLATFORM"}; 
  } 
  if(defined  $SERVER{"PLAX"}) { 
    $SEQ = $SERVER{"PLAX"}; 
  }
  if($SERVER{"TYPE"})  { $SEQ .= "-".$SERVER{"TYPE"}; }
  else                 { $SEQ .= "-OS"; }
  if($SERVER{"BACKUP"}){ $SEQ .= "-".$SERVER{"BACKUP"}; }
  else                 { $SEQ .= "-DP"; }
  unless(exists $HOSSEQ->{$SEQ}) { return @ASEQ; }
  @ASEQ = split(/\s*;\s*/,$HOSSEQ->{$SEQ});
  return @ASEQ;
}

####################################################################### }}} 1
## MANUALS ############################################################ {{{ 1

our $MANUAL_VERSION = <<__END__;
\n\n\n
PRODUCT NAME:
  Wrapper for Server Automation

FILE:
  migrateserver.pl

DESCRIPTION:
  A Wrapper intended for the automation of migration.
  This script should control the sequences of migration
  tasks depending on all technical data provided before
  the migration into configuration files.

USAGE:
  migrateserver.pl [-p] <HNAME/DEVIP/FQDN/RLI>
  migrateserver.pl [-p] <HNAME/DEVIP/FQDN/RLI> [TaskID]
  migrateserver.pl [-p] <HNAME/DEVIP/FQDN/RLI> [StartID-StopID]

PARAMETERS:
  HNAME  - Hostname of the server
  DEVIP  - Primary Management IP address of the server
  FQDN   - FQDN of the server
  RLI    - HPe specific server ID within the QRS system
  -p     - Prompt mode - asking to proceed before each task
  -v     - Verbose mode
  -      - non-customized dry syntax mode (internal tshoot)
  
PRODUCT LICENCE:
  This product can be used under terms of GPLv3 licence.

SEE ALSO:
  https://github.hpe.com/ondrej-duras/

VERSION:
   ${VERSION}(1M) by Ing. Ondrej DURAS, Capt. (Ret.)

FEATURES:
   (1M) - customized for HPe/VPC/PE team colleagues.\n\n
__END__

####################################################################### }}} 1
## Prototypes ######################################################### {{{ 1

sub help($);
sub showServer($);
sub showAllServers($);
sub showServerDetail($);
sub showAllTasks($);
sub execTask($);
sub showAllSequences($);
sub showSequence($);
sub execSequence($);

####################################################################### }}} 1
## shexec shexport #################################################### {{{ 1

sub shexport($;%) {
  my ($REF,%OPT) = @_;
  my $EXPORT="";
  $REF =~ s/^s\S+\s+e\S+\s+//;
  unless(exists $HHOSTS->{$REF}) { 
    warn "Wrong server name !\n"; 
    return "";
  }
  my %SERVER=getServer($REF);
  unless(exists $SERVER{"DEVIP"}) { 
    warn "No DEVIP defined for server ${REF} !\n";
    return $EXPORT; 
  }
  unless(exists $SERVER{"HNAME"}) { 
    warn "No HNAME defined for server ${REF} !\n";
    return $EXPORT; 
  }
  unless(exists $SERVER{"FQDN"}) { 
    warn "No FQDN defined for server ${REF} !\n";
    return $EXPORT; 
  }
  foreach my $KEY ( sort keys %SERVER) {
    my $VAL = $SERVER{$KEY};
    $EXPORT .= "export ${KEY}=${VAL}\n";
  }
  return $EXPORT;
}

sub shask($$) {
  my($CMD,$MODE) = @_;
  unless($MODE) { return 0; }
  print "\033[1;32m\n";
  print "${CMD}"; 
  print "\033[m\n";

  my $LINE;
  while(1) {
    print "Proceed (y=yes/n=no/q=quit) ? >> ";
    $LINE=<STDIN>;
    chomp $LINE;
    if($LINE =~ /^y/i)    { return 0; }
    if($LINE =~ /^n/i)    { return 1; }
    if($LINE =~ /^[qe]/i) { exit 0; }
    warn "Try again !\n";
  }
}

sub shexec($$;%) {
  my($SERVER,$CMD,%OPT) = @_;
  my @ACMD = split(/\n/,shexport($SERVER) . $CMD);
  my $FHIN; 
  my $FHOUT;
  my $PID;
  my $EXIT  = 0;
  my $CEXIT = 0;
  
  if(shask($CMD,$ASK_EXECUTE)) { return 0; }
  $PID = open2($FHOUT,$FHIN,"bash 2>1");
  unless($PID) { die "Error: Open2 issue !\n"; }
  foreach my $IN (@ACMD) {
    print $FHIN "${IN}\n";
    debug "${0}::shexec:${IN}\n";
  }
  print $FHIN "\nexit \$\?\n";
  close $FHIN;
  while(my $LINE=<$FHOUT>) {
    if($LINE =~ /^#\&EXIT\([0-9+]\)$/) {
       $EXIT = $LINE; chomp $EXIT; 
       $EXIT =~ s/[^0-9]//g;
       $EXIT = int($EXIT);
    }
    if($LINE =~ /^#\&PASS/) {
       $EXIT = 0;
    }
    if($LINE =~ /^#\&FAIL/) {
       $EXIT = 1;
    }
    print $LINE;
  }
  close $FHOUT;
  waitpid($PID, &WNOHANG);
  $CEXIT=$? >> 8;
  unless($EXIT) { $EXIT=$CEXIT; }
  return $EXIT;
}

sub shexecid($$;%) {
  my($SERVER,$TASK,%OPT) = @_;
  unless(exists $HTASKS->{$TASK}) {
    warn "Wrong TaskID !\n";
  }
  my $PT  = $HTASKS->{$TASK};
  my $CMD = $PT->{"CMD"};
  my $DESC= $PT->{"DESC"};
  if(shask($DESC,$ASK_EXECID)) { return 0; }
  return shexec($SERVER,$CMD,%OPT);
}

####################################################################### }}} 1
## bs_mode ############################################################ {{{ 1

# Applies all non-standard customisation required by
# end user.
sub bs_mode() {
  my $REF   = "";
  my $TASK  = "";
  my $START = "";
  my $STOP  = "";
  my $CMD   = "";

  # command-line detections
  while(my $ARGX = shift(@ARGV)) {
    if($ARGX eq "execute") { $ASK_BULLSHT = 0; last; }
    if($ARGX eq "-")  {      $ASK_BULLSHT = 0; last; }
    if($ARGX eq '-p') {      $ASK_EXECID  = 1; next; }
    if($ARGX eq '-v') { $MODE_DEBUG  = '.*';   next; }
    unless($REF) { $REF = getRef($ARGX); print "#: getRef => ${REF}\n"; next; }
    if($ARGX =~ /-/)  { ($START,$STOP)=split(/-/,$ARGX); last; }
    else { $TASK = $ARGX; last; }
  }

  # command-line stansformation to native mode
  if($REF) {
    if($TASK) {               $CMD="execute server ${REF} start ${TASK} stop ${TASK}"; }
    elsif($START and $STOP) { $CMD="execute server ${REF} start ${START} stop ${STOP}"; }
    elsif($START) {           $CMD="execute server ${REF} start ${START}"; }
    elsif($STOP)  {           $CMD="execute server ${REF} stop  ${STOP}"; }
    else {                    $CMD="execute server ${REF}"; }
    @ARGV=split(/\s+/,$CMD);
    $ASK_BULLSHT = 0;
  }
  
  # adding PATHs
  unless($ASK_PATH) {
    my $PATH=$ENV{"PATH"};
    if( -d "/home/hpsatool/PE_Utility_Migration/HPSA_tasks") {
      $PATH .= ":/home/hpsatool/PE_Utility_Migration/HPSA_tasks";
      debug "#: PATH: adding /home/hpsatool/PE_Utility_Migration/HPSA_tasks\n";
    } else { 
      debug "#- PATH: Issue with /home/hpsatool/PE_Utility_Migration/HPSA_tasks !\n";
    }
    if( -d "/home/hpsatool/PE_Utility_Migration/Linux_tasks") {
      $PATH .= ":/home/hpsatool/PE_Utility_Migration/Linux_tasks";
      debug "#: PATH: adding /home/hpsatool/PE_Utility_Migration/Linux_tasks\n";
    } else {
      debug "#- PATH: Issue with /home/hpsatool/PE_Utility_Migration/Linux_tasks !\n";
    }
    if( -d "/home/hpsatool/PE_Utility_Migration/Win2008_tasks") {
      $PATH .= ":/home/hpsatool/PE_Utility_Migration/Win2008_tasks";
      debug "#: PATH: adding /home/hpsatool/PE_Utility_Migration/Win2008_tasks\n";
    } else {
      debug "#- PATH: Issue with /home/hpsatool/PE_Utility_Migration/Win2008_tasks !\n";
    }
    if( -d "/home/hpsatool/PE_Utility_Migration/Win2012_tasks") {
      $PATH .= ":/home/hpsatool/PE_Utility_Migration/Win2012_tasks";
      debug "#: PATH: adding /home/hpsatool/PE_Utility_Migration/Win2012_tasks\n";
    } else {
      debug "#- PATH: Issue with /home/hpsatool/PE_Utility_Migration/Win2012_tasks !\n";
    }
    $ENV{"PATH"} = $PATH;
    $ASK_PATH = 1;
    print "${DOTS} updated.\rPATH \n";
  }

  # adding $IP and $HOST
  foreach my $ITEM (keys %$HHOSTS) {
    my $PT    = $HHOSTS->{$ITEM};
    my $DEVIP;
    if(exists $PT->{"DEVIP"} ) { $PT->{"IP"} = $PT->{"DEVIP"}; }
    elsif(exists $PT->{"IP"} ) { $PT->{"DEVIP"} = $PT->{"IP"}; }
    else { debug "#- HOST.ini HOST_${ITEM} : missing DEVIP key !\n"; }

    my $HNAME;
    if(exists $PT->{"HNAME"})   { $PT->{"HOST"}  = $PT->{"HNAME"}; }
    elsif(exists $PT->{"HOST"}) { $PT->{"HNAME"} = $PT->{"HOST"};  }
    else { debug "#- HOST.ini HOST_${ITEM} : missing HNAME key !\n"; }
  } 
  debug "#: HOST.ini BS_MODE update done.\n";

  # detection of mode.
  if($ASK_BULLSHT) {
    print "${DOTS} bs_mode.\rcontinues \n";
  } else {
    print "${DOTS} native.\rcontinues \n";
  }
}

####################################################################### }}} 1
## Command Rules ###################################################### {{{ 1

our $HCMD = {
  '10;sh(ow)?\s+ver(sion)?' => sub { print $MANUAL_VERSION; },
  '11;(exit|quit)' => sub { print "bye.\n"; exit; },
  '12;reload' => sub { loadHostsIni(); loadRefTasksCfg(); loadTaskListCfg(); },
  '14;sh(ow)?\s+ser\S*\s+\S+' => \&showServer,
  '12;sh(ow)?\s+ser\S*\s+\S+\s+detail' => \&showServerDetail,
  '13;sh(ow)?\s+task\s+\S+'   => \&showTask,
  '13;sh(ow)?\s+seq\S*\s+\S+' => \&showSequence,
  '14;sh(ow)?\s+all\s+ser.*'  => \&showAllServers,
  '14;sh(ow)?\s+all\s+tasks?' => \&showAllTasks,
  '14;sh(ow)?\s+all\s+seq'    => \&showAllSequences,
  '14;sh(ow)?\s+exp\S*\s+\S+' => sub { my $X=shift; $X =~ s/^sh(ow)?\s+exp\S*\s+//; print shexport($X); },
  '15;exec\S*\s+task\s+\S+\s+on\s+\S+' => sub { execTask('none ' . shift); },
  '15;exec\S*\s+seq\S*\s+\S+\s+on\s+\S+' => sub { execSequence('none '. shift); },
  '15;exec\S*\s+seq\S*\s+\S+\s+on\s+\S+\s+start\s+\S+' => sub { execSequence('start '. shift); },
  '15;exec\S*\s+seq\S*\s+\S+\s+on\s+\S+\s+stop\s+\S+'  => sub { execSequence('stop '. shift); },
  '15;exec\S*\s+seq\S*\s+\S+\s+on\s+\S+\s+start\s+\S+\s+stop\s+\S+' => sub { execSequence('startstop '. shift); },
  '16;exec\S*\s+on\s+\S+' => sub { execServer('none ' . shift); },
  '16;exec\S*\s+on\s+\S+\s+start\s+\S+' => sub { execServer('start ' . shift); },
  '16;exec\S*\s+on\s+\S+\s+stop\s+\S+' => sub { execServer('stop ' . shift); },
  '16;exec\S*\s+on\s+\S+\s+start\s+\S+\s+stop\s+\S+' => sub { execServer('startstop ' . shift); },
  '16;exec\S*\s+ser\S*\s+\S+' => sub { execServer('none ' . shift); },
  '16;exec\S*\s+ser\S*\s+\S+\s+start\s+\S+' => sub { execServer('start ' . shift); },
  '16;exec\S*\s+ser\S*\s+\S+\s+stop\s+\S+' => sub { execServer('stop ' . shift); },
  '16;exec\S*\s+ser\S*\s+\S+\s+start\s+\S+\s+stop\s+\S+' => sub { execServer('startstop ' . shift); },
  '17;exec\S*\s+pr\S*'      => sub{ $ASK_EXECUTE = 1; print "Prompting mode ON.\n"; },
  '17;exec\S*\s+no\s+pr\S*' => sub{ $ASK_EXECUTE = 0; print "Prompting mode OFF.\n";},
  '17;exec\S*\s+des\S*'     => sub{ $ASK_EXECID  = 1; print "Description mode ON.\n";},
  '17;exec\S*\s+no\s+des\S*'=> sub{ $ASK_EXECID  = 0; print "Description mode OFF.\n";},
  '17;sh(ow)?\s+exec\S*'    => sub{ print "${DOTS} ${ASK_EXECUTE}\rPrompt \n";print "${DOTS} ${ASK_EXECID}\rDescription \n"; },
  '7777;term(inal)?\s+mon(itor)?' => sub { $MODE_DEBUG = ".*"; debug "#: monitor on...\n"; },
  '7777;term(inal)?\s+no\s+mon(itor)?' => sub { debug "#: monitor off...\n"; $MODE_DEBUG = ""; },
  '7777;!.*'  => sub { my $LINE=shift; $LINE=~s/^!//;  system($LINE); },
  '7777;\..*' => sub { my $LINE=shift; $LINE=~s/^\.//; eval($LINE); },
  '7777;help.*' => \&help,
  '7777;\?.*'   => \&help
};

############################################za########################### }}} 1
## Command Interpretor ################################################ {{{ 1
#our $ARGC = scalar @ARGV;
#unless($ARGC) { print $MANUAL_DESC; exit; }

loadHostsIni(); loadRefTasksCfg(); loadTaskListCfg();

# Customisation required by Mourad Bouti
if($ASK_BULLSHT) {
  bs_mode();
}

if($ASK_BULLSHT) { print $MANUAL_VERSION; exit; }

# Non-Interactive - command asargument on command-line
if(scalar(@ARGV)) {
  my $LINE = "";
  foreach my $ARGX (@ARGV) {
    $LINE .= " ${ARGX}";
  }
  $LINE =~ s/^\s+//;
  debug "#: ${LINE}\n";

  my $FLAG=0;
  foreach my $ITEM (sort keys %$HCMD) {
    my ($IDX,$REG) = split(/;/,$ITEM,2);
    next unless ($LINE=~ /^${REG}$/);
    $HCMD->{$ITEM}($LINE);
    $FLAG=1;
    last;
  }
  unless($FLAG) { print "\033[1;31mError: Wrong command !\033[m\n"; }
  exit;
}

# interactive - prompt
print "\n\n\n\033[1;33mPE Utility Migration wrapper\033[m\n"
    . "Vesrion: ${VERSION} ( help ? )\n\n";
while(1) {
  print "\033[1;33mWrapper>\033[m ";
  my $LINE=<STDIN>;
  chomp $LINE;
  next if $LINE =~ /^\s*$/;
  next if $LINE =~ /^\s*#/;
  $LINE =~ s/^\s+//; $LINE =~ s/\s+$//;

  my $FLAG=0;
  foreach my $ITEM (sort keys %$HCMD) {
    my ($IDX,$REG) = split(/;/,$ITEM,2);
    next unless ($LINE=~ /^${REG}$/);
    $HCMD->{$ITEM}($LINE);
    $FLAG=1;
    last;
  }
  unless($FLAG) { print "\033[1;31mError: Wrong command !\033[m\n"; }
}

exit;


####################################################################### }}} 1
## help ############################################################### {{{ 1

sub help($) {
my $LINE=shift;
my $WHAT=$LINE;
my  $MANUAL_HELP = <<__END__;
exit                     - terminates this script
show server <server_ref> - shows details of server
show task <task_ref>     - show details of task
show sequence <seq_ref>  - show tasks of sequence
show all servers         - show list of all servers references
show all tasks           - show list of all tasks
show all sequences       - show list of all sequence names
exec task <task_ref> on <server_ref> [start <task_ref>] [stop <task_ref>]
exec sequence <sequnce_ref> on <server_ref> [start <task_ref>] [stop <task_ref>]
exec on  <server_ref> [start <task_ref>] [stop <task_ref>]
exec server <server_ref> [start <task_ref>] [stop <task_ref>]
exec [no] [prompt|description] - troubleshooting modes ON/OFF
__END__

  $WHAT =~ s/^(\?|help)\s*//;
  unless($WHAT =~ /\S/) { $WHAT='.*'; }
  foreach my $ITEM (split(/\n/,$MANUAL_HELP)) {
    unless($ITEM =~ /${WHAT}/) { next; }
    print "${ITEM}\n";
  }
}

####################################################################### }}} 1
## showServer showAllServers showServerDetail ######################### {{{ 1

sub showServer($) {
  my $LINE=shift;
  my $REF = $LINE;
  $REF =~ s/^\S+\s+\S+\s+//;
  unless(getRef($REF)) { 
    warn "Wrong server name !\n"; return; 
  }
  my %SERVER=getServer($REF);
  foreach my $KEY ( sort keys %SERVER) {
    my $VAL = $SERVER{$KEY};
    print "${DOTS} ${VAL}\r${KEY} \n";
  }
}

sub showAllServers($) {
  my $LINE=shift;
  foreach my $ITEM (sort keys %$HHOSTS) {
    my $PT=$HHOSTS->{$ITEM};
    my $DEVIP = $PT->{"DEVIP"};
    #my $HNAME = $PT->{"HNAME"};
    my $FQDN  = $PT->{"FQDN"};
    my $RLI   = $PT->{"RLI"};
    printf("%-15s %-15s %10s \%s\n",$ITEM,$DEVIP,$RLI,$FQDN);
  }
}

sub showServerDetail($) {
  my $LINE=shift;
  my $REF=$LINE;
  $REF =~ s/^\S+\s+\S+\s+//;
  $REF =~ s/\s+detail$//;
  unless(getRef($REF)) { 
    warn "Wrong server name !\n"; return; 
  }
  my %SERVER=getServer($REF);
  my $SEQ="";
  if(defined $SERVER{"PLATFORM"}) { 
    $SEQ = $SERVER{"PLATFORM"}; 
  } 
  if(defined  $SERVER{"PLAX"}) { 
    $SEQ = $SERVER{"PLAX"}; 
  }
  if($SERVER{"TYPE"})  { $SEQ .= "-".$SERVER{"TYPE"}; }
  else                 { $SEQ .= "-OS"; }
  if($SERVER{"BACKUP"}){ $SEQ .= "-".$SERVER{"BACKUP"}; }
  else                 { $SEQ .= "-DP"; }

  showServer($REF);
  showSequence($SEQ);
}
 
##za##################################################################### }}} 1
## showTask showAllTasks ############################################## {{{ 1

sub showAllTasks($) {
  my $LINE=shift;
  foreach my $ITEM (sort keys %$HTASKS) {
    my $DESC=$HTASKS->{$ITEM}->{"DESC"};
    my $CMD=$HTASKS->{$ITEM}->{"CMD"};
    printf("%-10s \%s\n",$ITEM,$DESC);
  }
}

sub showTask($) {
  my $LINE=shift;
  my $REF = $LINE;
  $REF =~ s/^\S+\s+\S+\s+//;
  unless(exists $HTASKS->{$REF}) {
    warn "Wrong task refference !\n";
    return;
  }
  my $PT=$HTASKS->{$REF};
  foreach my $KEY (sort keys %$PT) {
    my $VAL=$PT->{$KEY};
    print "${DOTS} ${VAL}\r${KEY} \n";
  } 
}
####################################################################### }}} 1
## showSequence showAllSequences ###################################### {{{ 1

sub showAllSequences($) {
  my $LINE=shift;
  print "List of all Task Sequences:\n";
  foreach my $ITEM (sort keys %$HOSSEQ) {
    print "    ${ITEM}\n";
  }
}

sub showSequence($) {
  my $LINE=shift;
  my $ITEM=$LINE;
  $ITEM =~ s/^\S+\s+\S+\s+//;
  unless(exists $HOSSEQ->{$ITEM}) {
    warn "Wrong Sequence refference !\n";
    return;
  }
  my $SEQ=$HOSSEQ->{$ITEM};
  print "Task Sequence '${ITEM}':\n";
  my $IDX=0;
  foreach my $XITEM (split(/;/,$SEQ)) {
    if($IDX == 0) { print "    "; }
    print " ${XITEM} ;";
    $IDX++;
    if($IDX > 7) { $IDX=0; print "\n"; }
  }
  print "\n";
}

####################################################################### }}} 1
## execTask execSequence execServer ################################### {{{ 1

sub execTask($) {
  my $LINE=shift;
  my($TYPE,$X,$TASK,$SERVER);
  ($TYPE,$X) = split(/\s+/,$LINE,2);
  ($X,$X,$X,$TASK,$X,$SERVER) = split(/\s+/,$LINE);
  debug "#: LINE ${LINE}\n";
  debug "#: TASK ${TASK}\n";
  debug "#: SERVER ${SERVER}\n";
  unless($TASK)   { warn "Wrong task !\n"; return; }
  unless($SERVER) { warn "Wrong server !\n"; return; }
  unless(exists $HTASKS->{$TASK}) { warn "Task does not exist !\n"; return; }
  my $PT = $HTASKS->{$TASK};
  my $CMD = $PT->{"CMD"};
  debug "#: CMD ${CMD}\n";
  my $RET = shexec($SERVER,$CMD);
  print "\033[1;35m${RET}\033[m\n";
}

sub execSequence($) {
  my $LINE=shift;
  my ($TYPE,$X,$SEQREF,$SERVER,$START,$STOP);
  my $RUNNING = 1;
  $START = $STOP = "";
  ($TYPE,$X) = split(/\s+/,$LINE,2);
  if($TYPE eq "none") {
    ($X,$X,$X,$SEQREF,$X,$SERVER) = split(/\s+/,$LINE);
  } elsif($TYPE eq "start") {
    ($X,$X,$X,$SEQREF,$X,$SERVER,$X,$START) = split(/\s+/,$LINE);
    $RUNNING = 0;
  } elsif($TYPE eq "stop") {
    ($X,$X,$X,$SEQREF,$X,$SERVER,$X,$STOP) = split(/\s+/,$LINE);
    $RUNNING = 1;
  } elsif($TYPE eq "startstop") {
    $RUNNING = 0;
    ($X,$X,$X,$SEQREF,$X,$SERVER,$X,$START,$X,$STOP) = split(/\s+/,$LINE);
  }

  unless(exists $HOSSEQ->{$SEQREF}) {
    warn "Wrong Sequence refference !\n";
    return;
  }

  debug "#: LINE ......... ${LINE}\n";
  debug "#: SERUENCE ..... ${SEQREF}\n";
  debug "#: SERVER ....... ${SERVER}\n";
  debug "#: START ........ ${START}\n";
  debug "#: STOP ......... ${STOP}\n";

  my $SEQDAT=$HOSSEQ->{$SEQREF};
  print "Task Sequence '${SEQREF}':\n";
  my $IDX=0;
  foreach my $XTASK (split(/;/,$SEQDAT)) {
    debug "#: SEQ ${SEQREF} TASK=${XTASK} on SERVER ${SERVER}\n";
    my($ATASK,$BTASK);
    if($XTASK =~ /-/) { ($ATASK,$BTASK)=split(/-/,$XTASK,2); }
    else { $ATASK=$XTASK; $BTASK=""; }

    if($START and ($ATASK eq $START)) { $RUNNING = 1; }
    if($RUNNING) {
      my $RET = shexecid($SERVER,$ATASK);
      print "\033[0;36m${XTASK} / ${ATASK} => ${RET}\033[m\n";
      if($BTASK and $RET) { 
        $RET = shexecid($SERVER,$BTASK); 
        print "\033[0;36m${XTASK} / ${BTASK} => ${RET}\033[m\n";
      }
      if($STOP and ($BTASK eq $STOP)) { $RUNNING = 0; }
    }
    if($STOP and ($ATASK eq $STOP)) { $RUNNING = 0; }
  }
  print "\n";
}



sub execServer($) {
  my $LINE=shift;
  my ($TYPE,$X,$SEQREF,$SRVREF,$START,$STOP);
  my $RUNNING = 1;
  my $EXPORT  = "";
  $START = $STOP = "";
  ($TYPE,$X) = split(/\s+/,$LINE,2);
  if($TYPE eq "none") {
    ($X,$X,$X,$SRVREF) = split(/\s+/,$LINE);
  } elsif($TYPE eq "start") {
    ($X,$X,$X,$SRVREF,$X,$START) = split(/\s+/,$LINE);
    $RUNNING = 0;
  } elsif($TYPE eq "stop") {
    ($X,$X,$X,$SRVREF,$X,$STOP) = split(/\s+/,$LINE);
    $RUNNING = 1;
  } elsif($TYPE eq "startstop") {
    $RUNNING = 0;
    ($X,$X,$X,$SRVREF,$X,$START,$X,$STOP) = split(/\s+/,$LINE);
  }
 
  my %SERVER = getServer($SRVREF);
  unless(exists $SERVER{"DEVIP"}) { 
    warn "No DEVIP defined for server ${SRVREF} !\n";
  }
  unless(exists $SERVER{"HNAME"}) { 
    warn "No HNAME defined for server ${SRVREF} !\n";
  }
  unless(exists $SERVER{"FQDN"}) { 
    warn "No FQDN defined for server ${SRVREF} !\n";
  }

  if(exists $SERVER{"PLATFORM"}) {
     $SEQREF=$SERVER{"PLATFORM"};
  }
  if(exists $SERVER{"PLAX"}) {
     $SEQREF=$SERVER{"PLAX"};
  }
  if($SERVER{"TYPE"})  { $SEQREF .= "-".$SERVER{"TYPE"}; }
  else                 { $SEQREF .= "-OS"; }
  if($SERVER{"BACKUP"}){ $SEQREF .= "-".$SERVER{"BACKUP"}; }
  else                 { $SEQREF .= "-DP"; }

  unless(exists $HOSSEQ->{$SEQREF}) {
    warn "Wrong Sequence refference !\n";
    return;
  }
 
  debug "#: LINE ......... ${LINE}\n";
  debug "#: SERVER ....... ${SRVREF}\n";
  debug "#: SERUENCE ..... ${SEQREF}\n";
  debug "#: START ........ ${START}\n";
  debug "#: STOP ......... ${STOP}\n";

  my $SEQDAT=$HOSSEQ->{$SEQREF};
  print "Task Sequence '${SEQREF}':\n";
  my $IDX=0;
  foreach my $XTASK (split(/;/,$SEQDAT)) {
    debug "#: SEQ ${SEQREF} TASK=${XTASK} on SERVER ${SRVREF}\n";
    my($ATASK,$BTASK);
    if($XTASK =~ /-/) { ($ATASK,$BTASK)=split(/-/,$XTASK,2); }
    else { $ATASK=$XTASK; $BTASK=""; }

    if($START and ($ATASK eq $START)) { $RUNNING = 1; }
    if($RUNNING) {
      my $RET = shexecid($SRVREF,$ATASK);
      print "\033[0;36m${XTASK} / ${ATASK} => ${RET}\033[m\n";
      if($BTASK and $RET) { 
        $RET = shexecid($SRVREF,$BTASK); 
        print "\033[0;36m${XTASK} / ${BTASK} => ${RET}\033[m\n";
      }
      if($STOP and ($BTASK eq $STOP)) { $RUNNING = 0; }
    }
    if($STOP and ($ATASK eq $STOP)) { $RUNNING = 0; }
  }
  print "\n";
}

####################################################################### }}} 1

# --- end ---
