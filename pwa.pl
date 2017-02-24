#!/usr/bin/perl
# PassWord Agent Utility
# 20160422, Ing. Ondrej DURAS (dury) +421-2-692-57912
# ~/prog/pwa/pwa.pl


## Manual ############################################################# {{{ 1

use strict;
use warnings;
use Data::Dumper;
use PWA;

our $VERSION = 2016.121201;
our $MANUAL  = <<__END__;
NAME: PassWord Agent Utility
FILE: ./pwa

DESCRIPTION:
  Utility to simplify PWA manipulation.

USAGE:
  ./pwa -list
  ./pwa -u user1 -login service_user1 -p pasw123
  ./pwa -u user2 -L -P

PARAMETERS:
  -list      - list of credentials [pw] (method) 
  -dump      - dumps internal credentials
  -clear     - removes my stored terminal session
  -clear-all - removes all stored sessions
  -remove    - removes user profile from session     
  -u / -U - user profile from command line
  -m / -M - user method
  -l / -L - user login 
  -p / -P - user password
  -i / -I - user description
  -a / -A - user specific atribute (use with -v)
  -v / -V - user specific value (use with -a)
  

VERSION: ${VERSION} .pl / ${PWA::VERSION} .pm
__END__

####################################################################### }}} 1
## Interface ########################################################## {{{ 1

sub test();
sub println($);
#sub debug($$);

our $MODE_DEBUG   = "";  # -debug <mode/s>
our $MODE_FILE    = "";  # -f file
our $MODE_IMPORTL = "";  # -i
our $MODE_IMPORTU = "";  # -I
our $MODE_EXPORTL = "";  # -w
our $MODE_EXPORTU = "";  # -W
our $MODE_USER    = "";  # -u user      -U
our $MODE_METH    = "";  # -m method    -M
our $MODE_LOGIN   = "";  # -l login     -L
our $MODE_PASSWORD= "";  # -p password  -P
our $MODE_DESC    = "";  # -i desc      -I
our $MODE_ATTRIB  = "";  # -a attribute -A
our $MODE_VALUE   = "";  # -v value     -V
our $MODE_QUERY   = "";  # -q attrib
our $MODE_QULOGIN = 0;   # -QL
our $MODE_QUPASS  = 0;   # -QP
our $MODE_QUATTR  = "";  # -QA attrib
our $MODE_REMOVE  = "";  # -rm user
our $MODE_WRITE   = 0;   # ...write if something has changed
our $MODE_LIST    = 0;   # -list
our $MODE_CLEARME = 0;   # -clear
our $MODE_CLEARALL= 0;   # -clear-all
our $MODE_DUMP    = 0;   # -dump
our $MODE_CRED    = 0;   # -cred
our $MODE_PWA     = 0;   # -pwa

unless(scalar @ARGV) { 
  print $MANUAL;
  exit 1;
}

