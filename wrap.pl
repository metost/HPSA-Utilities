#!/usr/bin/perl
# HPSA-LOG.PL - Logging Utility
# 20160810, Ing. Ondrej DURAS (dury)
# C:\usr\prog\HPSA-Utilities\hpsa-log.pl
#


## MANUAL ############################################################# {{{ 1

our $VERSION = 2016.113001;
our $MANUAL  = <<__MANUAL__;
NAME: Wrapper for Server Automation
FILE: wrap.pl

DESCRIPTION:
  Utility does four things:
  - copies a content of STDIN onto STDOUT
  - makes output on STDOUT colored on internal rule basis
  - writes STDIN into logfile
  - makes a timestam on each line written into file
  Specific is the "-mig" mode, when the script will use
  the system Environment variable HNAME to build a log filename.

USAGE:
  some_command | wrap
  hpsa-diff.pl -name engreq309-0176 -hot 2>\&1 | wrap
  wrap -new -msg "Previous content has been deleted"
  
   C:\\> (
    echo tasklist
    echo netstat -a
    ) | wrap -execute

    $ wrap -wmi 1.2.3.4 -login Admin -password hello <<__END__
        tasklist
        netstat -a
    __END__

    $ wrap -ssh server123 -login root -password hello <<__END__
        ps -ef | grep httpd
        netstat -ie
        cat /etc/redhat-release
    __END__

    $ wrap -exec -prompt -plax Win2008r2x64 <<__END__
        some-script -x -y
    __END__

    $ wpar -wmi server123 -jump user\@jmpserver <<__END__
        some-commands -x -y
    __END__

PARAMETERS:
  -color   ......... pass escape sequences to STDOUT (*)
  -no-color ........ removes escape sequences before the print to STDOUT
  -msg <message> ... message to be displayed/written before copy of STDIN
  -rules ........... data will be colored on rule basis (*)
  -no-rules ........ data will NOT be colored on rule basis
  -suppress ........ Escape sequences comming from STDIN will be suppressed (*)
  -no-suppress ..... Escape sequences comming from STDIN will NOT be suppressed
  -timestamp ....... timestamp each line written to file by YYYYmmdd-HHMMss (*)
  -no-timestamp .... None timestamps at begin of each line written to file
  -term ............ STDIN will pass to STDOUT (*)
  -no-term ......... none messages from STDIN to STDOUT
  -write ........... STDIN will pass into FILE (*)
  -no-write ........ none STDIN written into FILE
  -output <file> ... output file except the default name
  -mig ............. parameters related to migration (*)
  -no-mig .......... none parameters related to migration
  -dir-fold ........ uses ENV{DATA_FOLD} for destination directory
  -dir-logs......... uses ENV{DATA_LOGS} for destination directory (*)
  -no-fold ......... does not use ENV{DATA_FOLD} or ENV{DATA_LOGS} 
  -dir <dir> ....... explicit destination directory for output log file
  -cat ............. shows whole Log file onto terminal
  -grep <RexEx> .... displays filtered content of existing Log file
  -hot ............. non-cached STDOUT
                    
  -execute ......... executes content of STDIN localy
  -ssh <server> .... executes content of STDIN on the server over SSH
  -wmi <server> .... executes content of STDIN on the server over WMI
  -login <login> ... login name
  -password <pwd> .. password for login
  -sshpass ......... use SSHPASS feature
  -user <user> ..... PWA user profile containging login and password
  -jump <u\@host> ... SSH jump server used to perform a command
  -jumppw <pass> ... Password for SSH jump server
                    
  -task <Task> ..... Task number
  -linux ........... checks PLAX variable and executes in Linux cases only
  -windows ......... checks PLAX variable and executes in Windos case only
  -plax ............ checks PLAX variable and executes if both parameters match
  -force ........... MODE simly performing action unconditionally
  -prompt .......... MODE prompting before each action
  -auto ............ MODE performing action when rg.STOP==0 only
  -passed .......... MODE performing action if previous action successed
  -failed .......... MODE permorming action if previous action failed
  -while <RegEx> ... MODE performing action while RegEx matched
  -until <RegEx> ... MODE performing action while RegEx not matched
                    
  -pass <RegEx> .... PASS=0; then PASS=1 if output matched the RegEx
  -nopass <RegEx> .. PASS=1; then PASS=0 if output matched the RegEx
  -fail <RegEx> .... FAIL=0; then FAIL=1 if output matched the RegEx
  -nofail <RegEx> .. FAIL=1; then FAIL=0 if output matched the RegEx
  -stop <RegEx> .... STOP=0; if output matched RegEx then STOP=1
  -nostop <RegEx> .. STOP=1; if output matched RegEx then STOP=0
  
  -unlink .......... removed registry file (at the end)
  -clear ........... sets registry to default values (at the begin)                  
  -get-regs ........ Get content of all registers in one line
  -get-pass ........ Get status of PASS register
  -get-fail ........ Get status of FAIL register
  -get-stop ........ Get status of STOP register
  -set-pass <No> ... Set PASS register to <No> (number 0|1)
  -set-fail <No> ... Set PASS register to <No> (number 0|1)
  -set-stop <No> ... Set PASS register to <No> (number 0|1)
  (*) .............. all are by default

VERSION: ${VERSION}

__MANUAL__

####################################################################### }}} 1
## INTERFACE ########################################################## {{{ 1

use warnings;
use strict;
use subs 'die';
use subs 'warn';
use subs 'exit';
use IPC::Open2;
use POSIX;
use Win32::Console::ANSI;
use PWA;

# Prototypes
sub exit(;$);
sub die(;$$);
sub xregload(;$);
sub xregsave();
sub xcolor($);
sub xstrip($);
sub xinput(;$);
sub xsystem($);
sub xprint($);
sub xwrite($$);
sub xFileName(;$);
sub xopen($;$);
sub xclose();
sub xlog($);
sub xdecide(;%);
sub xsetreg($);
sub xgetreg($);
sub xgetregs();

our $MODE_SHOW   = 0;  # 0=OFF(writing records if -t STDIN) 1=cat 2=grep
our $MODE_GREP   = ""; # RegEx to grep a Log file.
our $MODE_MESSAGE= ""; # message to be displayed/written first before STDIN
our $MODE_USER   = ""; # PWA user profile
our $MODE_LOGIN  = ""; # login, taken from -login or from -u PWA profile
our $MODE_PASSWORD=""; # password taken from PWA or from -password
our $MODE_SSHPASS= 0;  # "sshpass -e " command used except the "ssh"
our $MODE_SSH    = ""; # DEVIP/HNAME/FQDN of Linux/SSH server
our $MODE_WMI    = ""; # DEVIP/HNAME/FQDN of Windows/WMI/WinExe/PSexec server
our $MODE_EXE    = ""; # execute content of STDIN localy
our $MODE_SSHJUMP= ""; # USER@DEVIP of SSH jump server
our $MODE_SSHJPWD= ""; # password for SSH jump server
our $MODE_LNX    = 0;  # checks the platform is Linux
our $MODE_WIN    = 0;  # checks the platform is Windows
our $MODE_PLX    = 0;  # checks the platform equals the -plax parameter
our $MODE_COLOR  = 2;  # 0=OFF 1=ON 2=TBD
our $MODE_HOTOUT = 2;  # 0=OFF 1=ON 2=TBD caching STDOUT  -hot / -no-hot
our $MODE_RULES  = 1;  # 1=ON 0=OFF usage of coloring rules
our $MODE_STDIN  = 1;  # 1=ON 0=OFF ON=suppress all escape sequences taken from STDIN
our $MODE_TIMER  = 1;  # 1=timestamps 0=no-timestamps into file
our $MODE_WRITE  = 1;  # 1=ON 0=OFF writing STDIN into log file
our $MODE_QUIET  = 0;  # 1=OFF 0=ON - 1=suppress the most of data printed to STDOUT
our $MODE_HNAME  = 1;  # 1=uses the ENV{HNAME} for output filename
our $MODE_DFOLD  = 0;  # 0=OFF 1=use a $ENV{DATA_FOLD} path for destination directory
our $MODE_DLOGS  = 1;  # 0=OFF 1=use a $ENV{DATA_LOGS} path for destination directory
our $MODE_DDIR   = 0;  # 0=OFF 1=explicit destination directory is going to be used for logs
our $MODE_NEW    = 0;  # 1=delete the file before the 1st write
our $MODE_GETSET = 0;  # --get-pass/--get-fail/--get-stop/--set-pass/--set-fail/--set-stop exit after registers set
our $MODE_UNLINK = 0;  # --unlink / --clear ... deletes the registry file at the 'exit'
our $PATH_DIR    = ""; # particular explicit destination directory
our $FILE_OUTPUT = ""; # file name of output file
our $FILE_FNAME  = ""; # file name of output file - full - after the xopen 
our $FH_OUTPUT   = undef; # file handler of output file

