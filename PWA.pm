#
# PWA.PM - Password Agent - Draft;
# 20160422, Ing. Ondrej DURAS (dury) +421-2-692-57912
# ~/prog/pwa/PWA.pm
#

## Interface ########################################################## {{{ 1

package PWA;

use strict;
use warnings;
use Exporter;
use IO::Handle;
use File::Basename;
use Term::ReadKey;
use Data::Dumper;
#use Data::Dumper;

our $VERSION=2016.121207;
our $PWA_DEFAULT_PHRASE="HPe#1Helion2VPC3!";
our $PWA_SESSION_PHRASE=$PWA_DEFAULT_PHRASE;
our $SECRET = {};
our $NEWDAT = {};
our $FILE   = "";

our @ISA=qw(
 Exporter
);

our @EXPORT= qw(
 $SECRET

 printty

 pwaFile
 pwaFold
 pwaConf
 pwaLogs

 pwaDumper
 pwaGenerate
 pwaDefault
 pwaPhrase
 pwaSession

 pwa
 pwaEncrypt
 pwaDecrypt
 pwaInput
 pwaInputSecret
 pwaInputVerify
 pwaYesNo

 pwaCred
 pwaMethod
 pwaLogin
 pwaPassword
 pwaLoad
 pwaSave

 debug
);

## use PWA qw(no-debug); # cuts debug function from exports
#sub import {
#  my $PKG = shift;
#  my @PAR = @_;
#  foreach my $ITEM (@PAR) {
#   if ($ITEM eq "no-debug") { pop @EXPORT; }
#  }
#}

####################################################################### }}} 1
## Prototypes ######################################################### {{{ 1

####################################################################### }}} 1
## internals ########################################################## {{{ 1

sub debug(;$$) {
  my ($LEVEL,$MESSAGE) = @_;
  return unless $ENV{MODE_DEBUG};
  #return unless $ENV{MODE_DEBUG} =~ /${LEVEL}/;
  my $SPACE="";
  if($MESSAGE) { $SPACE=" "; }
  print "#:${LEVEL}${SPACE}${MESSAGE}\n";
}


#FUNCTION:
#  printty $MSG;
#PARAMETERS:
#  $MSG - Output text message
#DESCRIPTION:
#  Provides output to the terminal even
#  the STDOUT is redirected. It's for user
#  interaction from scripts their standard
#  output has been / must be redirected.
#  export XXX=`myScript` cases
#


sub printty($) {
  my $MSG = shift;
  my $FLAG = 0;
  my $FH;

  # colo change for special queries
  unless( $^O =~ /win/i ) {
     $MSG = "\033[0;36m${MSG}\033[m";
  }
  # if none
  if( -t STDOUT ) {
    print $MSG;
    return;
  }
  if( -t STDERR ) {
    print STDERR $MSG;
    return;
  }
  my $TERM = "";
  if( exists $ENV{"SSH_TTY"} ) {
    $TERM = $ENV{"SSH_TTY"};
  } else {
    $TERM = qx(tty);
  }
  open $FH,">",$TERM or die "Error ! Terminal issue !\n";
  print $FH $MSG;
  close $FH;
}

#FUNCTION:
#  pwaDumper($SECRET,$LEVEL)
#PARAMETERS:
#  $SECRET - structure, taken from .pwa.ini /.pwa.dat /.pwa.<term>
#  LEVEL   - if >=2 then passwors shown, otherwise hiden
#DESCRIPTION:
#  Dumps PWA sensitive data to STDOUT
#  if there is LEVEL >= 2, then shows passwords
#  otherwise it replaces password by <<confidential>>

sub pwaDumper($$) {
  my($SECRET,$LEVEL) = @_;
  if($LEVEL >=2 ) { 
    print Dumper $SECRET;
    return;
  }
  my $EMPTY='          ';  
  print "\$VAR1 = {\n";
  foreach my $KEY ( sort keys %$SECRET ) {
    my $VAL = $SECRET->{$KEY};
    if ( $KEY =~ /password/) {
         $VAL = "<< confidential >>";
    }
    unless(ref($VAL)) { 
      print "${EMPTY}'${KEY}' => '${VAL}'\n";
      next;
    }
    print "${EMPTY}'${KEY}' => {\n";
    foreach my $KEY ( sort keys %$VAL ) {
      my $DAT = $VAL->{$KEY};
      unless(defined($DAT)) { $DAT = ""; }
      if ( $KEY =~ /password/) {
           $DAT = "<< confidential >>";
      }
      print "${EMPTY}${EMPTY}'${KEY}' => '${DAT}'\n";
    }
    print "${EMPTY}}\n";
  }
  print "}\n";
}