while(my $ARGX = shift @ARGV) {
  if($ARGX =~ /^-+no-?debug/) { delete $ENV{MODE_DEBUG}; }
  if($ARGX =~ /^-+write/)     { $MODE_WRITE = 1; next; }
  if($ARGX =~ /^-+wr/)        { $MODE_WRITE = 1; next; }
  if($ARGX =~ /^-+no-?write/) { $MODE_WRITE = 0; next; }
  if($ARGX =~ /^-+no-?wr/)    { $MODE_WRITE = 0; next; }
  if($ARGX =~ /^-+debug/){ $ENV{$MODE_DEBUG} = shift @ARGV; next; }
  if($ARGX =~ /^-+test/) { test; next; }
  if($ARGX =~ /^-+gen/)  { println pwaGenerate(); next; }
  if($ARGX =~ /^-+file/) { println pwaSession();  next; }
  if($ARGX =~ /^-+time/) { println time;          next; }
  if($ARGX =~ /^-+list/) { $MODE_LIST  = 1; next; }
  if($ARGX =~ /^-+dump/) { $MODE_DUMP += 1; next; }
  if($ARGX =~ /^-+clear-?all/){ $MODE_CLEARALL = 1; next; }
  if($ARGX =~ /^-+clear/)     { $MODE_CLEARME  = 1; next; }
  if($ARGX =~ /^-+cred/) { $MODE_CRED  = 1; next; }
  if($ARGX =~ /^-+pwa/)  { $MODE_PWA   = 1; next; }
  if($ARGX =~ /^-+re?m/) { $MODE_REMOVE = shift @ARGV; $MODE_WRITE=2; next; }
  if($ARGX =~ /^-+del/)  { $MODE_REMOVE = shift @ARGV; $MODE_WRITE=2; next; }
  if($ARGX =~ /^-+[EC]/) { println pwaEncrypt(shift @ARGV,pwaPhrase()); next; }
  if($ARGX =~ /^-+D/)    { println pwaDecrypt(shift @ARGV,pwaPhrase()); next; }
  if($ARGX =~ /^-+[ec]/) { println pwaEncrypt(shift @ARGV); next; }
  if($ARGX =~ /^-+d/)    { println pwaDecrypt(shift @ARGV); next; }
  if($ARGX =~ /^-+u/)    { $MODE_USER     = shift @ARGV; $MODE_WRITE=2; next; }
  if($ARGX =~ /^-+m/)    { $MODE_METH     = shift @ARGV; $MODE_WRITE=2; next; }
  if($ARGX =~ /^-+l/)    { $MODE_LOGIN    = shift @ARGV; $MODE_WRITE=2; next; }
  if($ARGX =~ /^-+p/)    { $MODE_PASSWORD = shift @ARGV; $MODE_WRITE=2; next; }
  if($ARGX =~ /^-+i/)    { $MODE_DESC     = shift @ARGV; $MODE_WRITE=2; next; }
  if($ARGX =~ /^-+a/)    { $MODE_ATTRIB   = shift @ARGV; $MODE_WRITE=2; next; }
  if($ARGX =~ /^-+v/)    { $MODE_VALUE    = shift @ARGV; $MODE_WRITE=2; next; }
  if($ARGX =~ /^-+QA/)   { $MODE_QUATTR   = shift @ARGV; next; }
  if($ARGX =~ /^-+QL/)   { $MODE_QULOGIN  = 1;           next; }
  if($ARGX =~ /^-+QP/)   { $MODE_QUPASS   = 1;           next; }
  if($ARGX =~ /^-+q/)    { $MODE_QUERY    = shift @ARGV; next; }
  if($ARGX =~ /^-+U/)    { $MODE_USER     = pwaInput('User Profile: ');          $MODE_WRITE=2; next; }
  if($ARGX =~ /^-+M/)    { $MODE_METH     = pwaInput("[${MODE_USER}] Method: "); $MODE_WRITE=2; next; }
  if($ARGX =~ /^-+L/)    { $MODE_LOGIN    = pwaInput("[${MODE_USER}] Login: ");  $MODE_WRITE=2; next; }
  if($ARGX =~ /^-+P/)    { $MODE_PASSWORD = pwaInputVerify("[${MODE_USER}] Password: "); $MODE_WRITE=2; next; }
  if($ARGX =~ /^-+I/)    { $MODE_DESC     = pwaInput("[${MODE_USER}] Description: ");    $MODE_WRITE=2; next; }
  if($ARGX =~ /^-+A/)    { $MODE_ATTRIB   = pwaInput("[${MODE_USER}] attribute name: "); $MODE_WRITE=2; next; }
  if($ARGX =~ /^-+V/)    { $MODE_VALUE    = pwaInput("[${MODE_USER} => ${MODE_ATTRIB}] attribute value: "); 
                                            $MODE_WRITE=2; next; 
                         }
  if($ARGX =~ /^-+F/)    { $MODE_FILE     = shift @ARGV;  next; }
  if($ARGX =~ /^-+r/)    { $MODE_IMPORTL  = ($MODE_FILE ? $MODE_FILE : pwaConf('.pwa.dat')); $MODE_WRITE=2; next; } 
  if($ARGX =~ /^-+R/)    { $MODE_IMPORTU  = ($MODE_FILE ? $MODE_FILE : pwaConf('.pwa.pwa')); $MODE_WRITE=2; next; } 
  if($ARGX =~ /^-+w/)    { $MODE_EXPORTL  = ($MODE_FILE ? $MODE_FILE : pwaConf('.pwa.dat')); next; } 
  if($ARGX =~ /^-+W/)    { $MODE_EXPORTU  = ($MODE_FILE ? $MODE_FILE : pwaConf('.pwa.pwa')); next; } 
  die "#- Error ! Wrong argument '${ARGX}' !\n";
}
if($MODE_WRITE == 2) { $MODE_WRITE = 0; } # Temporary workaround as there is some bug

