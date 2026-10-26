use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec::Functions qw(catfile catdir);

use lib 'lib', 't/lib';
use Plugins::CodecSwitch::Config;
use Plugins::CodecSwitch::CommandBuilder;

my $ffmpeg = -x '/usr/bin/ffmpeg' ? '/usr/bin/ffmpeg'
           : -x '/usr/local/bin/ffmpeg' ? '/usr/local/bin/ffmpeg' : undef;
my $ffprobe = -x '/usr/bin/ffprobe' ? '/usr/bin/ffprobe'
            : -x '/usr/local/bin/ffprobe' ? '/usr/local/bin/ffprobe' : undef;
plan skip_all => 'ffmpeg/ffprobe not found' unless $ffmpeg && $ffprobe;

my $dir = tempdir(CLEANUP => 1);
my $src = catfile($dir, 'tone.wav');
my $rc = system($ffmpeg, '-hide_banner', '-loglevel', 'error', '-y',
    '-f', 'lavfi', '-i', 'sine=frequency=440:duration=1',
    '-ar', '44100', '-ac', '2', '-c:a', 'pcm_s16le', $src);
is($rc, 0, 'generated test WAV');
ok(-s $src, 'test WAV is non-empty');

sub shell_quote {
    my ($value) = @_;
    $value =~ s/'/'\\''/g;
    return "'$value'";
}

sub render {
    my ($command, $file) = @_;
    my $q = shell_quote($file);
    $command =~ s/\$FILE\$/$q/g;
    $command =~ s/\$URL\$/$q/g;
    $command =~ s/\$START\$//g;
    $command =~ s/\$END\$//g;
    $command =~ s/\$RESAMPLE\$//g;
    return $command;
}

my %expected = (
    flc => 'flac',
    wav => 'pcm_s16le',
    aif => 'raw-pcm-s16be',
    mp3 => 'mp3',
    aac => 'aac',
    ogg => 'vorbis',
    ops => 'opus',
    alc => 'alac',
);

for my $key (sort keys %expected) {
    my $target = Plugins::CodecSwitch::Config->target_by_key($key);
    my $plan = Plugins::CodecSwitch::CommandBuilder->ffmpeg_plan({
        source     => 'wav',
        target     => $target,
        lms_format => $target->{formats}[0],
        tools      => { ffmpeg => $ffmpeg },
        resampler  => 'swr',
    });
    ok($plan, "$key plan");

    my $out = catfile($dir, "out.$key");
    my $err = catfile($dir, "err.$key");
    my $command = render($plan->{command}, $src) . ' > ' . shell_quote($out) . ' 2> ' . shell_quote($err);
    my $ok = system($command);
    is($ok, 0, "$key pipeline exits 0");
    ok(-s $out, "$key output exists");

    if ($expected{$key} eq 'raw-pcm-s16be') {
        is(-s $out, 44100 * 2 * 2, "$key raw PCM byte count");
    }
    else {
        my $codec = qx{$ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=nw=1:nk=1 $out};
        $codec =~ s/\s+//g;
        is($codec, $expected{$key}, "$key output codec");
    }
}

my $spaceDir = catdir($dir, 'tool dir');
mkdir $spaceDir;
my $spacedFfmpeg = catfile($spaceDir, 'ffmpeg');
symlink($ffmpeg, $spacedFfmpeg) or die "symlink: $!";

my $target = Plugins::CodecSwitch::Config->target_by_key('flc');
my $plan = Plugins::CodecSwitch::CommandBuilder->ffmpeg_plan({
    source     => 'wav',
    target     => $target,
    lms_format => 'flc',
    tools      => { ffmpeg => $spacedFfmpeg },
    resampler  => 'swr',
});
my $spacedOut = catfile($dir, 'spaced.flac');
my $spacedErr = catfile($dir, 'spaced.err');
my $spacedCmd = render($plan->{command}, $src) . ' > ' . shell_quote($spacedOut) . ' 2> ' . shell_quote($spacedErr);
is(system($spacedCmd), 0, 'pipeline works with spaces in tool path');
ok(-s $spacedOut, 'spaced-path output exists');

done_testing;
