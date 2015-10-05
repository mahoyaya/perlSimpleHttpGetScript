#!/usr/bin/env perl

use strict;
use warnings;
use Socket;

my $host = "127.0.0.1";
my $port = 80;
my $proxy_data = "";
my $proxy_host = "";
my $proxy_port = 80;
my $url_data = "";       # request url
my $ofile = "";          # output file name
my $out_data = "";       # output directory and file name
my $force = 0;           # force overwrite file
my $direct = 0;          # force direct connect

## set pxory from env
if( defined($ENV{'http_proxy'}) ) { if($ENV{'http_proxy' ne ""}){ $proxy_data = $ENV{'http_proxy'}; } }
if( defined($ENV{'HTTP_PROXY'}) ) { if($ENV{'HTTP_PROXY' ne ""}){ $proxy_data = $ENV{'HTTP_PROXY'}; } }

## test data
#$proxy_data = 'http://112.78.3.75:3128';
$url_data = 'http://ftp.riken.jp/Linux/centos/6.7/updates/x86_64/Packages/bash-4.1.2-33.el6_7.1.x86_64.rpm';
#$url_data = 'http://ftp.riken.jp/Linux/centos/6.7/os/x86_64/isolinux/splash.jpg';

if(scalar(@ARGV) < 2){ &getHelp; }

while(my $value = shift(@ARGV)){
  if($value =~ m/-h/){
    &getHelp;
  } elsif($value =~ m/-p/){
    $proxy_data = shift(@ARGV);
  } elsif($value =~ m/-u/){
    $url_data = shift(@ARGV);
  } elsif($value =~ m/-o/){
    $out_data = shift(@ARGV);
    # unsupported MSWin
    if($^O =~ m/MSWin.+/){
      $out_data = "";
      print "info: unsupported option `-o' on MSWin\n";
    }
  } elsif($value =~ m/-f/){
    $force++;
  } elsif($value =~ m/-d/){
    $direct++;
  }
}

# init
my $use_proxy = 0;
my $schema = ""; my $blank = ""; my $proxy_url = "";
my $url_base =""; my $url_options = "";
my @urlstrings = ();
my $parent = "";

#==================#
#  set proxy data  #
#==================#
if( $proxy_data =~ m|^http://.+:[0-9]{1,5}$| ){
  ($schema, $blank, $proxy_url) = split('/', $proxy_data);
  if($proxy_url =~ m/:/){
    ($proxy_host, $proxy_port) = split(':', $proxy_url);
  } else {
    $proxy_host = $proxy_url;
  }
  $use_proxy++;
} else {
  print "  info: proxy is not set.\n";
}

#================#
#  set url data  #
#================#
if( $url_data =~ m|^http://.+[:0-9]{0,1}[0-9]{0,4}/.+$| ){
  # escape options
  ($url_base, $url_options) = split('\?', $url_data);
  @urlstrings = split('/', $url_base);
  # set output file
  $ofile = $urlstrings[$#urlstrings];
  if($urlstrings[2] =~ m/:/){
    ($host, $port) = split(':', $urlstrings[2]);
  } else {
    $host = $urlstrings[2];
  }
} else {
  die "  error: please include schema to request url.\n    ex: http://foo.bar.com/public/foobar.rpm\n";
  exit 1;
}

#==================#
#  set output dir  #
#==================#
if( $out_data ne "" ){
  if(-f $out_data){
    $ofile = $out_data;
  }elsif(-d $out_data){
    $parent = $out_data;
  } elsif(-d getParent($out_data)){
    $parent = getParent($out_data);
    $ofile = getFilename($out_data);
  } else {
    die "error: invalid output path: $out_data"
  }
  $parent =~ s|/+|/|;
  $parent =~ s|/$||;
  print "  info: output to " . $parent . "/" .  $ofile . "\n";
  $ofile = $parent . "/" . $ofile;
} else {
  print "  info: output to current directory.\n";
}

my $request_url = "";
if($direct < 1 && $use_proxy > 0){
  $host = $proxy_host;
  if($proxy_port =~ m/[a-zA-Z][a-zA-Z0-9]*/){
    $port = getservbyname($proxy_port, 'tcp');
  } else {
    $port = $proxy_port;
  }
  $request_url = $url_data;
} else {
  $port = getservbyname($port, 'tcp') if $port =~ m/[a-zA-Z][a-zA-Z0-9]+/;
  for(my $i = 3; $i < scalar(@urlstrings); $i++){
    $request_url .= "/" . $urlstrings[$i];
  }
}

print "  info: connect to $host:$port\n";
print "  info: [send strings] GET " . $request_url . " HTTP/1.0\\r\\n\\r\\n\n";

my $iaddr = inet_aton($host) or die "error: can\'t resolve host: $host\n";
my $sock_addr = pack_sockaddr_in($port, $iaddr);


#=========================#
#  connect to remote host #
#=========================#
my $sock;
socket($sock, PF_INET, SOCK_STREAM, 0) or die "can\'t open socket\n";
connect($sock, $sock_addr) or die "can\'t connect remote host\n";


#=====================#
#  open output file   #
#=====================#
if( $force == 0 && -f $ofile ){ die "  error: file is exist: $ofile\n"; }
unlink($ofile);
open(my $ofh, '>', $ofile) or die "can\'t open the file: $ofile";
flock($ofh, 2);
binmode $ofh;

# no buffered sock $sock
select($sock); $|=1; select(STDOUT);
print $sock "GET " . $request_url . " HTTP/1.0\r\n";
print $sock "\r\n";

#=====================#
#  get http response  #
#=====================#
# print headers
while (<$sock>){
  print $_;
  last if m/^\r\n$/; }

# write data
$|=1;
while (<$sock>){
  print ".";
  print $ofh $_;
}
print "Complete\n";
$|=0;
close($ofh);

exit(0);


sub getHelp() {
  print << "EOL";
usage:
$0 -u http://url/file -p http://proxy:8080 -o /var/tmp/
  -u set a request url
  -p OPTION: set a proxy setting(default: use environment of http_proxy)
  -o OPTION: set a output directory or filename
  -f force overwrite
  -d force direct connect
EOL
  exit(0);

}

sub getParent {
  my $dir = shift;
  my @ary = split('/', $dir);
  my $parentDirectory;
  for(my $i = 0; $i < scalar(@ary) - 1; $i++){
    $parentDirectory .= "/" . $ary[$i];
  }
  if($dir =~ m|^[^/]|){ $parentDirectory =~ s|^/||; }
  return $parentDirectory;
}

sub getFilename {
  my $dir = shift;
  my @ary = split('/', $dir);
  my $filename;
  $filename = $ary[$#ary];
  return $filename;
}