####################################################################### }}} 1
## Procedures ######################################################### {{{ 1


sub println($) {
  my $LINE = shift;
  $LINE =~ s/\n\Z//;
  if( -t STDOUT ) { $LINE .= "\n"; }
  print $LINE;
}

sub test() {
 my $hpsa=pwa('hpsa');
 my $root=pwa('root');

 print Dumper $hpsa;
 print "----------------\n";
 print Dumper $root;

 my ($METH,$USER,$PASS)=pwaCred('hpsa');
 print "${METH} ; ${USER} ; ${PASS}\n";
}

#sub debug($$) {
#  my ($LEVEL,$MESSAGE) = @_;
#  return unless $ENV{MODE_DEBUG};
#  return unless $ENV{MODE_DEBUG} =~ /${LEVEL}/;
#  print "#:${LEVEL} ${MESSAGE}\n";
#}

####################################################################### }}} 1
## Main ############################################################### {{{ 1

# lightweight import
if($MODE_IMPORTL) {
  my $DATA = pwaLoad($MODE_IMPORTL,'password'=>pwaDefault);
  %$SECRET = (%$SECRET,%$DATA);
  debug 1,"reading of ${MODE_IMPORTL} done. (-r)\n";
}

# Hard import
if($MODE_IMPORTU) {
  my $DATA = pwaLoad($MODE_IMPORTL,'password'=>pwaInputVerify('Main PWA Password: '));
  %$SECRET = (%$SECRET,%$DATA);
  debug 1,"reading of ${MODE_IMPORTU} done. (-R)\n";
}

# Modification of user profile data
if($MODE_USER) {
  my $PT;

  # creating a new user if does not exist yet
  unless($PT = $SECRET->{$MODE_USER}) {
    $PT = $SECRET->{$MODE_USER} = {};
  }
  if($MODE_METH) {
    $PT->{method} = $MODE_METH;
  }
  if($MODE_LOGIN) {
    $PT->{login} = $MODE_LOGIN;
  }
  if($MODE_PASSWORD) {
    $PT->{password} = pwaEncrypt($MODE_PASSWORD);
  }
  if($MODE_DESC) {
    $PT->{desc} = $MODE_DESC;
  }
  # specific attributes
  if($MODE_ATTRIB and $MODE_VALUE) {
    $PT->{$MODE_ATTRIB} = $MODE_VALUE;
  }
  if($MODE_QULOGIN) {
    unless( exists $PT->{login} ) {
      $PT->{login} = pwaInput("[${MODE_USER}] Login: ");
      $MODE_WRITE = 1;
    }
    my $L = $PT->{login};
    unless( $L ) { $L = ""; }
    #print "[${MODE_USER}] Login set to '${L}' .\n";
  }
  if($MODE_QUPASS) {
    unless( exists $PT->{password} ) {
      $PT->{password} = pwaEncrypt(pwaInputVerify("[${MODE_USER}] Password: "));
      $MODE_WRITE = 1;
    }
    #print "[${MODE_USER}] Password set to <<confidential>> .\n";
  }
  if($MODE_QUATTR) {
    unless( exists $PT->{$MODE_QUATTR} ) {
      $PT->{$MODE_QUATTR} = pwaInput("[${MODE_USER} => ${MODE_QUATTR}] Attribute: ");
      $MODE_WRITE = 1;
    }
    my $A = $PT->{$MODE_QUATTR}; 
    unless( $A ) { $A=""; }
    #print "[${MODE_USER} => ${MODE_QUATTR}] Attribute is set to '${A}' .\n";
  }
  if($MODE_QUERY and exists $PT->{$MODE_QUERY} ) {
    print $PT->{$MODE_QUERY};
    if( -t STDOUT ) { print "\n"; }
  }
}