####################################################################### }}} 1
## pwaFold pwaLogs pwaConf ############################################ {{{ 1

#FUNCTION:
#  $FILE2=pwaFile($PATH,$FILE1,%OPT);
#  $DIR=dirAny($PATH,"","create"=>1);
#PARAMETERS:
#  $FILE2 - returned file with whole PATH
#  $DIR   - returned directory
#  $PATH  - Path to the directory
#  $FILE1 - file name without the path
#  "create"=>1 - creates a directory if does not exist
#DESCRIPTION:
#  Minor function used by dirFold, dirConf, dirLogs
#  Finishes handling of directories, files
sub pwaFile($;$%) {
  my($PATH,$FILE,%OPT) = @_;

  # Creating forlder if necessary
  if($OPT{"create"} and (not -d $PATH)) {
    mkdir $PATH or warn "Trouble to create a foledr ${PATH} !";
  }

  # adding a filename to the PATH
  if($FILE) {
    if($^O =~ /win/i) { $PATH .= "\\${FILE}"; }
    else              { $PATH .= "/${FILE}"; }
  }
  return $PATH;
}

sub pwaFold(;$%) {
  my($FILE,%OPT) = @_;
  my $PATH="";

  # taking a folder where we should write
  if(exists($ENV{"DATA_FOLD"}))       { $PATH=$ENV{"DATA_FOLD"}; }
  elsif(exists($ENV{"HOME"}))         { $PATH=$ENV{"HOME"}; }
  elsif(exists($ENV{"APPDATA"}))      { $PATH=$ENV{"APPDATA"}; }
  elsif(exists($ENV{"LOCALAPPDATA"})) { $PATH=$ENV{"LOCALAPPDATA"}; }
  elsif(exists($ENV{"USERPROFILE"}))  { $PATH=$ENV{"USERPROFILE"}; }
  else                                { $PATH=dirname(__FILE__); }

  return pwaFile($PATH,$FILE,%OPT);
}

sub pwaLogs(;$%) {
  my($FILE,%OPT) = @_;
  my $PATH="";

  if(exists($ENV{"DATA_LOGS"}))       { $PATH=$ENV{"DATA_LOGS"}; }
  elsif(exists($ENV{"HOME"}))         { $PATH=$ENV{"HOME"}; }
  elsif(exists($ENV{"LOCALAPPDATA"})) { $PATH=$ENV{"LOCALAPPDATA"}; }
  elsif(exists($ENV{"APPDATA"}))      { $PATH=$ENV{"APPDATA"}; }
  elsif(exists($ENV{"USERPROFILE"}))  { $PATH=$ENV{"USERPROFILE"}; }
  else                                { $PATH=dirname(__FILE__); }

  return pwaFile($PATH,$FILE,%OPT);
}

sub pwaConf(;$%) {
  my($FILE,%OPT) = @_;
  my $PATH="";

  if(exists($ENV{"DATA_CONF"}))       { $PATH=$ENV{"DATA_CONF"}; }
  elsif(exists($ENV{"HOME"}))         { $PATH=$ENV{"HOME"}."/.ssh"; }
  elsif(exists($ENV{"APPDATA"}))      { $PATH=$ENV{"APPDATA"}; }
  elsif(exists($ENV{"LOCALAPPDATA"})) { $PATH=$ENV{"LOCALAPPDATA"}; }
  elsif(exists($ENV{"USERPROFILE"}))  { $PATH=$ENV{"USERPROFILE"}; }
  else                                { $PATH=dirname(__FILE__); }

  return pwaFile($PATH,$FILE,%OPT);
}

