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
use File::Path qw(make_path remove_tree);
use File::Spec;
use 5.012;

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

sub runCommand {
  my ($command, $errMsg) = @_;
  print $command."\n";
  if (defined $errMsg) {
    system ($command)
      and die $errMsg;
  } else {
    system ($command);
  }
}

my $targetLoc = "";
my $zipLoc = ""; 
my $patchLoc = "";

sub unzipPatchset {
  if (defined $param{zipLoc}) {
    $zipLoc = $param{zipLoc};
  }
  if (defined $param{targetLoc}) {
    $targetLoc = $param{targetLoc};
  }

  # make sure targetLoc exist and empty
  if (-e $targetLoc) {
    print "Clean up unzip location: $targetLoc\n";
    remove_tree($targetLoc);
  }
  make_path($targetLoc);
  
  print "[1] Unzip files\n";
  my $command = "unzip '$zipLoc/*.zip' -d $targetLoc\n";
  runCommand $command, "Failed!";

}

sub trim {
  my $s = shift;
  $s =~ s/^\s+|\s+$//g;
  return $s;
}

sub createImage {
  # first create rsp file
  my $patchId = "";
  my $imgVersion = "";
  my $metaFile = "";

  # get image version
  opendir(my $dh, $targetLoc);
  while (readdir $dh) {
    if ($_ =~ /SBA_.*\.jar/) {
      my @words = split /_/, $_, 3;
      if (defined $words[1]) {
        $imgVersion = $words[1];
        last;
      }
    } 
  }
  closedir $dh;
  print "imageVersion: $imgVersion\n"; # TODO delete

  if ($imgVersion eq "") {
    die "failed at getting imageVersion parameter of response file for image creator";
  }

  # get metdata xml file name
  opendir($dh, $zipLoc);
  while (readdir $dh) {
    if ($_ =~ /.*\.xml/) {
      $metaFile = $_;
      last;
    }
  }
  closedir $dh;

  # get bug number from metadata file
  $metaFile = File::Spec->catfile($zipLoc, $metaFile);
  open (my $metaFH, $metaFile) or die "Error: Could not find metadata xml file: $metaFile";
  my $inBugTag = 0;
  my $start = 0;
  my $end = 0;
  my $line = "";
  foreach $line (<$metaFH>) {
    if (index ($line, "<bug>") >= 0) {
      $inBugTag = 1;
    } elsif (index ($line, "</bug>") >= 0) {
      die "Error: metadata xml file content invalid, cannot find bug number!";
    } elsif ($inBugTag && ($start = index ($line, ">")) >= 0) {
      ++$start;
      $end = index ($line, "</number>");
      $patchId = substr($line, $start, $end - $start);
      $patchId = trim($patchId);
      last;
    }
  }
  print "PatchId: $patchId\n"; # TODO delete
  if ($patchId eq "") {
    die "Error: metadata xml file content invalid, cannot find bug number!";
  }

  # create response file
  $patchLoc = File::Spec->catdir($targetLoc, $patchId);
  open (my $respFile, '>', File::Spec->catfile($targetLoc, "image.rsp")) or die "Error: Could not create response file for image creator!";
  print $respFile "imageVersion=\"$imgVersion\"\n";
  print $respFile "imageDirectory=\"$patchLoc\"\n";
  print $respFile "platformList={$param{platform}}\n";
  print $respFile "productList={Siebel_Enterprise_Server}\n";
  print $respFile "languageList={$param{language}}\n";
  close $respFile;
  print "Created response file for Siebel Image Creator.\n"; 

  # then invoke image creator
  if (-e $patchLoc) {
    remove_tree($patchLoc);
  }

  my $isWin = $^O =~ m/^(Windows|MSWin|msmy)/i;
  my $postFix = " -silent -responseFile image.rsp ";
  my $command = "snic.sh";
  if ($isWin) {
    $command = "snic.bat";
  }
  $command = File::Spec->catfile($targetLoc, $command).$postFix; 

  print "[2] Create Patchset image\n";
  runCommand $command, "Error: failed at create Patchset image";

  # create needed files/directories
  my $configPath = File::Spec->catdir($patchLoc, "etc", "config");
  make_path($configPath);
  my $action = File::Spec->catfile($configPath, "actions.xml");
  my $tmp;
  open($tmp, ">", $action) or die "Error: Could not create actions.xml in $action";
  close($tmp);
  my $inv = File::Spec->catfile($configPath, "inventory.xml");
  open($tmp, ">", $inv) or die "Error: Could not create inventory.xml in $inv";
  print $tmp "<oneoff_inventory>\n";
  print $tmp "<patch_id number=\"$patchId\" />\n";
  print $tmp "</oneoff_inventory>\n";
  close($tmp); 
  my $readme = File::Spec->catfile($patchLoc, "README.txt");
  open($tmp, ">", $readme) or die "Error: Could not create README.txt in $readme";
  close($tmp);
 
}

sub zipImage {
  print "[3] Zip the created image\n";
  if (-e File::Spec->catdir($patchLoc, "etc")) {
    runCommand "zip -r $patchLoc.zip $patchLoc", "Error: failed at compressing Patchset image";
  } else {
    die "Error: Failed at creating Siebel image.";
  }
  remove_tree($patchLoc);
}

sub process {

  # 1. unzip the patchset zips
  unzipPatchset();

  # 2. create image 
  createImage();

  # 3. zip the image
  zipImage();

  print "Success! Final patch location: $patchLoc.zip\n";
}

processInputArgs();

my @tmpList = %param;
%param = (
  zipLoc      => '/tmp/zip',
  targetLoc   => '/tmp/patch',
  platform    => 'Linux',
  language    => 'ENU',
  @tmpList
);

process();