if($MODE_CRED and $MODE_USER) {
  my $LOGIN    = $SECRET->{$MODE_USER}->{login}    or die "#- pwa CRED Error: login is missing !\n";
  my $PASSWORD = $SECRET->{$MODE_USER}->{password} or die "#- pwa CRED Error: password is missing !\n";
  $PASSWORD    = pwaDecrypt($PASSWORD);
  print "${LOGIN}\%${PASSWORD}";
  if( -t STDOUT ) { print "\n"; }
}

if($MODE_PWA and $MODE_USER) {
  my $METHOD   = $SECRET->{$MODE_USER}->{method};
  my $LOGIN    = $SECRET->{$MODE_USER}->{login}    or die "#- pwa CRED Error: login is missing !\n";
  my $PASSWORD = $SECRET->{$MODE_USER}->{password} or die "#- pwa CRED Error: password is missing !\n";
  $PASSWORD    = pwaDecrypt($PASSWORD);
  $METHOD      = "password" unless $METHOD;
  my $TEXT     = "${METHOD}:${LOGIN}:${PASSWORD}";
  print pwaEncrypt($TEXT,pwaPhrase());
  if( -t STDOUT ) { print "\n"; }
}

# removing whole user's profile
# or ( -a ) a singla attribute within user profile
if($MODE_REMOVE) {
  if($MODE_ATTRIB and exists $SECRET->{$MODE_REMOVE}) {
    my $PT = $SECRET->{$MODE_REMOVE};
    if(ref $PT) {
      delete $PT->{$MODE_ATTRIB};
    }
  } elsif( not $MODE_ATTRIB ) {
    delete $SECRET->{$MODE_REMOVE};
  } else {
    warn "#- Error: have a look on -remove attribute !\n";
  }
}

# lightweight export
if($MODE_EXPORTL) {
  pwaSave($MODE_EXPORTL,$SECRET,'password'=>pwaDefault);
  debug 1,"file ${MODE_EXPORTL} written. (-w)\n";
}

# hard export
if($MODE_EXPORTU) {
  pwaSave($MODE_EXPORTU,$SECRET,'password'=>pwaInputVerify('Main PWA Password: '));
  debug 1,"file ${MODE_EXPORTU} written. (-W)\n";
}

# Deleting only a session relater to the active terminal
if($MODE_CLEARME) {
  my $SEFILE = pwaSession;
  debug 1,"Deleting ${SEFILE}\n";
  unlink $SEFILE;
}

# Deleting all old .pwa. session files
if($MODE_CLEARALL) {
  #my $SEFILE=pwaSession;
  foreach my $FILE (glob(pwaFold('.pwa.*'))) {
    next unless $FILE =~ /\.pwa\.[0-9]+$/;
    #next if $FILE eq $SEFILE;
    debug  1,"Deleting ${FILE}";
    unlink $FILE;
  }
}

# listing user profiles and their statuses
if($MODE_LIST) {
  foreach my $USER ( sort keys %$SECRET ) {
    my $PT = $SECRET->{$USER};
    my $TEXT = $USER . " [";
    if($PT->{method})   { $TEXT .= 'm'; }
    if($PT->{login})    { $TEXT .= 'l'; }
    if($PT->{password}) { $TEXT .= 'p'; }
    if($PT->{desc})     { $TEXT .= 'i'; }
    if($USER =~ /\@\S+/){ $TEXT .= 'x'; }
    $TEXT .= "] ";
    if($PT->{method})   { $TEXT .= "(".$PT->{method}.") "; }
    if($PT->{desc})     { $TEXT .= $PT->{desc}; }
    print "${TEXT}\n";
  }
}

# Dumps internal data
if($MODE_DUMP) {
  pwaDumper $SECRET, $MODE_DUMP;
}

# writes/updates a session data
if($MODE_WRITE) {
  pwaSave(pwaSession,$SECRET,'password' => pwaPhrase, 'wrap' =>1);
  debug 1,"Session ".pwaSession." updated."; 
}

####################################################################### }}} 1

# ---- end ----
