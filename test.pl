use File::Spec;

my $path = '/home/yiyichen/perlScript/ab';
chmod 0777, $path;
my $path2 = File::Spec->catfile($path, '*');
chmod 0744, (glob $path2);
