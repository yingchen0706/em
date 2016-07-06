#!/usr/bin/perl -w
# $version$
# 
# Copyright (c) 2005, 2016, Oracle and/or its affiliates. All rights reserved.
#
#  NAME
#     siebelGenRespFile.pl
#
#  DESCRIPTION
#     This script is used to generate response files for Siebel PatchSet installation.
#

#require 5.6.1;

use strict;
use File::Copy;

my %param;

sub processArgs {
  my $key;
  my $val;
  my $index = 0;

  foreach my $arg (@ARGV) {
    if ($index % 2 == 0) {
      $key = substr $arg, 1;
    } else {
      $val = $arg;
      $param{$key} = $val;
      #print $key."=".$val;    
    }
    $index++;
  }
}

sub genRespFile {
  my %args = @_;

  if (!defined $args{pn}) {
    print "Error: Response file path invalid! \n";
    return;
  }

  my $filename = $args{pn};
  my $tempfile = $filename.".temp";
  
  #print "Creating response file from template file - $filename \n";
  
  if(open(temp_FH, ">", $tempfile)) {
    print temp_FH "RESPONSEFILE_VERSION=2.2.1.0.0\n";
    print temp_FH "s_shiphomeLocation=\"$args{sh}\"\n";
    print temp_FH "FROM_LOCATION=\"$args{fl}\"\n";
    print temp_FH "s_topLevelComp=\"$args{tl}\"\n";
    print temp_FH "s_SiebelVersion=\"$args{sv}\"\n";
    print temp_FH "ORACLE_HOME=\"$args{oh}\"\n";
    print temp_FH "ORACLE_HOME_NAME=\"$args{on}\"\n";
    print temp_FH "b_isGatewayInstalled=\"$args{gi}\"\n";
    print temp_FH "b_isSiebsrvrInstalled=\"$args{si}\"\n";
    print temp_FH "selectedLangs=\"$args{sl}\"\n";
    print temp_FH "DEINSTALL_LIST=$args{dl}\n";
    print temp_FH "SHOW_DEINSTALL_CONFIRMATION=true\n";
    print temp_FH "SHOW_DEINSTALL_PROGRESS=true\n";

    close(temp_FH);
    unlink "$filename" if -e "$filename";
    copy("$tempfile", "$filename");
    unlink "$tempfile" if -e "$tempfile";
  }
  else {
    print "Cannot open temp cfg file $tempfile \n";
  }
}

processArgs();
my @paramList = %param;
my %respFileParam = (
  sh    => 'C:\Siebel_Install_Image\15.9.0.0.patchset9\Windows\Server\Siebel_Enterprise_Server\Disk1',
  fl    => 'C:\Siebel_Install_Image\15.9.0.0.patchset9\Windows\Server\Siebel_Enterprise_Server\Disk1\stage\products.xml',
  tl    => 'oracle.siebel.ses',
  sv    => '15.9.0.0.0',
  oh    => 'c:\Siebel\15.0.0.0.0\ses',
  on    => 'SES_HOME',
  gi    => 'true',
  si    => 'true',
  sl    => '[English]',
  dl    => '{"oracle.siebel.ses","15.9.0.0.0"}',
  pn    => 'test.rsp',
  @paramList
);
# TODO this is for test, we should pass %param directly
genRespFile(%respFileParam);
