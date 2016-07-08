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
my %platform = (
  233   =>  'Windows',
  912   =>  'Windows',
  46    =>  'Linux',
  226   =>  'Linux',
  211   =>  'Linux',
  209   =>  'Linux',
  525   =>  'Linux',
  23    =>  'Solaris',
  173   =>  'Solaris',
  267   =>  'Solaris',
  319   =>  'AIX',
  212   =>  'AIX',
  197   =>  'HPUX',
  59    =>  'HPUX'
);

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

sub trim {
  my $s = shift;
  $s =~ s/^\s+|\s+$//g;
  return $s;
}

sub readParamFromIni {
  my $ini = shift;

  open my $fh, "<", $ini or die "Error: Could not find ini file";
  foreach my $line (<$fh>) {
    $line = trim($line);
    if ($line ne "" && 
      substr($line, 0, 1) ne "#") {
      my ($key, $val) = split /=/, $line, 2;
      $key = trim $key;
      $val = trim $val;
      if ($key ne "") {
        $param{$key} = $val;
      }
    } 
  }
  close $fh;
}

sub runCommand {
  my ($command, $errMsg) = @_;
  print "Running command: ".$command."\n";
  if (defined $errMsg) {
    system $command
      and die $errMsg;
  } else {
    system $command;
  }
}

my $targetLoc = "";
my $zipLoc = ""; 
my $patchLoc = "";
my $patchId = "";

sub unzipPatchset {
  print "\n[1] Unzip files\n";

  $zipLoc = $param{zipLoc};
  if (!$zipLoc) {
    die "Error: Missing zip location in ini file!";
  }

  $targetLoc = $param{targetLoc};
  if (!$targetLoc) {
    die "Error: Missing target locatioin in ini file!";
  }
  $targetLoc = File::Spec->catdir($targetLoc, time());

  # make sure targetLoc exist and empty
  if (-e $targetLoc) {
    print "Clean up unzip location: $targetLoc\n";
    remove_tree($targetLoc);
  }
  make_path($targetLoc);
  
  my $command = "unzip -q '$zipLoc/*.zip' -d $targetLoc\n";
  runCommand($command, "Error: Failed at unzip Patchset zip files");
}

sub createImage {
  print "\n[2] Create Patchset image\n";

  # first create rsp file
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

  if ($imgVersion eq "") {
    die "failed at getting imageVersion parameter of response file for image creator";
  }

  # get metdata xml file name
  opendir $dh, $zipLoc;
  while (readdir $dh) {
    if ($_ =~ /.*\.xml/) {
      $metaFile = $_;
      last;
    }
  }
  closedir $dh;

  # get bug number from metadata file
  $metaFile = File::Spec->catfile($zipLoc, $metaFile);
  open my $metaFH, $metaFile or die "Error: Could not find metadata xml file: $metaFile";
  my $start = 0;
  my $end = 0;
  my $line = "";
  my $platform = "";
  foreach $line (<$metaFH>) {
    if ( $patchId eq "" && ($start = index ($line, "<number>")) >= 0) {
      $start += 8;
      $end = index ($line, "</number>");
      $patchId = substr($line, $start, $end - $start);
      $patchId = trim($patchId);
    } elsif ($platform eq "" && ($start = index ($line, "<platform")) >= 0) {
      $start = index $line, "id";
      $start = index($line, "\"", $start) + 1;
      $end = index $line, "\"", $start;
      $platform = trim(substr($line, $start, $end -$start));
      $platform = $platform{$platform};
      last;
    }
  }
  close $metaFH;

  if ($patchId eq "") {
    die "Error: metadata xml file content invalid, cannot find bug number!";
  }

  # create response file
  $patchLoc = File::Spec->catdir($targetLoc, $patchId);
  open my $respFile, '>', File::Spec->catfile($targetLoc, "image.rsp") or die "Error: Could not create response file for image creator!";
  print $respFile "imageVersion=\"$imgVersion\"\n";
  print $respFile "imageDirectory=\"$patchLoc\"\n";
  print $respFile "platformList={$platform}\n";
  print $respFile "productList={Siebel_Enterprise_Server}\n";
  print $respFile "languageList={$param{language}}\n";
  close $respFile;
  print "Created response file for Siebel Image Creator.\n"; 

  # then invoke image creator
  remove_tree($patchLoc) if -e $patchLoc;

  my $inputHelper = File::Spec->catfile($targetLoc, "enter");
  open my $fh, ">", $inputHelper;
  print $fh "\n";
  close $fh;

  my $isWin = $^O =~ m/^(Windows|MSWin|msmy)/i;
  my $postFix = " -silent -responseFile image.rsp < $inputHelper > ".File::Spec->catfile($targetLoc, "log");
  my $command = "snic.sh";
  if ($isWin) {
    $command = "snic.bat";
  }
  $command = File::Spec->catfile($targetLoc, $command).$postFix; 

  runCommand($command, "Error: failed at create Patchset image");

  # create needed files/directories
  my $configPath = File::Spec->catdir($patchLoc, "etc", "config");
  make_path($configPath);
  my $action = File::Spec->catfile($configPath, "actions.xml");
  my $tmp;
  open $tmp, ">", $action or die "Error: Could not create actions.xml in $action";
  close $tmp;
  my $inv = File::Spec->catfile($configPath, "inventory.xml");
  open $tmp, ">", $inv or die "Error: Could not create inventory.xml in $inv";
  print $tmp "<oneoff_inventory>\n";
  print $tmp "<patch_id number=\"$patchId\" />\n";
  print $tmp "</oneoff_inventory>\n";
  close $tmp; 
  my $readme = File::Spec->catfile($patchLoc, "README.txt");
  open $tmp, ">", $readme or die "Error: Could not create README.txt in $readme";
  close $tmp;
 
}

sub zipImage {
  print "\n[3] Zip the created image\n";
  if (-e File::Spec->catdir($patchLoc, "etc")) {
    my $finalLoc = File::Spec->catfile($param{targetLoc}, $patchId.".zip");
    unlink $finalLoc if (-e $finalLoc);
    runCommand("zip -rq $finalLoc $patchLoc", "Error: failed at compressing Patchset image");
  } else {
    die "Error: Failed at creating Siebel image.";
  }
  remove_tree($targetLoc);
}

sub process {

  # 1. unzip the patchset zips
  unzipPatchset();

  # 2. create image 
  createImage();

  # 3. zip the image
  zipImage();

  print "\nSuccess! Final patch location: $patchLoc.zip\n\n";
}

#processInputArgs();

readParamFromIni("wrapSiebelPatchset.ini");
#my @tmpList = %param;
#%param = (
#  zipLoc      => '/tmp/zip',
#  targetLoc   => '/tmp/patch',
#  platform    => 'Linux',
#  language    => 'ENU',
#  @tmpList
#);

process();