####################################################################### }}} 1
## pwaEncrypt / pwaDecrypt ############################################ {{{ 1

sub pwaChar($$$$) {
  my($CHR,$PHRASE,$REFA,$REFB) = @_;
  my $IDX;
  my $LEN = length($PHRASE);
  $LEN = 1 unless $LEN;
  $$REFB=($$REFB +1 ) % 256;
  $$REFA=(($$REFA + $$REFB) ) % 256;
  $IDX = ($$REFA * $$REFB) % $LEN;
  my $CHX = $CHR ^ $$REFA ^ ord(substr($PHRASE,$IDX,1));
  #print "#: CHR=${CHR} CHX=${CHX} REFA=${${REFA}} REFB=${${REFB}} IDX=${IDX}\n";
  return $CHX;
}

sub pwaEncrypt($;$%) {
  my ($TEXT,$PHRASE,%OPT) = @_;
  unless($PHRASE) { $PHRASE=$PWA_DEFAULT_PHRASE; }
  unless(length($PHRASE) >=2 ) {
    $PHRASE = $PWA_DEFAULT_PHRASE;
  }
  my ($KEYA,$KEYB) = $PHRASE =~ m/^(\S)(\S).*/;

  $KEYA = ord($KEYA);
  $KEYB = ord($KEYB);

  my $REFA=\$KEYA;
  my $REFB=\$KEYB;

  my $CODE = $TEXT;
  unless($CODE) { $CODE=""; }
  $CODE =~ s/(.)/sprintf("%02x",pwaChar(ord($1),$PHRASE,$REFA,$REFB))/seg;
  if($OPT{"wrap"}) {
    $CODE =~ s/(.{77})/$1\n/gm;
  }
  return $CODE;
}

sub pwaDecrypt($;$%) {
  my ($CODE,$PHRASE,%OPT) = @_;
  unless($PHRASE) { $PHRASE=$PWA_DEFAULT_PHRASE; }
  unless(length($PHRASE) >=2 ) {
    $PHRASE = $PWA_DEFAULT_PHRASE;
  }
  my ($KEYA,$KEYB) = $PHRASE =~ m/^(\S)(\S).*/;

  $KEYA = ord($KEYA);
  $KEYB = ord($KEYB);

  my $REFA=\$KEYA;
  my $REFB=\$KEYB;
  my $TEXT =  $CODE;
  unless($TEXT) { $TEXT=""; }
  $TEXT =~ s/[^0-9-A-Fa-f]//mg;
  $TEXT =~ s/([0-9a-fA-F][0-9a-fA-F])/chr(pwaChar(hex($1),$PHRASE,$REFA,$REFB))/segm;
  return $TEXT;

}
 
####################################################################### }}} 1
## pwaInput / pwaInputSecret / pwaInputVerify ######################### {{{ 1

#FUNCTION
#  $LOGIN=pwaInput($PROMPT);
#PARAMETERS:
#  $LOGIN  - given text value / mostly the login
#  $PROMPT - prompt shown when user is asked
#DESCRIPTION:
#  queries user to provide a text (mostly the login)

sub pwaInput(;$) {
  my $PROMPT = shift;
  $PROMPT = "Login: " unless $PROMPT;
  printty $PROMPT;
  flush STDIN;
  my $DATA=<STDIN>;
  chomp $DATA;
  return $DATA;
}

#FUNCTION
#  $PASSWORD=pwaInputSecret($PROMPT);
#PARAMETERS:
#  $PASSWORD  - given confidential text value / mostly the password
#  $PROMPT    - prompt shown when user is asked
#DESCRIPTION:
#  queries user to provide a confidential text (mostly the password)

sub pwaInputSecret(;$) {
  my $PROMPT = shift;
  $PROMPT = "Password: " unless $PROMPT;
  printty $PROMPT;
  ReadMode 2;
  flush STDIN;
  my $DATA=<STDIN>;
  ReadMode 0;
  printty "\n";
  chomp $DATA;
  return $DATA;
}

#FUNCTION
#  $PASSWORD=pwaInputVerify($PROMPT);
#PARAMETERS:
#  $PASSWORD  - given confidential text value / mostly the password
#  $PROMPT    - prompt shown when user is asked
#DESCRIPTION:
#  queries user to provide a confidential text (mostly the password)
#  It queries twice and compares the entered values.
#  If values do not match, the the users is asked again (twice)

