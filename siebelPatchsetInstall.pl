#!/usr/bin/perl -w
# $version$
#
# Copyright (c) 2005, 2016, Oracle and/or its affiliates. All rights reserved.
#
#  NAME
#     siebelGenRespFile.pl
#
#  DESCRIPTION
#     This script has following usage:
#     1. Install Siebel Patchset in silient mode. It will create response file
#        based on input argument and invoke OUI installer in silent mode.
#     2. Run install precheck, check whether the patchset already applied.
#     3. Run install postcheck, check whether the patchset has been applied successfully.
#
#  Input arguments
#     -patchLoc     specify the unzipped Patchset location.
#     -platform     specify target platform, supported: Linux, Windows, Solaris, HPUX, AIX
#                   No need for preCheck and postCheck.
#     -oh           specify Oracle home.
#     -ohn          specify Oracle home name. No need for preCheck and postCheck.
#     -preCheck     indicate this is precheck, no value needed.
#     -postCheck    indicate this is postCheck, no value needed.

use strict;
use File::Copy;
use File::Spec;

my %param;
my %respFileParam;

&processInputArgs();

my @tmpList = %param;
%param = (
  patchLoc    => '/tmp/p23144283_600000000019690_226_0/sblqa2/23144283',
  platform    => 'Linux',
  oh          => '/export/home/sblqa2/23048/ses',
  ohn         => 'BIT_SES_23048',
  preCheck    => 'true',
  #postCheck   => 'true',
  @tmpList
);

my $invPtrLoc = '~/oraInst.loc';

my %langMap = (
  ENU => "English",
  PSL => "PSL",
  PSJ => "Vitenamese",
  CHS => "Simplified Chinese",
  CSY => "Czech",
  DEU => "German",
  SVE => "Swedish",
  KOR => "Korean",
  ITA => "Italian",
  FIN => "Finnish",
  THA => "Thai",
  CHT => "Traditional Chinese",
  PLK => "Polish",
  PTB => "Brazilian Portuguese",
  ESN => "Spanish",
  ARA => "Arabic",
  RUS => "Russian",
  HEB => "Hebrew",
  DAN => "Danish",
  JPN => "Japanese",
  FRA => "French",
  PTG => "Portuguese",
  NLD => "Dutch",
  TRK => "Turkish"
);

&prepRespFileParams();

if (defined $param{preCheck}) {
  &versionCheck(1);
} elsif (defined $param{postCheck}) {
  &versionCheck();
} else {
  &genRespFile();
  &runInstaller();
}

sub trim {
  my $s = shift;
  $s =~ s/^\s+|\s+$//g;
  return $s;
}

sub isWin {
  return $^O =~ m/^(Windows|MSWin|msmy)/i;
}

sub processInputArgs {
  my $key = "";
  my $val = "";

  foreach my $arg (@ARGV) {
    if ((substr $arg, 0, 1) eq '-') {
      $key = substr $arg, 1;
      $param{$key} = "";
    } else {
      if ($param{$key} eq "") {
        $param{$key} = $arg;
      }
    }
  }

  print "Input arguments:\n";
  while (($key, $val) = each %param) {
    printf "%-10s= %s\n", $key, $val;
  }
}

# do version check by checking whether the patchset version
# already contained in opatch output
sub versionCheck {
  my $isPre = shift;
  my $targetVer = $respFileParam{sv};
  my $opatch = File::Spec->catfile(File::Spec->catdir($respFileParam{oh}, 'OPatch'), 'opatch');

  my $command = $opatch." lsinventory -oh $respFileParam{oh}";
  if (!&isWin()) {
    $command = $command." -invPtrLoc $invPtrLoc";
  }
  my $output = `$command`;

  print "Execute version check command: $command\n";
  print "Output: $output\n";

  my $exitCode = 0;
  if ($isPre) {
    if ((index $output, $targetVer) >= 0) {
      print "Error: Patchset already applied.\n";
      $exitCode = 1;
    } else {
      print "Version check succeeded.\n";
    }
  } else {
    if ((index $output, $targetVer) >= 0) {
      print "Version check succeeded.\n";
    } else {
      print  "Error: Version check failed.";
      $exitCode = 1;
    }
  }
  exit $exitCode;
}