our $PRE_PASS    = 0; # status taken from file, ...givin info of PREvious task
our $PRE_FAIL    = 0;
our $PRE_STOP    = 0;
our $PRE_IDSTART = 0;
our $PRE_IDSTOP  = 0;
our $PRE_IDTASK  = "";

our $REG_PASS    = 0;    # counter of successes
our $REG_FAIL    = 0;    # counter of failures
our $REG_FIRST   = 0;    # first task
our $REG_LAST    = 0;    # last task
our $REG_TASK    = 0;    # actual task number
our $REG_IDSTART = 0;    # task ID, non-zero means the PreTask has not started yet
our $REG_IDSTOP  = 0;    # task ID, non-zero means the PreTask has not stopped yet
our $REG_IDTASK  = "";   # the list of comma separated TaskIDs
our $REG_STOP    = 0;    # =1 => stop
our $REG_AUTO    = 0;    # =1 automatically =0 ask to proceed
our $REG_REDO    = 0;    # =1 need to RE-DO ... do again whole command.
our $REG_ONCE    = 0;    # =1 means the user had been asked already ("once"=1, 0="retry")
                 
our $WRAP_CODE   = ""; # a PERL CODE taken from ENV{WRAP_CODE}
our $RP_PASS     = ""; # RegEx - if the LINE matches it, then $PASS=1 (PASS=0 at the begin)
our $RN_PASS     = ""; # RegEx - if the LINE matches it, then $PASS=0 (PASS=1 at the begin)
our $RP_FAIL     = ""; # RegEx - if the LINE matched it, then $FAIL=1 (FAIL=0 at the begin)
our $RN_FAIL     = ""; # RegEx - if the LINE matches it, then $FAIL=0 (FAIL=1 at the begin)
our $RP_STOP     = ""; # RegEx - if the LINE matches it, then $STOP=1 (STOP=0 at the begin)
our $RN_STOP     = ""; # RegEx - if the LINE matches it, then $STOP=0 (STOP=1 at the begin)
our $RP_REDO     = ""; # RegEx - if the LINE matches it, then command will be executed one more time --while
our $RN_REDO     = ""; # RegEx - if the LINE matches it, then command will not be exetuted more time --until

our $MODE_FORCE  = 0;  # unconditional execution of commands
our $MODE_PROMPT = 0;  # must ask before command performed (proceed/skip/quit/retry)
our $MODE_AUTO   = 0;  # can proceed a task when STOP=0
our $MODE_PASSED = 0;  # perform the task when STOP==0 & PASS==1
our $MODE_FAILED = 0;  # perform the task when STOP==0 & FAIL==1
our $MODE_REDO   = 0;  # $RP_REDO & $REDO

# Manual Page must be show if none argument on the commandline
if((-t STDIN) and (not scalar @ARGV)) {
  print $MANUAL;
  exit;
}

# Feeding Task-Control Regular Expressions from the Sysytem ENVironment
if(exists $ENV{WRAP_CODE})    { $WRAP_CODE = $ENV{WRAP_CODE}; }
if(exists $ENV{WRAP_RN_PASS}) { $RN_PASS   = $ENV{WRAP_RN_PASS}; $REG_PASS = 1; }
if(exists $ENV{WRAP_RP_PASS}) { $RP_PASS   = $ENV{WRAP_RP_PASS}; $REG_PASS = 0; }
if(exists $ENV{WRAP_RN_FAIL}) { $RN_FAIL   = $ENV{WRAP_RN_FAIL}; $REG_FAIL = 1; }
if(exists $ENV{WRAP_RP_FAIL}) { $RP_FAIL   = $ENV{WRAP_RP_FAIL}; $REG_FAIL = 0; }
if(exists $ENV{WRAP_RN_STOP}) { $RN_STOP   = $ENV{WRAP_RN_STOP}; }
if(exists $ENV{WRAP_RP_STOP}) { $RP_STOP   = $ENV{WRAP_RP_STOP}; }
xregload();  # loading the content of registers (PASS/FAIL/STOP)

