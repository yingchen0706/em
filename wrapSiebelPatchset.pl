#!/usr/bin/perl -w
# $version$
#
# Copyright (c) 2005, 2016, Oracle and/or its affiliates. All rights reserved.
#
#  NAME
#     wrapSiebelPatchset.pl
#
#  DESCRIPTION
#     This script is used to wrap the Siebel PatchSet zips from MOS to OPatch format.
#

use strict;
use File::Copy;
use File::Path qw(mkpath rmtree);
use File::Spec;

my %param;
my $targetLoc = "";  # where final zip and xml should be
my $zipLoc = "";     # where zip from MOS should be
my $patchLoc = "";   # where the created image should be
my $patchId = "";
my $platform = "";
my $imgVersion = ""; # patchset image version
my $metaFile = "";   # original metadata file name

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

&readParamFromIni("wrapSiebelPatchset.ini");
&process();

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

sub isWin {
  return $^O =~ m/^(Windows|MSWin|msmy)/i;
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
    rmtree($targetLoc);
  }
  mkpath($targetLoc);

  my $command = "unzip -q \"".File::Spec->catfile($zipLoc, "*.zip")."\" -d $targetLoc\n";
  runCommand($command, "Error: Failed at unzip Patchset zip files");
}

sub getImageVersion {
  opendir(my $dh, $targetLoc);
  my @list = readdir $dh;
  closedir $dh;

  foreach (@list) {
    if ($_ =~ /SBA_.*\.jar/) {
      my @words = split /_/, $_, 3;
      if (defined $words[1]) {
        $imgVersion = $words[1];
        last;
      }
    }
  }
}

sub getPatchInfo {
  # get metdata xml file name
  opendir(my $dh, $zipLoc);
  my @list = readdir $dh;
  closedir $dh;

  foreach (@list) {
    if ($_ =~ /.*\.xml/) {
      $metaFile = $_;
      last;
    }
  }

  if ($metaFile eq "") {
    die "Error: Could not find metadata xml file in $zipLoc";
  }

  # get bug number from metadata file
  $metaFile = File::Spec->catfile($zipLoc, $metaFile);
  open my $metaFH, $metaFile or die "Error: Could not open metadata xml file: $metaFile";
  my $start = 0;
  my $end = 0;
  my $line = "";
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

}

sub createResponseFile {
  $patchLoc = File::Spec->catdir($targetLoc, $patchId);
  
  my $respFile = File::Spec->catfile($targetLoc, "image.rsp");
  
  open my $fh, '>', $respFile or die "Error: Could not create response file for image creator!";
  print $fh "imageVersion=\"$imgVersion\"\n";
  print $fh "imageDirectory=\"$patchLoc\"\n";
  print $fh "platformList={$platform}\n";
  print $fh "productList={Siebel_Enterprise_Server}\n";
  print $fh "languageList={$param{language}}\n";
  close $fh;

  print "Created response file for Siebel Image Creator.\n";
}

sub invokeImageCreator {
  rmtree($patchLoc) if -e $patchLoc;

  my $inputHelper = File::Spec->catfile($targetLoc, "enter");
  open my $fh, ">", $inputHelper;
  print $fh "\n";
  close $fh;

  my $postFix = " -silent -responseFile image.rsp < $inputHelper > ".File::Spec->catfile($targetLoc, "log");
  my $command = "snic.sh";
  if (isWin()) {
    $command = "snic.bat";
  }
  $command = File::Spec->catfile($targetLoc, $command).$postFix;

  runCommand($command, "Error: failed at create Patchset image");
}

sub postCreateProcess {
  # create needed files/directories
  my $configPath = File::Spec->catdir($patchLoc, "etc", "config");
  mkpath($configPath);
  my $action = File::Spec->catfile($configPath, "actions.xml");
  open my $tmp, ">", $action or die "Error: Could not create actions.xml in $action";
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

sub updateMetadataFile {
  my $metaFileNew = File::Spec->catfile($param{targetLoc}, "$patchId.xml");
  my $needCp = 1;
  my $isInFiles = 0;
  my $size = -s File::Spec->catfile($param{targetLoc}, $patchId.".zip");

  open my $fhdst, ">", $metaFileNew or die "Error: error when update metadata xml file";
  open my $fhsrc, "<", $metaFile or die "Error: error when update metadata xml file";

  while (my $line = <$fhsrc>) {
    if (index($line, "<files>") >= 0) {
      print $fhdst $line;
      $isInFiles = 1;
    } elsif (index($line, "</files>") >= 0) {
      print $fhdst $line;
      $isInFiles = 0;
    } elsif (!$isInFiles) {
      if (index($line, "<size>") >= 0) {
        $line =~ s/>.*</>$size</;
      }
      print $fhdst $line;
    } elsif ($isInFiles) {
      if ($needCp) {
        if (index($line, "<name>") >= 0) {
          my $tmp = ">$patchId.zip<";
          $line =~ s/>.*</$tmp/;
        } elsif (index($line, "<size>") >= 0) {
          $line =~ s/>.*</>$size</;
        }
        print $fhdst $line;
        if (index($line, "</file>") >= 0) {
          $needCp = 0;
        }
      }
    }
  }

  close $fhdst;
  close $fhsrc;

}

sub createImage {
  print "\n[2] Create Patchset image\n";

  getImageVersion();
  if ($imgVersion eq "") {
    die "failed at getting imageVersion parameter of response file for image creator";
  }

  getPatchInfo();
  if ($patchId eq "") {
    die "Error: Could not find bug number from metadata xml file";
  }
  if ($platform eq "") {
    die "Error: Could not find platform info from metadata xml file";
  }

  createResponseFile();

  invokeImageCreator();

  postCreateProcess();

}

sub zipImage {
  print "\n[3] Zip the created image\n";
  if (-e File::Spec->catdir($patchLoc, "etc")) {
    my $finalLoc = File::Spec->catfile($param{targetLoc}, $patchId.".zip");
    unlink $finalLoc if (-e $finalLoc);
    my $sep = isWin() ? "&" : ";";
    runCommand("cd $targetLoc ".$sep." zip -rq $finalLoc $patchId", "Error: failed at compressing Patchset image");

    updateMetadataFile();

    print "\nSuccess!\n";
    print "Patch is in: $finalLoc\n";
    print "Metadata is in: ".File::Spec->catfile($param{targetLoc}, $patchId.".xml")."\n\n";

   } else {
    die "Error: Failed at creating Siebel image.";
  }
  rmtree($targetLoc);
}

sub process {

  # 1. unzip the patchset zips
  unzipPatchset();

  # 2. create image
  createImage();

  # 3. zip the image
  zipImage();

}


#my @tmpList = %param;
#%param = (
#  zipLoc      => '/tmp/zip',
#  targetLoc   => '/tmp/patch',
#  platform    => 'Linux',
#  language    => 'ENU',
#  @tmpList
#);