sub prepRespFileParams {
  my $stageLoc = $param{patchLoc};
  my $platform = $param{platform};

  my $prodXML = File::Spec->catfile($stageLoc, 'products.txt');
  open my $fh, "<", $prodXML
    or die "Error: no products.txt found in Patchset.";

  my $patchName = '';

  while (my $line = <$fh>) {
    $line = trim($line);
    if ((substr $line, 0, 1) eq '[') {
      $patchName = substr $line, 1, -1;
      last;
    }
  }

  if ($patchName eq '') {
    die "Error: patch invalid, cannot find patch name in products.txt";
  }

  my $disk1Path = File::Spec->catdir($stageLoc, $patchName, $platform,
    'Server', 'Siebel_Enterprise_Server', 'Disk1');

  $respFileParam{sh} = $disk1Path;
  $respFileParam{fl} = File::Spec->catfile(File::Spec->catdir($disk1Path, 'stage'), 'products.xml');
  $respFileParam{tl} = 'oracle.siebel.ses';
  my $index = index($patchName, 'patchset');
  $respFileParam{sv} = substr($patchName, 0, $index).'0';
  $respFileParam{oh} = $param{oh};
  $respFileParam{on} = $param{ohn};
  $respFileParam{gi} = 'true';
  $respFileParam{si} = 'true';
  $respFileParam{sl} = '['.&getLanguage.']';
  $respFileParam{dl} = '{"oracle.siebel.ses","'.$respFileParam{sv}.'"}';
  $respFileParam{pn} = File::Spec->catfile($param{oh}, "ps.rsp");
}

sub getLanguage {
  my $objPath = File::Spec->catdir($respFileParam{oh}, "siebsrvr", "objects");
  my @langList = ();

  opendir(my $dh, $objPath);
  my @files = readdir $dh;
  closedir $dh;

  foreach my $key (@files) {
    if (-d File::Spec->catdir($objPath, $key)) {
      my $val = $langMap{uc($key)};
      if (defined($val)) {
        push @langList, $val;
      }
    }
  }

  die "Error: empty language list" if @langList == 0;

  join(',', @langList);
}

sub genRespFile {
  my %args = %respFileParam;

  if (!defined $args{pn}) {
    print "Error: Response file path invalid! \n";
    return;
  }

  my $filename = $args{pn};
  my $tempfile = $filename.".temp";

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
    unlink $filename if -e $filename;
    copy($tempfile, $filename);
    unlink $tempfile if -e $tempfile;
  }
  else {
    print "Cannot open temp response file $tempfile \n";
  }
}

sub createInputFile {
  my $name = time();
  my $inputHelper = File::Spec->catfile($respFileParam{oh}, $name);
  open my $fh, ">", $inputHelper;
  print $fh "\n\n\n\n\n";
  close $fh;
  $inputHelper;
}

sub runInstaller {
  my $fileName = createInputFile();

  my $commandParam = "-silent -responseFile $respFileParam{pn} -waitforcompletion < $fileName";
  if (!isWin()) {
    $commandParam = "-invPtrLoc $invPtrLoc ".$commandParam;
  }

  my $obj = "runInstaller.sh";
  if (isWin()) {
    $obj = "setup.bat";
  }
  my $command = File::Spec->catfile(File::Spec->catdir($respFileParam{sh}, 'install'), $obj).' '.$commandParam;
  print $command."\n";

  #system($command) and die "Error: Failed at running $command";
  #unlink $respFileParam{pn} if -e $respFileParam{pn};
  unlink $fileName if -e $fileName;
}