while(my $ARGX = shift @ARGV) {
  if($ARGX =~ /^-+hot/)       { $MODE_HOTOUT  = 1; next; }  # --hot
  if($ARGX =~ /^-+no-?hot/)   { $MODE_HOTOUT  = 0; next; }  # --no-hot
  if($ARGX =~ /^-+co/)        { $MODE_COLOR   = 1; next; }  # --color
  if($ARGX =~ /^-+no-?co/)    { $MODE_COLOR   = 0; next; }  # --no-color
  if($ARGX =~ /^-+ru/)        { $MODE_RULES   = 1; next; }  # --rules
  if($ARGX =~ /^-+no-?ru/)    { $MODE_RULES   = 0; next; }  # --no-rules
  if($ARGX =~ /^-+su/)        { $MODE_STDIN   = 1; next; }  # --suppress / --strip
  if($ARGX =~ /^-+no-su/)     { $MODE_STDIN   = 0; next; }  # --no-suppress / --no-strip
  if($ARGX =~ /^-+str/)       { $MODE_STDIN   = 1; next; }  # --suppress / --strip
  if($ARGX =~ /^-+no-str/)    { $MODE_STDIN   = 0; next; }  # --no-suppress / --no-strip
  if($ARGX =~ /^-+time/)      { $MODE_TIMER   = 1; next; }  # --timestamp
  if($ARGX =~ /^-+no-?ti/)    { $MODE_TIMER   = 0; next; }  # --no-timestamp
  if($ARGX =~ /^-+term/)      { $MODE_QUIET   = 0; next; }  # --term
  if($ARGX =~ /^-+no-?te/)    { $MODE_QUIET   = 1; next; }  # --no-term / --quiet
  if($ARGX =~ /^-+q/)         { $MODE_QUIET   = 1; next; }  # --no-term / --quiet
  if($ARGX =~ /^-+wr/)        { $MODE_WRITE   = 1; next; }  # --write
  if($ARGX =~ /^-+no-?wr/)    { $MODE_WRITE   = 0; next; }  # --no-write
  if($ARGX =~ /^-+new/)       { $MODE_NEW     = 1; next; }  # --new
  if($ARGX =~ /^-+o/)         { $FILE_OUTPUT  =    shift @ARGV; next; } # --file FILE-LOG.txt
  if($ARGX =~ /^-+cat/)       { $MODE_SHOW    = 1; next; }  # --cat
  if($ARGX =~ /^-+grep/)      { $MODE_SHOW    = 1;          # --grep <RexEx>
                                $MODE_GREP    =    shift @ARGV; next; }
  if($ARGX =~ /^-+mig/)       { $MODE_HNAME   = 1; next; }  # --migration  / --mig
  if($ARGX =~ /^-+no-?mig/)   { $MODE_HNAME   = 0; next; }  # --no-migration / --no-mig
  if($ARGX =~ /^-+m/)         { $MODE_MESSAGE =    shift @ARGV; next; } # --message "something"
  if($ARGX =~ /^-+dir-?fold/) { $MODE_DFOLD   = 1; $MODE_DLOGS = 0; $MODE_DDIR = 0; next; }
  if($ARGX =~ /^-+dir-?logs/) { $MODE_DFOLD   = 0; $MODE_DLOGS = 1; $MODE_DDIR = 0; next; }
  if($ARGX =~ /^-+dir/)       { $MODE_DFOLD   = 0; $MODE_DLOGS = 1; $MODE_DDIR = 0; # --dir <dir>
                                $PATH_DIR     = shift @ARGV;       next; }
  if($ARGX =~ /^-+u(ser)?$/)  { $MODE_USER    = shift @ARGV; next; } # --user - PWA user profile to be used
  if($ARGX =~ /^-+login/)     { $MODE_LOGIN   = shift @ARGV; next; } # --login on command-line
  if($ARGX =~ /^-+passw/)     { $MODE_PASSWORD= shift @ARGV; next; } # --password on command-line
  if($ARGX =~ /^-+sshpass/)   { $MODE_SSHPASS = 1;           next; } # --sshpass      (uses ENV{SSHPASS}
  if($ARGX =~ /^-+ssh$/)      { $MODE_SSH     = shift @ARGV; next; } # going to connect server over SSH
  if($ARGX =~ /^-+wmi$/)      { $MODE_WMI     = shift @ARGV; next; } # going to connect server over WMI
  if($ARGX =~ /^-+exe/)       { $MODE_EXE     = "#";         next; } # going to execute commands locally
  if($ARGX =~ /^-+jump$/)     { $MODE_SSHJUMP = shift @ARGV; next; } # --jump user@server
  if($ARGX =~ /^-+sshjump$/)  { $MODE_SSHJUMP = shift @ARGV; next; } # --sshjump user@server
  if($ARGX =~ /^-+jumppw$/)   { $MODE_SSHJPWD = shift @ARGV; next; } # --jumppw password
  if($ARGX =~ /^-+sshjumppw$/){ $MODE_SSHJPWD = shift @ARGV; next; } # --sshjumppw password
  if($ARGX =~ /^-+(lnx|lin)/) { $MODE_LNX     = 1; next; }           # ENV{PLAX} based test whether server is linux
  if($ARGX =~ /^-+win/)       { $MODE_WIN     = 1; next; }           # ENV{PLAX} based test whether server is windows
  if($ARGX =~ /^-+plax/)      { $MODE_PLX     = shift @ARGV; next; } # if ENV{PLAX} == -plax paramater

  if($ARGX =~ /^-+task$/)     { $REG_TASK     = shift @ARGV; next; } # --task <ID> - task identificator

  if($ARGX =~ /^-+no-?pass$/) { $RN_PASS      = shift @ARGV; next; $REG_PASS = 1; } # --no-pass <RegEx>
  if($ARGX =~ /^-+pass$/)     { $RP_PASS      = shift @ARGV; next; $REG_PASS = 0; } # --pass <RegEx>
  if($ARGX =~ /^-+no-?fail$/) { $RN_FAIL      = shift @ARGV; next; $REG_FAIL = 1; } # --no-fail <RegEx>
  if($ARGX =~ /^-+fail$/)     { $RP_FAIL      = shift @ARGV; next; $REG_FAIL = 0; } # --fail <RegEx>
  if($ARGX =~ /^-+no-?stop$/) { $RN_STOP      = shift @ARGV; next; } # --no-stop <RegEx>
  if($ARGX =~ /^-+stop$/)     { $RP_STOP      = shift @ARGV; next; } # --stop <RegEx>

  if($ARGX =~ /^-+force/)     { $MODE_FORCE   = 1;           next; } # --force - unconditional execution
  if($ARGX =~ /^-+prompt/)    { $MODE_PROMPT  = 1;           next; } # --prompt at each step
  if($ARGX =~ /^-+auto/)      { $MODE_AUTO    = 1;           next; } # REG_STOP /REG_TASK/FIRST/LAST can stop exec. 
  if($ARGX =~ /^-+passed/)    { $MODE_PASSED  = 1;           next; } # +REG_PASS to execute
  if($ARGX =~ /^-+failed/)    { $MODE_FAILED  = 1;           next; } # +REG_FAIL to execute

  if($ARGX =~ /^-+while/)     { $RP_REDO = shift @ARGV; $MODE_REDO = 1; $REG_REDO = 0; next; }
  if($ARGX =~ /^-+until/)     { $RN_REDO = shift @ARGV; $MODE_REDO = 1; $REG_REDO = 1; next; }


  if($ARGX =~ /^-+get-?regs-file/){ xgetregs(); $MODE_GETSET = 2; next; }
  if($ARGX =~ /^-+get-?regs$/)    { xgetregs(); $MODE_GETSET = 1; next; }
  if($ARGX =~ /^-+get-?pass$/)    { xgetreg($REG_PASS);    next; }
  if($ARGX =~ /^-+get-?fail$/)    { xgetreg($REG_FAIL);    next; } 
  if($ARGX =~ /^-+get-?first$/)   { xgetreg($REG_FIRST);   next; }
  if($ARGX =~ /^-+get-?last$/)    { xgetreg($REG_LAST);    next; } 
  if($ARGX =~ /^-+get-?task$/)    { xgetreg($REG_TASK);    next; } 
  if($ARGX =~ /^-+get-?idstart$/) { xgetreg($REG_IDSTART); next; } 
  if($ARGX =~ /^-+get-?startid$/) { xgetreg($REG_IDSTART); next; } 
  if($ARGX =~ /^-+get-?idstop$/)  { xgetreg($REG_IDSTOP);  next; } 
  if($ARGX =~ /^-+get-?stopid$/)  { xgetreg($REG_IDSTOP);  next; } 
  if($ARGX =~ /^-+get-?taskid$/)  { xgetreg($REG_IDTASK);  next; } 
  if($ARGX =~ /^-+get-?idtask$/)  { xgetreg($REG_IDTASK);  next; } 
  if($ARGX =~ /^-+get-?stop$/)    { xgetreg($REG_STOP);    next; } 
  if($ARGX =~ /^-+get-?auto$/)    { xgetreg($REG_AUTO);    next; } 
  if($ARGX =~ /^-+get-?redo$/)    { xgetreg($REG_REDO);    next; } 
  if($ARGX =~ /^-+get-?once$/)    { xgetreg($REG_ONCE);    next; } 


  if($ARGX =~ /^-+set-?pass$/)    { $REG_PASS    = xsetreg(shift @ARGV); next; }  # previous task has PASSed 
  if($ARGX =~ /^-+set-?fail$/)    { $REG_FAIL    = xsetreg(shift @ARGV); next; }  # prefious task has FAILed
  if($ARGX =~ /^-+set-?first$/)   { $REG_FIRST   = xsetreg(shift @ARGV); next; }  # minimal task ID
  if($ARGX =~ /^-+set-?last$/)    { $REG_LAST    = xsetreg(shift @ARGV); next; }  # maximal task ID
  if($ARGX =~ /^-+set-?task$/)    { $REG_TASK    = xsetreg(shift @ARGV); next; }  # list of tasks to be performed
  if($ARGX =~ /^-+set-?idstart$/) { $REG_IDSTART = xsetreg(shift @ARGV); next; }  # task ID of the first applicable task
  if($ARGX =~ /^-+set-?startid$/) { $REG_IDSTART = xsetreg(shift @ARGV); next; }  # task ID of the first applicable task
  if($ARGX =~ /^-+set-?idstop$/)  { $REG_IDSTOP  = xsetreg(shift @ARGV); next; }  # task ID of the first applicable task
  if($ARGX =~ /^-+set-?stopid$/)  { $REG_IDSTOP  = xsetreg(shift @ARGV); next; }  # task ID of the first applicable task
  if($ARGX =~ /^-+set-?taskid$/)  { $REG_IDTASK  = xsetreg(shift @ARGV); next; }  # task ID of the first applicable task
  if($ARGX =~ /^-+set-?idtask$/)  { $REG_IDTASK  = xsetreg(shift @ARGV); next; }  # task ID of the first applicable task
  if($ARGX =~ /^-+set-?stop$/)    { $REG_STOP    = xsetreg(shift @ARGV); next; }  # task ID of the last applicable task
  if($ARGX =~ /^-+set-?auto$/)    { $REG_AUTO    = xsetreg(shift @ARGV); next; } 
  if($ARGX =~ /^-+set-?redo$/)    { $REG_REDO    = xsetreg(shift @ARGV); next; } 
  if($ARGX =~ /^-+set-?once$/)    { $REG_ONCE    = xsetreg(shift @ARGV); next; } 
  if($ARGX =~ /^-+clear$/)        { $MODE_UNLINK = 1;      next; }  # --clear / --unlink
  if($ARGX =~ /^-+unlink$/)       { $MODE_UNLINK = 1;      next; }  # --clear / --unlink




  die "#- Error: Wrong argument '${ARGX}' !\n";
}

