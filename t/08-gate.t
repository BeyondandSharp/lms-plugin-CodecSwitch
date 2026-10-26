use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec::Functions qw(catfile);
use Time::HiRes qw(time);

my $gate = 'Bin/codecswitch-gate';
plan skip_all => 'gate script missing' unless -x $gate;
plan skip_all => 'flock not available' unless grep { -x "$_/flock" } split /:/, $ENV{PATH} || '';
plan skip_all => 'fork not available' if $^O eq 'MSWin32';

my $dir = tempdir(CLEANUP => 1);
my $log = catfile($dir, 'events.log');
my $locks = catfile($dir, 'locks');

my $start = time();
my @pids;
for my $i (1 .. 4) {
    my $pid = fork();
    if (!defined $pid) {
        die "fork failed: $!";
    }
    if ($pid == 0) {
        exec($gate, 2, $locks, 'sh', '-c',
            "echo S >> '$log'; sleep 0.15; echo E >> '$log'");
        exit 127;
    }
    push @pids, $pid;
}
for my $pid (@pids) {
    waitpid($pid, 0);
    is($?, 0, 'gated child exited cleanly');
}
my $elapsed = time() - $start;

open my $fh, '<', $log or die "$log: $!";
my @lines = <$fh>;
close $fh;
chomp @lines;

my ($active, $max) = (0, 0);
for my $line (@lines) {
    if ($line eq 'S') { $active++; $max = $active if $active > $max; }
    elsif ($line eq 'E') { $active--; }
}
is(scalar(grep { $_ eq 'S' } @lines), 4, 'all four jobs started');
is(scalar(grep { $_ eq 'E' } @lines), 4, 'all four jobs finished');
cmp_ok($max, '<=', 2, 'at most two jobs run at once');
cmp_ok($max, '>=', 2, 'two jobs do run at once');
cmp_ok($elapsed, '>=', 0.25, 'four jobs with two slots take at least two rounds');

my $failed = system($gate, 1, $locks, 'false');
isnt($failed, 0, 'failing command is propagated');
my $after = system($gate, 1, $locks, 'true');
is($after, 0, 'slot is released after a failure');

done_testing;
