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
my %respFileParam;
my $sep = '/';

sub processInputArgs {
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

sub prepRespFileParams {
  my $stageLoc = $param{sl};
  my $platform = $param{pl};

  my $prodXML = $stageLoc.$sep.'products.txt';
  open(my $fh, "<", $prodXML)
    or die "Error: no products.txt found in Patchset.";

  my $patchName = '';

  while (my $line = <$fh>) {
    if ((substr $line, 0, 1) eq '[') {
      print $patchName."\n";
      $patchName = substr $line, 1, -3;
      last;
    }
  }
  
  if ($patchName eq '') {
    die "Error: patch invalid, cannot find patch name in products.txt";
  }

  my $disk1Path = $stageLoc.$sep.$patchName.$sep.$platform.$sep.'Server'.$sep.'Siebel_Enterprise_Server'.$sep.'Disk1'.$sep;
  
  $respFileParam{sh} = $disk1Path;
  $respFileParam{fl} = $disk1Path.'stage'.$sep.'products.xml';
  $respFileParam{tl} = 'oracle.siebel.ses';
  my $index = index($patchName, 'patchset');
  $respFileParam{sv} = substr($patchName, 0, $index).'0';
  $respFileParam{oh} = $param{oh};
  $respFileParam{on} = $param{on};
  $respFileParam{gi} = 'true';
  $respFileParam{si} = 'true';
  $respFileParam{sl} = '[English]'; #TODO;
  $respFileParam{dl} = '{"oracle.siebel.ses","'.$respFileParam{sv}.'"}';
  $respFileParam{pn} = $param{pn};
}

sub genRespFile {
  my %args = %respFileParam;

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

sub runInstaller {
  my $commandParam = '-invPtrLoc ~/oraInst.loc -silent -responseFile ~/test.rsp -waitforcompletion';
  my $command = $respFileParam{sh}.'install'.$sep.'runInstaller.sh'.' '.$commandParam;
  print $command."\n";
}

processInputArgs();
my @tmpList = %param;
%param = (
  sl    => '/tmp/p23144283_600000000019690_226_0/sblqa2/23144283',
  pl    => 'Linux',
  oh    => 'c:\Siebel\15.0.0.0.0\ses',
  on    => 'SES_HOME',
  pn    => 'test.rsp',
  @tmpList
);

prepRespFileParams();
genRespFile();
runInstaller();