if($MODE_HOTOUT == 2) {                        # STDOUT buffer
  unless( -t STDOUT) { $MODE_HOTOUT = 1; }     #
  else               { $MODE_HOTOUT = 0; }     #
}                                              #
if($MODE_HOTOUT) {                             #
  # http://perl.plover.com/FAQs/Buffering.html #
  select((select(STDOUT), $|=1)[0]);           #
}                                              #

# color mode / if not decided by explicit (cmdline) way
if($MODE_COLOR == 2) {
  if( -t STDOUT ) { $MODE_COLOR = 1; }
  else            { $MODE_COLOR = 0; }
}

if($MODE_SSHJUMP eq "no") {
  $MODE_SSHJUMP = "";
}

# solving credentials, if they are necessary
if($MODE_SSH or $MODE_WMI) {
  if((not $MODE_LOGIN)    and $MODE_USER) { $MODE_LOGIN    = pwaLogin($MODE_USER); }
  if((not $MODE_PASSWORD) and $MODE_USER) { $MODE_PASSWORD = pwaPassword($MODE_USER); }
}

if($MODE_GETSET) { 
  if($MODE_GETSET == 2) {
    my $FNAME = xFileName('dat');
    xprint xcolor "#: Registry stored in '${FNAME}'\n";
  }
  exit; 
}

####################################################################### }}} 1
## exit && die && register handling ################################### {{{ 1