sub pwaInputVerify(;$$) {
  my ($PROMPT1,$PROMPT2,$MSGPASS,$MSGFAIL) = @_;
  $PROMPT1  = "Password: "       unless $PROMPT1;
  $PROMPT2  = "Retype ".$PROMPT1 unless $PROMPT2;
  $MSGPASS  = "Good."            unless $MSGPASS;
  $MSGFAIL  = "Try again !"      unless $MSGFAIL;
  my $AGAIN = 1;
  my $PASS1 = "";
  my $PASS2 = "";
  while($AGAIN) {
    $PASS1 = pwaInputSecret($PROMPT1);
    $PASS2 = pwaInputSecret($PROMPT2);
    if ( $PASS1 eq $PASS2 ) {
      $AGAIN = 0; printty "${MSGPASS}\n";
    } else {
      printty "${MSGFAIL}\n";
    }
  }  
  return $PASS1;  
}

#FUNCTION:
#  if(pwaYesNo("Continue ?") { ... }
#PARAMETERS
#  output value is a boolean 0/1
#  PROMPT - is a question shown on the STDOUT
#DESCRIPTION:
#  Quesries the user to answer a boolean question 
#  where Yes=1/No=0 are an only possible answers.

sub pwaYesNo($;%) {
  my ($PROMPT,%OPT) = @_;
  my $ANS = "";
  do {
     $ANS = lc(pwaInput("${PROMPT} [y/n]: "));
  } while( $ANS !~ /[yn]/ );
  return 1 if $ANS eq "y";
  return 0;
}

####################################################################### }}} 1
## pwaGenerate / pwaPhrase / pwaSession / pwaDefault ################## {{{ 1

sub pwaDefault() {
  return $PWA_DEFAULT_PHRASE;
}

#FUNCTION:
#  $PHRASE=pwaPhrase;
#  $PHRASE=pwaPhrase("session" => 1);
#PARAMETERS:
#  $PHRASE - returned phrase related to the actual session
#  "session"=>1 - string generated on session data basis
#DESCRIPTION:
#  Returns a phrase to decrypt/encrypt a credentials, related
#  to actual session

sub pwaPhrase(%) {
  my (%OPT) = @_;
  my $PHRASE="";
  my $TTY;

  if(exists($ENV{"SESSIONNAME"})) { 
    $TTY=$ENV{"SESSIONNAME"}; $TTY=~s/[^0-9]//g; 
  }
  if(exists($ENV{"SSH_TTY"}))     { 
    $TTY=$ENV{"SSH_TTY"};     $TTY=~s/[^0-9]//g; 
  } else {
    $TTY=qx(tty);
    unless($TTY =~ /[0-9]/) {
      $TTY = '1234';
    }
    $TTY=~s/[^0-9]//g;
  }
  unless($TTY =~ /[0-9]/) { $TTY="0"; }
  $PHRASE .= $TTY;

  if(exists($ENV{"SSH_AUTH_SOCK"})) {
    my $SOCK = $ENV{"SSH_AUTH_SOCK"};
    $SOCK =~ s/(ssh|agent|tmp)//g;
    $SOCK =~ s/[^A-Za-z0-9]//g;
    $PHRASE .= $SOCK;
  }
  if(exists($ENV{"SSH_CLIENT"})) {
    my $PORT .= $ENV{"SSH_CLIENT"};
    $PORT =~ s/.* ([0-9]+) .*/$1/;
    $PHRASE .= $PORT;
  }
  if(length($PHRASE)<7) { $PHRASE .= $PWA_DEFAULT_PHRASE; }
  
  if($OPT{"session"}) { return $PHRASE; }
  elsif(exists($ENV{"DATA_LOCK"})) {  
    $PWA_SESSION_PHRASE = pwaDecrypt($ENV{"DATA_LOCK"},$PHRASE); 
  }
  else { 
    $PWA_SESSION_PHRASE = $PWA_DEFAULT_PHRASE; 
  }
  return $PWA_SESSION_PHRASE;
}

