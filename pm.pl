#!/usr/bin/perl
##!/usr/bin/env perl
##!/root/home/hpoduras/perl/bin/perl
# Package Module Checker
# 20160405, Ing. Ondrej DURAS (dury)
# ~/bin/pm


#$CODE='return "hello world !";';
#$RET=eval($CODE);
#print $RET."\n";

our $VERSION = 2016.060601;
our @PKG_ALL = qw/
POSIX CGI DBI
Net::Telnet
Net::Telnet::Cisco
Net::SNMP Net::SMTP
Term::ReadKey
SOAP::Lite SOAP::WSDL
Crypt::SSLeay
IO::Socket::SSL
Net::SSLeay
HTML::Parser
MIME::Base64
URI
Bundle::LWP
/;

our @PKG_SOAP = qw/
Bundle::LWP
LWP
Crypt::SSLeay
IO::Socket::SSL
Net::SSLeay
HTML::Parser
MIME::Base64
URI
XML::Parser
XML::XPath
SOAP::Lite
SOAP::WSDL
/;

our @PKG_LITE = qw/
Class::Inspector Compress::Zlib FCGI
HTTP::Daemon IO::File IO::Socket::SSL
LWP::UserAgent MIME::Base64 Scalar::Util
Task::Weaken Test::More URI XML::Parser 
/;
our @PKG_WSDL = qw/
Data::Dumper SOAP::Lite XML::XPath
/;


sub check_pm($) {
 my $PM=shift;
 my $CODE=<<__END__;
 use ${PM};
 return \$${PM}::VERSION;
__END__
 my $RET=1;
 my $VER=eval($CODE);
 unless($VER) { $VER="! missing !"; $RET=0; }
 unless($VER=~/[0-9a-zA-Z]/) { $VER="found."; }
 print "....................."
   # . "....................."
     . " ${PM}\r${VER} \n";
   # . " ${VER}\r${PM} \n";
 return $RET;
}

sub check_pm_all(@) {
 my @PACKAGES = @_;
 $FOUND=0; $ALL=0;
 foreach $PM (sort @PACKAGES) {
   $ALL++;
   $FOUND += check_pm $PM;
 }
 return ($FOUND,$ALL);
}

sub list_inc() {
  my $COUNT=0; my $ALL=0;
  my $STAT;
  foreach my $DIR (@INC) {
    $STAT="! missing !";
    if( -d $DIR) { $STAT="found"; $COUNT++; }
    print ".................. ${DIR} \r ${STAT} \n";
    $ALL++;
  }
  print "${COUNT}/${ALL} folders found.\n";
}


sub list_repo588() {
  require $ENV{"HOME"}."/.cpan/CPAN/MyConfig.pm";
  my $CONF=$CPAN::Config;
  my $LIST=$CONF->{"urllist"};
   foreach my $URL ( @$LIST ) {
   print  "${URL}\n";
  }
}

sub which_pm($) {
  my $PKG = shift;
  my $PMP = $PKG; $PMP =~ s/::/\//g; $PMP = '/'.$PMP.'.pm';
  my $CTP = 0;
  print "#: which ${PKG} ... ${PMP}\n";
  foreach $PATH (@INC) {
   if( -f $PATH.$PMP )  { 
     print " PM found ${PATH}${PMP}\n";
     $CTP++;
   }
  }
  return $CTP;
}

unless(scalar @ARGV) { print <<__END__;
NAME: PM Checker
FILE: pm

DESCRIPTION:
  Helps to get an overview of installed
  Perl packages/Modules
  Then missing packages could be installed
  using cpan or ppm or ipm tool, depends
  on kind of PERL installed.

USAGE:
  ./pm POSIX CGI DBI Net::Telnet Net::SNMP
  ./pm -all
  ./pm -soap -lite -wsdl
  ./pm -inc
  cpan reload index
  cpan install DBI
  ppm install SOAP::Lite
  ppm install SOAP::WSDL


PARAMETERS:
  -all   - tests all predefined (favorite) packages
  -soap  - tests all packages related to HPSA 
  -lite  - packages dependent to SOAP::Lite
  -wsdl  - packages dependent to SOAP::WSDL 
  -which - lists all findengs 
  -repo  - lists CPAN repositories
  -inc   - lists \@INC folders, and checks they exist
SEE ALSO:
  http://search.cpan.org

VERSION: ${VERSION}
__END__
exit;
}



our $FOUND=0;
our $ALL=0;
our $PKGFIN=0;
our $MODE_WHICH = 0;
our $MODE_VER   = 1;
while($ARGX = shift @ARGV) {
  if($ARGX =~ /^-+all/)  { ($FOUND,$ALL)=check_pm_all(@PKG_ALL);  $PKGFIN=1; next; }
  if($ARGX =~ /^-+soap/) { ($FOUND,$ALL)=check_pm_all(@PKG_SOAP); $PKGFIN=1; next; }
  if($ARGX =~ /^-+lite/) { ($FOUND,$ALL)=check_pm_all(@PKG_LITE); $PKGFIN=1; next; }
  if($ARGX =~ /^-+wsdl/) { ($FOUND,$ALL)=check_pm_all(@PKG_WSDL); $PKGFIN=1; next; }
  if($ARGX =~ /^-+w/)    { $MODE_WHICH=1; $MODE_VER=0; next; }
  if($ARGX =~ /^-+repo/) { list_repo588; next; }
  if($ARGX =~ /^-+inc/)  { list_inc; next; }
  if($MODE_WHICH) { $FOUND += which_pm $ARGX; }
  if($MODE_VER)   { $FOUND += check_pm $ARGX; }
  $ALL++;
  $PKGFIN=1;
}
print "${FOUND}/${ALL} packages installed.\n" if $PKGFIN;