sub exit(;$) {
  my $EXIT = shift;
  xregsave;
  unless($EXIT) { $EXIT = 0; }
  #print "#: DEBUG exit\n";
  CORE::exit($EXIT);
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

sub xsetreg($) {
  my $VAL = shift;
  $VAL = 0 unless($VAL =~ /^[,0-9a-zA-Z]+$/);
  $MODE_GETSET = 1;
  return $VAL;
}

sub xgetreg($) {
  my $VAL = shift;
  print $VAL;
  if( -t STDOUT) { print "\n"; }
  $MODE_GETSET = 1;
}

sub xgetregs() {
  unless(defined $REG_PASS)    { $REG_PASS    = "_"; }
  unless(defined $REG_FAIL)    { $REG_FAIL    = "_"; }
  unless(defined $REG_FIRST)   { $REG_FIRST   = "_"; }
  unless(defined $REG_LAST)    { $REG_LAST    = "_"; }
  unless(defined $REG_TASK)    { $REG_TASK    = "_"; }
  unless(defined $REG_IDSTART) { $REG_IDSTART = "_"; }
  unless(defined $REG_IDSTOP)  { $REG_IDSTOP  = "_"; }
  unless(defined $REG_IDTASK)  { $REG_IDTASK  = "_"; }
  unless(defined $REG_STOP)    { $REG_STOP    = "_"; }
  unless(defined $REG_AUTO)    { $REG_AUTO    = "_"; }
  unless(defined $REG_REDO)    { $REG_REDO    = "_"; }
  unless(defined $REG_ONCE)    { $REG_ONCE    = "_"; }
  print xcolor "#:"
    . " PASS=${REG_PASS}"
    . " FAIL=${REG_FAIL}" 
    . " FIRST=${REG_FIRST}"
    . " LAST=${REG_LAST}"
    . " TASK=${REG_TASK}"
    . " STOP=${REG_STOP}"
    . " AUTO=${REG_AUTO}"
    . " REDO=${REG_REDO}"
    . " ONCE=${REG_ONCE}"
    . "\n#:"
    . " IDSTART=${REG_IDSTART}"
    . " IDSTOP=${REG_IDSTOP}"
    . " IDTASK='${REG_IDTASK}'"
    . "\n";
}

sub xgetexp() {
 print xcolor <<__EXP__;
#: RP_PASS='${RP_PASS}'
#: RN_PASS='${RN_PASS}'
#: RP_FAIL='${RP_FAIL}'
#: RN_FAIL='${RN_FAIL}'
#: RP_STOP='${RP_STOP}'
#: RN_STOP='${RN_STOP}'
__EXP__
}
   
sub xprintcode(%) {
  my %OPT = @_;
  my $NOTE=""; 
  my $CODE="";
  my $TASK="";
  unless(defined $OPT{cmd})  { return; }
  unless(defined $OPT{note}) { $NOTE=""; }
  else                       { $NOTE=$OPT{note}; }
  if($REG_TASK ne "0")       { $TASK=$REG_TASK; }

  $CODE = $OPT{cmd};
  $CODE =~ s/^.*$/\033[1;32m$&\033[m/gm;
  xprint xcolor "#: ------------------\n";
  if($TASK) { 
  xprint xcolor "#: TASK = ${TASK}\n"; 
  }
  xprint xcolor "#: ${NOTE}\n";
  xprint $CODE."\n";
}

####################################################################### }}} 1
## Terminal Handling :xcolor xstrip xprint xinput ##################### {{{ 1

#FUNCTION: 
#  $TTY_MESSAGE = xcolor $PLAIN_MESSAGE;
#  priunt xcolor $PLAIN_MESSAGE;
#PARAMETER:
#  $PLAIN_MESSAGE - a plain text without the Escape sequences
#  $TTY_MESSAGE   - colored/highlighted message with the escape sequences
#DESCRIPTION:
#  based on highlighting rule it gives the colors to message
sub xcolor($) {
  my $MSG = shift;
  unless($MODE_COLOR) { return $MSG; }
  $MSG =~ s/^#:.*$/\033\[0;36m$&\033\[m/mg;
  $MSG =~ s/^#-.*$/\033\[1;31m$&\033\[m/mg;
  $MSG =~ s/^#\+.*$/\033\[1;32m$&\033\[m/mg;
  $MSG =~ s/^#!.*$/\033\[1;37;41m$&\033\[m/mg;
  $MSG =~ s/^#\?.*$/\033\[1;36m$&\033\[m/mg;
  $MSG =~ s/^#\&.*$/\033\[1;33m$&\033\[m/mg;

  $MSG =~ s/^.* #: .*$/\033\[0;36m$&\033\[m/mg;
  $MSG =~ s/^.* #- .*$/\033\[1;31m$&\033\[m/mg;
  $MSG =~ s/^.* #\+ .*$/\033\[1;32m$&\033\[m/mg;
  $MSG =~ s/^.* #! .*$/\033\[1;31m$&\033\[m/mg;

  #$MSG =~ s/^.*\bdone\b.*$/\033\[0;36m$&\033\[m/img;
  #$MSG =~ s/^.*\blog.*$/\033\[0;36m$&\033\[m/img;
  #$MSG =~ s/^.*\bsuccess.*$/\033\[1;32m$&\033\[m/img;
  #$MSG =~ s/^.*\berr.*$/\033\[1;31m$&\033\[m/img;
  #$MSG =~ s/^.*\bwarn.*$/\033\[1;31m$&\033\[m/img;
  return $MSG;
}

#FUNCTION:
#  $LINE = xstrip <STDIN>;
#DESCRIPTION:
#  cuts all escape sequences
sub xstrip($) {
  my $MSG = shift;
  unless($MODE_STDIN) { return $MSG; }
  $MSG =~ s/\033\[[;0-9]+[A-Za-z]//mg;
  return $MSG;
}

#FUNCTION:
#  xprint xcolor $MSG;
#DESCRIPTION:
#  Prints the $MSG text message onto STDOUT terminal
#  In case of "quiet" it skips the printing
#  There are none colors added / xcolor is for that
#  But in case of MODE_COLOR=0 it
#  strips all colors/escape sequences
sub xprint($) {  # to STDOUT
  my $MSG = shift;
  return if $MODE_QUIET;
  unless($MODE_COLOR) { $MSG = xstrip($MSG); }
  print $MSG;
}

#FUNCTION:
#  $USER_INPUT = xinput('Prompt: ");
#DESCRIPTION:
#  Performs direct user interaction even 
#  STDIN and STDOUT are redirected into pipes or files
#  Returned value is a string given by user over terminal.
#  Function has one agrument - PROMPT, displayed
#  onto terminal anouncing the request of user interaction.
#  Prompt is not mandatory. By default it's "?>"

sub xinput(;$) {
  my $PROMPT = shift;
  unless($PROMPT) { $PROMPT = "?> "; }
  my ($FI,$FO);

  if($^O eq "MSWin32") {
    open $FI,"<" ,"CON"   or die "#- STDIN issue !\n";
    open $FO,">&STDERR"   or die "#- STDOUT issue !\n";
  } else {
    open $FI,"<" ,"/dev/tty"  or die "#- STDIN issue !\n";
    open $FO,">>","/dev/tty"  or die "#- STDOUT issue !\n";
  }

  #print $FO $PROMPT;
  print $FO xcolor $PROMPT;
  flush $FI;
  my $LINE=<$FI>;
  chomp $LINE;
  close $FO;
  close $FI;
  return $LINE;
}

sub xsystem($) {
  my $COMMAND = shift;
  printty "#- Not implemented yet.\n";
}

####################################################################### }}} 1
## File Handling: xwrite xFileName xopen xclose ####################### {{{ 1

sub xwrite($$) { # to FILE
  my ($FH,$MSG) = @_;
  return unless($MODE_WRITE);
  return unless $FH;
  $MSG =~ s/\033\[[;0-9]+[A-Za-z]//mg;
  my $STAMP = ""; if($MODE_TIMER) { $STAMP=strftime("%Y%m%d-%H%M%S ",gmtime(time)); }
  my $HNAME = ""; if($MODE_HNAME and exists($ENV{HNAME})) { $HNAME=$ENV{HNAME}.' '; }
  $MSG =~ s/^/${STAMP}${HNAME}/mg;
  print $FH $MSG;
}

sub xFileName(;$) {
  my $FTYPE = shift;
  unless($FTYPE) { $FTYPE="log"; }
  my $FNAME = "";
  if($FILE_OUTPUT) { 
    $FNAME = $FILE_OUTPUT; 
  } else {
    my $TTY   = "";
       if(exists $ENV{SSH_TTY}) { $TTY = $ENV{SSH_TTY}; }
       else                     { $TTY   = lc qx/tty/;  }
       $TTY   =~ s/[^0-9a-z]//g;
       $TTY   =~ s/^dev//;
       $TTY   = "-".$TTY;
    my $HNAME = "";
    if($MODE_HNAME and (exists $ENV{HNAME})) {
       $HNAME = "-".$ENV{HNAME};
       $HNAME =~ s/[^-A-Za-z0-9_]//g;
       if($HNAME =~ /\S/) { $TTY = ""; }
    }
    $FNAME=strftime("%Y%m%d",gmtime(time)).$TTY.$HNAME.".".$FTYPE;
  }
  unless($FNAME =~ /\\|\//) {
    my $HOME;
    if(exists $ENV{HOME}) { $HOME=$ENV{HOME}; }
    elsif(exists $ENV{USERPROFILE}) { $HOME=$ENV{USERPROFILE}; }

    if($MODE_DDIR) {
    } elsif($MODE_DLOGS) {
      if(exists $ENV{DATA_LOGS}) { $PATH_DIR=$ENV{DATA_LOGS}; }
    } elsif($MODE_DFOLD) {
      if(exists $ENV{DATA_FOLD}) { $PATH_DIR=$ENV{DATA_FOLD}; }
    } elsif(not $PATH_DIR) {
      $PATH_DIR = $HOME;
    }
    $PATH_DIR =~ s/(\\|\/)$//;
    if($^O =~ /MSWin32/) { $PATH_DIR .= "\\"; }
    else                 { $PATH_DIR .= "/";  }

    if($MODE_DLOGS or $MODE_DFOLD or $MODE_DDIR) {
      $FNAME = $PATH_DIR . $FNAME;
    }
  }
  return $FNAME;
}

#  xopen(">>"); xopen(">>","xyz.log"); # for appending
#  xopen("<"); ...for reading
sub xopen($;$) {
  my ($MODE,$FNAME) = @_;
  unless($FNAME) { $FNAME = xFileName(); }
  $FILE_FNAME = $FNAME;
  open $FH_OUTPUT,$MODE,$FNAME  or 
    die "#- Error: File '${FNAME}' unreachable !\n";
  # xprint xcolor "#: Log file '${FNAME}' opened.\n";
  xregload();
  return $FH_OUTPUT;
}

sub xclose() {
  return unless $FH_OUTPUT;
  close $FH_OUTPUT;
  # xprint xcolor "#: Log file '${FILE_FNAME}' closed.\n";
  $FH_OUTPUT = undef;
  xregsave();
}


####################################################################### }}} 1
## Handling: xregsave xregload - content of registers ################# {{{ 1

# saves registers into file
sub xregsave() {
  my $FNAME = xFileName('dat');
  my $FH;
  if($MODE_UNLINK) {
    unlink $FNAME;
    return 0;
  }
  open $FH,">",$FNAME or return 0;
  print $FH "STOP ${REG_STOP} PASS ${REG_PASS} FAIL ${REG_FAIL}\n";
  print $FH "STARTID ${REG_IDSTART} STOPID ${REG_IDSTOP} TASKID ${REG_IDTASK}\n";
  close $FH;
  return 1;
}


sub xregload(;$) {
  my $ASK = shift;
  my $FNAME = xFileName('dat');
  my $FH;
  my $XY;
  open $FH,"<",$FNAME or return 0;
  my $LINE1 = <$FH>;
  my $LINE2 = <$FH>;
  close $FH;
  chomp $LINE1;
  chomp $LINE2;
  $LINE1 =~ s/^\s+//; $LINE1 =~ s/\s+$//;
  $LINE2 =~ s/^\s+//; $LINE2 =~ s/\s+$//;
  ($XY,$REG_STOP,$XY,$REG_PASS,$XY,$REG_FAIL) = split /\s+/,$LINE1;
  ($XY,$REG_IDSTART,$XY,$REG_IDSTOP,$XY,$REG_IDTASK) = split /\s+/,$LINE2;
  unless(defined $REG_STOP)    { $REG_STOP    = 0; } $PRE_STOP    = $REG_STOP; 
  unless(defined $REG_PASS)    { $REG_PASS    = 0; } $PRE_PASS    = $REG_PASS;
  unless(defined $REG_FAIL)    { $REG_FAIL    = 0; } $PRE_FAIL    = $REG_FAIL;
  unless(defined $REG_IDSTART) { $REG_IDSTART = 0; } $PRE_IDSTART = $REG_IDSTART;
  unless(defined $REG_IDSTOP)  { $REG_IDSTOP  = 0; } $PRE_IDSTOP  = $REG_IDSTOP;
  unless(defined $REG_IDTASK)  { $REG_IDTASK  = "";} $PRE_IDTASK  = $REG_IDTASK;
  return 1;
}



####################################################################### }}} 1
## xlog && xdecide - Action Control Features ########################## {{{ 1

#FUNCTION:
#  $INCLUDED=xInTaskList($TASKLIST,$TASKITEM)
#PARAMETERS:
#  $INCLUDED - returned value 0=no 1=yes
#  TASKLIST  - string contains a comma separated list of TaskIDs
#  TASKITEM  - tarticular TaskID we are searching for
#DESCRIPTION:
#  Searches a TASKLIST for TASKID. If a TASKITEM is
#  found in a TASKLIST, then returns "true"/1 else "false"/0.
sub xInTaskList($$) {
  my ($TASK,$LIST) = @_;
  my  $FLAG = 0;
  foreach my $ITEM (split(/,/,$LIST)) {
    if($TASK eq $ITEM) { $FLAG=1; last; }
  }
  return $FLAG;
}


#FUNCTION:
#  xlog($LINE);
#DESCRIPTION:
#  Parses each $LINE of output
#  Based on results, it sets REG_* registers
sub xlog($) {
  my $LINE = shift;
     $LINE =~ s/\033\[[;0-9]+[A-Za-z]//mg;
  #if(exists $ENV{WRAP_CODE}) {
  #  eval $ENV{WRAP_CODE};
  #}
  if(($RP_PASS =~ /\S/) and ($LINE =~ /${RP_PASS}/)) { $REG_PASS+= 1; xprint xcolor "#& RP_PASS\n"; }
  if(($RN_PASS =~ /\S/) and ($LINE =~ /${RN_PASS}/)) { $REG_PASS = 0; xprint xcolor "#& RN_PASS\n"; }
  if(($RP_FAIL =~ /\S/) and ($LINE =~ /${RP_FAIL}/)) { $REG_FAIL+= 1; }
  if(($RN_FAIL =~ /\S/) and ($LINE =~ /${RN_FAIL}/)) { $REG_FAIL = 0; }
  if(($RP_STOP =~ /\S/) and ($LINE =~ /${RP_STOP}/)) { $REG_STOP+= 1; }
  if(($RN_STOP =~ /\S/) and ($LINE =~ /${RN_STOP}/)) { $REG_STOP = 0; }
  if(($RP_REDO =~ /\S/) and ($LINE =~ /${RP_REDO}/)) { $REG_REDO+= 1; }
  if(($RN_REDO =~ /\S/) and ($LINE =~ /${RN_REDO}/)) { $REG_REDO = 0; }
}

#FUNCTION:
#  xdecide();
#RETURNS:
#  0 - if wrapped task/command should NOT be executed
#  1 - if wrapped task/command should be executed
#DESCRIPTION:
#  responsible for decission whether to execute or
#  to not execute the command/wrapped task.
#  
sub xdecide(;%) {
  my %OPT = @_;


  # Platform based decission
  if($MODE_WIN or $MODE_LNX or $MODE_PLX) {
     my $PLAX = "";
     my $FLAG = 0;
     if(exists $ENV{PLAX}) { $PLAX = $ENV{PLAX}; }
     else { die "#- Error: Environment variable 'PLAX' is not defined !\n"; }
     if   ($MODE_LNX and ($PLAX=~/^Lnx/i))        { $FLAG = 1; }
     elsif($MODE_WIN and ($PLAX=~/^Win/i))        { $FLAG = 1; }
     elsif($MODE_PLX and ($PLAX=~/${MODE_PLX}/i)) { $FLAG = 1; }
     unless($FLAG) { return 0; }
  }
  # unconditional execution
  if($MODE_FORCE)  { 
    # SHOWING COMMANDS
    if($REG_ONCE) { return 0; }
    xprintcode(%OPT); 
    $REG_ONCE=1; return 1; 
  }

  # AUTOMATED and/or PROMPTed EXECUTIONS
  # if a STOP is set already, then we should not do anything
  # if STOP ... sthen simply STOP !!!
  if($REG_STOP > 0) { return 0; }
  if($PRE_STOP > 0) { return 0; }

  
  # TaskID based questions/decisions
  # is task in list of expected tasks
  if($REG_TASK and $REG_IDTASK) {
  #  if($REG_ONCE) { return 0; }
  #  $REG_ONCE=1;
    unless(xInTaskList($REG_TASK,$REG_IDTASK)) { return 0; }
  }
  # this point ensures the start of execution at some TaskID
  if($REG_TASK and $REG_IDSTART) {
  #  if($REG_ONCE) { return 0; }
  #  $REG_ONCE=1;
    if($REG_TASK eq $REG_IDSTART) {
      $REG_IDSTART = 0;
    } else {
      return 0;
    }
  }
  # this point ensures the stop of execution at some TaskID
  # .... but the STOP TaskID  is included / is executed yet,
  # just blocking the next one execution.
  # .... it's about START=11 STOP=11 - performs a task 11.
  if($REG_TASK and $REG_IDSTOP) {
    if($REG_TASK eq $REG_IDSTOP) { 
       $REG_STOP   = 1; 
       $REG_IDSTOP = 0;
    }
  }

  # Prompted Execution
  if($MODE_PROMPT) {
     if($REG_ONCE) { return 0; }
     my $ANS;
     #printty("#? Options: 1=once/2=retry/3=skip/4=terminate/5=view/6=set-reg/7=bash\n");

     xprintcode(%OPT);
     while(1) {
       xprint xcolor "#? Options: 1=once/2=retry/3=skip/4=stop/5=view\n";
       $ANS=xinput("#? wrapper> ");
       if($ANS =~ /^(1|go|once)$/)         { $REG_ONCE = 1; return 1; }                     # 1, once, go
       if($ANS =~ /^(2|retry|again)$/)     { $REG_ONCE = 0; return 1; }                     # 2, retry,  again
       if($ANS =~ /^(3|s|skip)$/)          { return 0; }                                    # 3, skip
       if($ANS =~ /^(4|[xqe]|exit|quit)$/) { $REG_STOP=1; xregsave(); return 0; }           # 4, exit

       if($ANS =~ /^(5|[vw]|view)$/) {                                                      # 5, VieW
         xprintcode(%OPT);
         next; 
       }

       if($ANS =~ /^(6|reg)/)   {                                                           # 6, config, memory, flags
         xgetregs(); next; 
       } 

       if($ANS =~ /^(7|[bi]|shell|bash)$/) {                                                # 7, bash, interpretor 
         printty "starting a sub-shell ...\n";
         if($^O =~ /MSWin32/) { xsystem("cmd.exe /L prompt sub-cmd\$G\$G\$S"); }
         else                 { xsystem("/bin/bash"); }
         next;
       }

       if($ANS =~ /^xlog$/)   {  xgetexp(); next; }
       #print "#- Warrning: Wrong option ! Use 1/2/3/4/5/6/7 !\n"; 
       xprint xcolor "#- Warrning: Wrong option ! Use 1/2/3/4/5 !\n"; 
     }
  }

  if($REG_TASK and $REG_FIRST) { 
    if($REG_TASK < $REG_FIRST) { return 0; }
  }
  if($REG_TASK and $REG_LAST) {
    if($REG_TASK > $REG_LAST) { return 0; }
  }


  unless($REG_ONCE) { xprintcode(%OPT); }
  # --auto
  if($MODE_AUTO) { 
    if($REG_ONCE) { return 0; }
    $REG_ONCE = 1;  return 1; 
  }

  if($MODE_PASSED) {
    unless($PRE_PASS) { return 0; }
    if($REG_ONCE)     { return 0; }
    $REG_ONCE = 1; return 1;
  }   

  if($MODE_FAILED) {
    unless($PRE_FAIL) { return 0; }
    if($REG_ONCE)     { return 0; }
    $REG_ONCE = 1; return 1;
  }   

  if($MODE_REDO) {
    #unless($REG_ONCE) { $REG_ONCE = 1; return 1; }
    if($REG_REDO) { return 1; }
    else          { return 0; }
  }

  xprint xcolor "#- Warning: Wrong mode of operation !\n";
  $REG_ONCE = 1; return 0;
}



####################################################################### }}} 1
## MAIN - MODE_NEW & MODE_MESSAGE ##################################### {{{ 1

xregload(1);
# In case when a file should be re-written,
# we delete its previous content to start from scratch.
if($MODE_NEW) {
  my $FILE_NAME = xFileName;
  if( -f $FILE_NAME) { 
    unlink $FILE_NAME; 
    xprint "#: Log file '${FILE_FNAME}' deleted.\n";
  }
}

# This one is for a single line messages (explicit in PreTask)
if($MODE_MESSAGE) {
  xopen(">>");
  xprint xcolor      $MODE_MESSAGE."\n";
  xwrite $FH_OUTPUT, $MODE_MESSAGE."\n";
  xlog               $MODE_MESSAGE."\n";
  xclose;
}

####################################################################### }}} 1
## MAIN - MODE_SSH #################################################### {{{ 1

if($MODE_SSH and $MODE_SSHJUMP) {
  # initiation
  xopen(">>");
  my $XCMD   = "";
  my $INPUT  = "";
  my $OUTPUT = "";
  my $FHIN;
  my $FHOUT;

  # builds a command
  if($^O =~ /MSWin32/) {
    $XCMD = "plink";
    if($MODE_PASSWORD) { $XCMD .= " -pw ${MODE_SSHJPWD}"; }
    $XCMD .= " -ssh ${MODE_SSHJUMP} 2>&1";
  } else {
    if($MODE_SSHJPWD ) { $XCMD  = "export SSHPASS='${MODE_SSHJPWD}'; sshpass -e ssh ${MODE_SSHJUMP}"; }
    else               { $XCMD  = "ssh ${MODE_SSHJUMP}"; }
    $XCMD .= " 2>&1";
  } 
  my @ASTDIN=();
  my @BSTDIN=();
  my $SSHCMD="";
  if($MODE_PASSWORD)  { $SSHCMD  = "export SSHPASS='${MODE_PASSWORD}'; sshpass -e ssh "; }
  elsif($MODE_SSHPASS){ $SSHCMD  = "sshpass -e ssh "; }
  else                { $SSHCMD  = "ssh "; }
  if($MODE_LOGIN)     { $SSHCMD .= "-l ${MODE_LOGIN} "; }
  $SSHCMD .= "${MODE_SSH} 2>&1 <<__SSHCMDS__\n";

  # reading STDIN - commands
  push @ASTDIN,$SSHCMD;
  while(my $LINE=<STDIN>) {
    push @ASTDIN,$LINE;
    push @BSTDIN,$LINE;
  }
  push @ASTDIN,"\nexit \$?\n";
  push @ASTDIN,"__SSHCMDS__\n";

  #- xprint xcolor "#- ${XCMD}\n"; # DEBUG MESSAGE
  my $EXIT=0;
  while(xdecide('cmd' => join("",@BSTDIN), 'note'=> "Jumped SSH login=${MODE_LOGIN}")) { 
    # command execution
    my $PID = open2($FHOUT, $FHIN, $XCMD);
    die "#- Error: None SSH jump session '${XCMD}' created !\n" unless $PID;
    foreach my $LINE (@ASTDIN) {
      print $FHIN $LINE;
    } 
    print $FHIN "\nexit \$?\n";
    close $FHIN;
    while(my $LINE=<$FHOUT>) {
      xprint xcolor $LINE;
      xwrite $FH_OUTPUT,$LINE;
      xlog   $LINE;
    }
    close $FHOUT; 
    waitpid($PID, &WNOHANG);
    $EXIT=$? >> 8;
  }

  # closure of action
  xclose;  
  exit $EXIT;
}


# Handling SSH Protocol commands
if($MODE_SSH) {

  # initiation
  xopen(">>");
  my $XCMD   = "";
  my $INPUT  = "";
  my $OUTPUT = "";
  my $FHIN;
  my $FHOUT;

  # builds a command
  if($^O =~ /MSWin32/) {
    $XCMD = "plink";
    if($MODE_LOGIN)    { $XCMD .= " -l ${MODE_LOGIN}"; }
    if($MODE_PASSWORD) { $XCMD .= " -pw ${MODE_PASSWORD}"; }
    $XCMD .= " -ssh ${MODE_SSH} 2>&1";
  } else {
    if($MODE_PASSWORD)  { $XCMD  = "(export SSHPASS='${MODE_PASSWORD}'; sshpass -e ssh"; }
    elsif($MODE_SSHPASS){ $XCMD  = "(sshpass -e ssh"; }
    else                { $XCMD  = "(ssh"; }
    if($MODE_LOGIN)     { $XCMD .= " -l ${MODE_LOGIN}"; }
    $XCMD .= " ${MODE_SSH} 2>&1)";
  } 
  my @ASTDIN=();

  # reading STDIN - commands
  while(my $LINE=<STDIN>) {
    push @ASTDIN,$LINE;
  }

  my $EXIT=0;
  # xprint xcolor "#- ${XCMD}\n"; # DEBUG
  while(xdecide('cmd' => join("",@ASTDIN), 'note'=> "SSH login=${MODE_LOGIN}")) {
    # command execution
    my $PID = open2($FHOUT, $FHIN, $XCMD);
    die "#- Error: None SSH session '${XCMD}' created !\n" unless $PID;
    foreach my $LINE (@ASTDIN) {
      print $FHIN $LINE;
    } 
    print $FHIN "\nexit \$?\n";
    close $FHIN;
    while(my $LINE=<$FHOUT>) {
      xprint xcolor $LINE;
      xwrite $FH_OUTPUT,$LINE;
      xlog   $LINE;
    }
    close $FHOUT; 
    waitpid($PID, &WNOHANG);
    $EXIT=$? >> 8;
  }

  # closure of action
  xclose;  
  exit $EXIT;
}

####################################################################### }}} 1
## MAIN - MODE_WMI ####################################################za {{{ 1
if($MODE_WMI and $MODE_SSHJUMP) {
  # initiation
  xopen(">>");
  my $XCMD   = "";
  my $INPUT  = "";
  my $OUTPUT = "";
  my $FHIN;
  my $FHOUT;

  # builds a command
  if($^O =~ /MSWin32/) {
    $XCMD = "plink";
    if($MODE_PASSWORD) { $XCMD .= " -pw ${MODE_SSHJPWD}"; }
    $XCMD .= " -ssh ${MODE_SSHJUMP} 2>&1";
  } else {
    if($MODE_SSHJPWD ) { $XCMD  = "export SSHPASS='${MODE_SSHJPWD}'; sshpass -e ssh ${MODE_SSHJUMP}"; }
    else               { $XCMD  = "ssh ${MODE_SSHJUMP}"; }
    $XCMD .= " ${MODE_SSH} 2>&1";
  } 
  my @ASTDIN=();
  my @BSTDIN=();
  unless($MODE_LOGIN and $MODE_PASSWORD) { die "#- WMI credentials are missing #2 !\n"; }
  my $WMICMD="winexe //${MODE_WMI} -U '${MODE_LOGIN}\%${MODE_PASSWORD}' \"cmd.exe\" 2>&1 <<__WMICMDS__\n";

  # reading STDIN - commands
  push @ASTDIN,$WMICMD;
  while(my $LINE=<STDIN>) {
    push @ASTDIN,$LINE;
    push @BSTDIN,$LINE;
  }
  push @ASTDIN,"\nexit \$?\n";
  push @ASTDIN,"__WMICMDS__\n";

  my $EXIT=0;
  while(xdecide('cmd' => join("",@BSTDIN), 'note'=> "Jumped WMI login=${MODE_LOGIN}")) {
    # command execution
    my $PID = open2($FHOUT, $FHIN, $XCMD);
    die "#- Error: None SSH jump session '${XCMD}' created !\n" unless $PID;
    foreach my $LINE (@ASTDIN) {
      print $FHIN $LINE;
    } 
    print $FHIN "\nexit \$?\n";
    close $FHIN;
    while(my $LINE=<$FHOUT>) {
      xprint xcolor $LINE;
      xwrite $FH_OUTPUT,$LINE;
      xlog   $LINE;
    }
    close $FHOUT; 
    waitpid($PID, &WNOHANG);
    $EXIT=$? >> 8;
  }

  # closure of action
  xclose;  
  exit $EXIT;
}

# Handling WMI Protocol commands
if($MODE_WMI) {

  # initiations
  xopen(">>");
  my $XCMD   = "";
  my $INPUT  = "";
  my $OUTPUT = "";
  my $FHIN;
  my $FHOUT;

  # builds a command
  if($^O =~ /MSWin32/) {
    $XCMD = "psexec.exe \\\\${MODE_WMI}";
    if($MODE_LOGIN)    { $XCMD .= " -u ${MODE_LOGIN}"; }
    if($MODE_PASSWORD) { $XCMD .= " -p ${MODE_PASSWORD}"; }
    $XCMD .= " \"cmd.exe\" 2>&1";
  } else {
    unless($MODE_LOGIN and $MODE_PASSWORD) { 
      die "#- Error: Login and Password must be defined !\n";
    }
    $XCMD = "winexe //${MODE_WMI} -U '${MODE_LOGIN}\%${MODE_PASSWORD}' \"cmd.exe\" 2>&1";
  } 
  my @ASTDIN=();

  # reading STDIN - commands
  while(my $LINE=<STDIN>) {
    push @ASTDIN,$LINE;
  }

  my $EXIT=0;
  while(xdecide('cmd' => join("",@ASTDIN), 'note'=> "WMI login=${MODE_LOGIN}")) {
    # command execution
    my $PID = open2($FHOUT, $FHIN, $XCMD);
    die "#- Error: None WMI session '${XCMD}' created !\n" unless $PID;
    foreach my $LINE (@ASTDIN) {
      print $FHIN $LINE;
    } 
    print $FHIN "\nexit \%errorlevel\%\n";
    close $FHIN;
    while(my $LINE=<$FHOUT>) {
      xprint xcolor $LINE;
      xwrite $FH_OUTPUT,$LINE;
      xlog   $LINE;
    }
    close $FHOUT; 
    waitpid($PID, &WNOHANG);
    $EXIT=$? >> 8;
  }

  # closure of action
  xclose;  
  exit $EXIT;
}

####################################################################### }}} 1
## MAIN - MODE_EXE #################################################### {{{ 1
if($MODE_EXE and $MODE_SSHJUMP) {
  # initiation
  xopen(">>");
  my $XCMD   = "";
  my $INPUT  = "";
  my $OUTPUT = "";
  my $FHIN;
  my $FHOUT;

  # builds a command
  if($^O =~ /MSWin32/) {
    $XCMD = "plink";
    if($MODE_PASSWORD) { $XCMD .= " -pw ${MODE_SSHJPWD}"; }
    $XCMD .= " -ssh ${MODE_SSHJUMP} 2>&1";
  } else {
    if($MODE_SSHJPWD ) { $XCMD  = "export SSHPASS='${MODE_SSHJPWD}'; sshpass -e ssh ${MODE_SSHJUMP}"; }
    else               { $XCMD  = "ssh ${MODE_SSHJUMP}"; }
    $XCMD .= " ${MODE_SSH} 2>&1";
  } 
  my @ASTDIN=();

  # reading STDIN - commands
  while(my $LINE=<STDIN>) {
    push @ASTDIN,$LINE;
  }
  
  my $EXIT=0;
  while(xdecide('cmd' => join("",@ASTDIN), 'note'=> "EXECUTE on SSHJUMP")) {
    # command execution
    my $PID = open2($FHOUT, $FHIN, $XCMD);
    die "#- Error: None SSH jump session '${XCMD}' created !\n" unless $PID;
    foreach my $LINE (@ASTDIN) {
      print $FHIN $LINE;
    } 
    print $FHIN "\nexit \$?\n";
    close $FHIN;
    while(my $LINE=<$FHOUT>) {
      xprint xcolor $LINE;
      xwrite $FH_OUTPUT,$LINE;
      xlog   $LINE;
    }
    close $FHOUT; 
    waitpid($PID, &WNOHANG);
    $EXIT=$? >> 8;
  }

  # closure of action
  xclose;  
  exit $EXIT;
}

if($MODE_EXE) {

  # initiations 
  xopen(">>");
  my $XCMD   = "";
  my $XEXIT  = "";
  my $INPUT  = "";
  my $OUTPUT = "";
  my $FHIN;
  my $FHOUT;

  # builds a command
  if($^O =~ /MSWin32/) {
    $XCMD = "cmd.exe 2>&1";
    $XEXIT= "\nexit \%errorlevel\%\n";
  } else {
    $XCMD = "/bin/bash 2>&1";
    $XEXIT= "\nexit \$?\n";
  }
  my @ASTDIN=();

  # reading STDIN - commands
  while(my $LINE=<STDIN>) {
    push @ASTDIN,$LINE;
  }

  my $EXIT=0;
  while(xdecide('cmd' => join("",@ASTDIN), 'note'=> "EXECUTE LOCALLY")) {
    # command execution
    my $PID = open2($FHOUT, $FHIN, $XCMD);
    die "#- Error: None EXEC session '${XCMD}' created !\n" unless $PID;
    foreach my $LINE (@ASTDIN) {
      print $FHIN $LINE;
    } 
    print $FHIN $XEXIT;
    close $FHIN;
    while(my $LINE=<$FHOUT>) {
      xprint xcolor $LINE;
      xwrite $FH_OUTPUT,$LINE;
      xlog   $LINE
    }
    close $FHOUT; 
    waitpid($PID, &WNOHANG);
    $EXIT=$? >> 8;
  }

  
  # closure of action
  xclose;  
  exit $EXIT;
  
}

####################################################################### }}} 1
## MAIN - STDIN+LOG & MODE_SHOW/cat/grep ############################## {{{ 1


# Platform based decission - even for logging
if($MODE_WIN or $MODE_LNX or $MODE_PLX) {
   my $PLAX = "";
   my $FLAG = 0;
   if(exists $ENV{PLAX}) { $PLAX = $ENV{PLAX}; }
   else { die "#- Error: Environment variable 'PLAX' is not defined !\n"; }
   if   ($MODE_LNX and ($PLAX=~/^Lnx/i))        { $FLAG = 1; }
   elsif($MODE_WIN and ($PLAX=~/^Win/i))        { $FLAG = 1; }
   elsif($MODE_PLX and ($PLAX=~/${MODE_PLX}/i)) { $FLAG = 1; }
   unless($FLAG) { exit; }
}

# handling simple STDIN going to Log-file
unless( -t STDIN) {
  xopen(">>");
  select((select(STDIN),  $|=1)[0]);  # makes the filehandler "HOT" - stops the buffering 
  select((select(STDOUT), $|=1)[0]);  # http://perl.plover.com/FAQs/Buffering.html
  while(my $LINE=<STDIN>) {
    #chomp $LINE;
    $LINE = xstrip $LINE;
    xprint xcolor $LINE;
    xwrite $FH_OUTPUT, $LINE;
    xlog   $LINE;
  }
  xclose;
}
if($MODE_SHOW) {
  xopen("<");
  while(my $LINE=<$FH_OUTPUT>) {
    if($MODE_GREP) { next unless $LINE =~ /${MODE_GREP}/; }
    xprint xcolor $LINE;
  }
  xclose;
}

####################################################################### }}} 1


# --- end ---