#FUNCTION:
#  $PHRASE=pwaGenerate;
#PARAMETERS:
#  $PHRASE  - returned random string
#DESCRIPTION:
#  Generates a random string/phrase to encrypt/decrypt
#  session protected credentials

sub pwaGenerate(%) {
  my (%OPT) = @_;
  my $PHRASE="";
  my $COUNT=int(rand(10))+17;
  for(my $I=1;$I<=$COUNT;$I++) {
   $PHRASE .= chr(int(rand(25))+65);
  }
  return pwaEncrypt($PHRASE,pwaPhrase('session' =>1));
}

#FUNCTION:
#  $FILE=pwaSession();
#PARAMETERS:
#  $FILE - returned filename including whole path
#DESCRIPTION:
#  provides a filename & whole path to the ecprypted
#  session file that maintains a session credentials
#  when a session terminates, session credentials should not
#  be usable anymore.

sub pwaSession(%) {
  my (%OPT) = @_;

  # taking a session ID
  my $TTY = "";
  if(exists($ENV{"SESSIONNAME"})) { $TTY=$ENV{"SESSIONNAME"}; $TTY=~s/[^0-9]//g; }
  if(exists($ENV{"SSH_TTY"}))     { $TTY=$ENV{"SSH_TTY"};     $TTY=~s/[^0-9]//g; }
  unless($TTY) { $TTY="0"; }


  return pwaFold(".pwa.${TTY}",%OPT);

}

####################################################################### }}} 1
## pwaEncode / pwaDecode ############################################## {{{ 1


#FUNCTION:
#  $HASH_REF=pwaDecode($TEXT_INI; ...)
#PARAMETERS:
#  $HASH_REF - reference to whole structure
#  $TEXT_INI - text of configuration in .INI format
#  'lc'=>1   - all keys in HASH are going to be lower case
#  'uc'=>1   - all keys in HASH are going to be UPPER case
#  ...       - otherwise the keys are KeySensitive
#DESCRIPTION:
#  reads an .INI text string into HASH
#  returns a hash reference

sub pwaDecode($;%) {
  my ($TEXT,%OPT) = @_;
  my $CONFIG = {};
  my $PREFIX = "";
  my $PT     = $CONFIG;
  my $METH   = "";

  if(ref($TEXT) eq "ARRAY") {
    $TEXT = join("\n", @$TEXT);
  } elsif(ref($TEXT) eq "SCALAR") {
    $TEXT = $$TEXT;
  }

  foreach my $ITEM (split(/\n/,$TEXT)) {
    my $LINE = $ITEM;
    $LINE =~ s/^\s+//;
    $LINE =~ s/\s+$//;
    next unless $LINE =~ /\S/;
    next if     $LINE =~ /^#/;

    if($LINE =~ /^\[(\S+)\]$/) { 
      $PREFIX =  $1;
      if($OPT{lc})    { $PREFIX = lc $PREFIX; }
      elsif($OPT{uc}) { $PREFIX = uc $PREFIX; }
      # $PREFIX =  $LINE; 
      # $PREFIX =~ s/^\[//;
      # $PREFIX =~ s/\]$//;
      unless( exists $CONFIG->{$PREFIX} ) {
        $PT = $CONFIG->{$PREFIX} = {};
      } else {
        $PT = $CONFIG->{$PREFIX};
      }
      next;
    }
    my ($KEY,$VAL) = split(/\s*=\s*/,$LINE,2);
    if($OPT{lc})    { $KEY = lc $KEY; }
    elsif($OPT{uc}) { $KEY = uc $KEY; }
    $PT->{$KEY} = $VAL;
  }
  return $CONFIG;
}

#FUNCTION:
#  $TEXT_INI=pwaEncode($HASH_REF; ...)
#PARAMETERS:
#  $TEXT_INI - text of configuration in .INI format
#  $HASH_REF - reference to whole structure
#  'lc'=>1   - all keys in HASH are going to be lower case
#  'uc'=>1   - all keys in HASH are going to be UPPER case
#  ...       - otherwise the keys are KeySensitive
#DESCRIPTION:
#  translates config structure HASH_REF to TEXT_INI format
#  returns a text in format of .INI file

sub pwaEncode($;%) {
  my ($CONFIG,%OPT) = @_;
  my $TEXT   = "";
  my ($NEW,$KEY,$VAL,$PT);

  foreach $KEY ( sort keys %$CONFIG ) {
    $VAL  = $CONFIG->{$KEY};
    next if ref($VAL);
    if($OPT{lc})    { $NEW = lc $KEY; }
    elsif($OPT{uc}) { $NEW = uc $KEY; }
    else            { $NEW =    $KEY; }
    $TEXT .= "${NEW} = ${VAL}\n";
  }

  foreach $KEY ( sort keys %$CONFIG ) {
    next unless ref($PT = $CONFIG->{$KEY});
    if($OPT{lc})    { $NEW = lc $KEY; }
    elsif($OPT{uc}) { $NEW = uc $KEY; }
    else            { $NEW =    $KEY; }
    $TEXT .= "[${NEW}]\n";
    foreach my $KEY ( sort keys %$PT ) {
      $VAL = $PT->{$KEY};
      unless( defined($VAL)) { $VAL = ""; }
      if($OPT{lc})    { $NEW = lc $KEY; }
      elsif($OPT{uc}) { $NEW = uc $KEY; }
      else            { $NEW =    $KEY; }
      $TEXT .= "  ${NEW} = ${VAL}\n";
    }
    $TEXT .= "\n";
  }
  return $TEXT;
}

####################################################################### }}} 1
## pwaLoad / pwaSave / pwaEnv ######################################### {{{ 1

#FUNCTION:
#  $HASH_REF=iniLoad('config.ini'; ...);
#PARAMETERS:
#  $HASH_REF    - refers to hash including config parameters
#  'config.ini' - file name, it is going to be read
#  'lc'=>1   - all keys in HASH are going to be lower case
#  'uc'=>1   - all keys in HASH are going to be UPPER case
#  'cs'=>1   - all keys in HASH are going to be CaseSensitive case
#  ...       - default behaviour is 'lc' => 1
#DESCRIPTION:
#  Reads .INI configuration file into HASH
#  returns a pointer to HASH of config data

sub pwaLoad($;%) {
  my ($FNAME,%OPT) = @_;
  my $CONFIG = {};
  my $FH;

  open $FH,"<",$FNAME or return $CONFIG;
  my $TEXT = join("",<$FH>);
  close $FH;

  if($OPT{password}) {
    $TEXT = pwaDecrypt($TEXT,$OPT{password});
  }
  unless($OPT{uc} or  $OPT{cs}) { $OPT{lc}=1; }
  return pwaDecode($TEXT,%OPT);
}

#FUNCTION:
#  $RESULT=iniSave('config.ini',$CONFIG; ...);
#PARAMETERS:
#  $RESULT   - 1 for success / 0 for failure
#  $HASH_REF    - refers to hash including config parameters
#  'config.ini' - file name, it is going to be read
#  'lc'=>1   - all keys in HASH are going to be lower case
#  'uc'=>1   - all keys in HASH are going to be UPPER case
#  ...       - default behaviour is 'uc' => 1
#DESCRIPTION:
#  Reads .INI configuration file into HASH
#  returns a pointer to HASH of config data

sub pwaSave($$;%) {
  my ($FNAME,$CONFIG,%OPT) = @_;
  my $FH;
  unless(ref($CONFIG) eq "HASH") {
    die "#- Error ! iniSave 2nd parameter is not hash !\n";
  }
  if($OPT{"pm"}) {
    $FNAME = pwaFile(dirname(__FILE__),'.pwa.ini');
  } 

  unless($OPT{lc} or  $OPT{cs}) { $OPT{uc}=1; }
  my $TEXT = pwaEncode($CONFIG,%OPT);
  if($OPT{password}) {
    $TEXT = pwaEncrypt($TEXT,$OPT{password});
  }

  open $FH,">",$FNAME or return 0;
  print $FH $TEXT;
  close $FH;
  return 1;
}


#FUNCTION:
#  
sub pwaEnv(;%) {
  my (%OPT) = @_;
  my $PHRASE = pwaPhrase();
  my ($USER,$METH,$LOGIN,$PASSWORD);
  my $CONFIG = {};
  if($OPT{secret}) {
    $CONFIG = $SECRET;
  }

  foreach my $ITEM ( sort keys %ENV ) {
    $USER = lc($ITEM);

    if($ITEM =~ /^CRED_/) {
      ($LOGIN,$PASSWORD) = split(/\%|;|:/,$ENV{$ITEM},2);
      $METH =  'password';
      $USER =~ s/^cred_//;
    } elsif ($ITEM =~ /^PWA_/) {
      my $DATA = pwaDecrypt($ENV{$ITEM},$PHRASE);
      ($METH,$LOGIN,$PASSWORD) = split(/\%|;|:/,$DATA,3);
      $USER   =~ s/^pwa_//;
    } elsif ($ITEM =~ /^VAR_/) {
      my ($TYPE,$USER,$VAR) = split(/_/,lc($ITEM),3);
      next unless($TYPE and $USER and $VAR);
      next unless(exists $CONFIG->{$USER});
      my $PT = $CONFIG->{$USER};
      $PT->{$VAR} = $ENV{$ITEM};
    } else { next; }

    if(not exists($CONFIG->{$USER})) { 
      $CONFIG->{$USER} = {}; 
    }
    my $PT = $CONFIG->{$USER};
    $PT->{method}   = $METH;
    $PT->{login}    = $LOGIN;
    $PT->{password} = pwaEncrypt($PASSWORD);
    
  }
  return $CONFIG;
}

####################################################################### }}} 1
## pwa / pwaMethod / pwaLogin / pwaPassword / pwaCred ################# {{{ 1

sub pwa($;$) {
  my($USER,$DETAIL) = @_;
  my $PT;

  # potentially user@hostname should work here
  unless( $PT = $SECRET->{$USER} ) {
    # is the user@hostname ?
    unless($USER =~/\S+\@\S+/) {
      return undef;
    }
    # if user@hostname then trying to 
    # find def for {user}
    $USER  =~ s/\@\S+//;
    unless( $PT = $SECRET->{$USER} ) {
      return undef;
    }
  }
  unless($DETAIL) {
    return $PT;
  }

  my $RET = $PT->{$DETAIL};
  return "" unless $RET;
  return $RET;
}


sub pwaMethod($) {
  my $METHOD = pwa(shift,'method');
  unless($METHOD) { $METHOD = 'password'; }
  return $METHOD;
}

sub pwaLogin($) {
  return pwa(shift,'login');
}


sub pwaPassword($) {
  return pwaDecrypt(pwa(shift,'password'));
}

sub pwaCred($) {
  my $USER = shift;
  return (
    pwaMethod($USER),
    pwaLogin($USER),
    pwaPassword($USER)
  );
}

####################################################################### }}} 1
## MAIN Initiation #################################################### {{{ 1

$SECRET = {};
$NEWDAT = {};

# loads an session data if exist
$FILE = pwaSession();
if( -f $FILE) {
  $NEWDAT  = pwaLoad($FILE,'password' => pwaPhrase());
  %$SECRET = (%$SECRET,%$NEWDAT);
} else {

  # loads a vendor/security configuration
  $FILE = pwaFile(dirname(__FILE__),'.pwa.ini');
  if( -f $FILE) {
    $NEWDAT  = pwaLoad($FILE);
    %$SECRET = (%$SECRET,%$NEWDAT);
  }

  ## loads a vendor/security configuration
  #$FILE = pwaConf('.pwa.dat');
  #if( -f $FILE) {
  #  $NEWDAT  = pwaLoad($FILE, 'password' => $PWA_DEFAULT_PHRASE );
  #  %$SECRET = (%$SECRET,%$NEWDAT);
  #}

  # loads a user's configuration
  $FILE = pwaConf('.pwa.ini');
  if( -f $FILE) {
    $NEWDAT  = pwaLoad($FILE);
    %$SECRET = (%$SECRET,%$NEWDAT);
  }

}
$SECRET = pwaEnv( 'secret' => 1);
1;

####################################################################### }}} 1

# --- end ---
