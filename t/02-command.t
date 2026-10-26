use strict;
use warnings;
use Test::More;

use lib 'lib', 't/lib';
use Plugins::CodecSwitch::Config;
use Plugins::CodecSwitch::CommandBuilder;

my $tools = {
    ffmpeg  => '/usr/bin/ffmpeg',
    flac    => '/usr/bin/flac',
    lame    => '/usr/bin/lame',
    sox     => '/usr/bin/sox',
    opusenc => '/usr/bin/opusenc',
};

for my $key (qw(flc wav aif mp3 aac ogg ops alc)) {
    my $target = Plugins::CodecSwitch::Config->target_by_key($key);
    my $plan = Plugins::CodecSwitch::CommandBuilder->ffmpeg_plan({
        source     => 'mp3',
        target     => $target,
        lms_format => $target->{formats}[0],
        tools      => $tools,
        resampler  => 'soxr',
    });
    ok($plan, "$key ffmpeg plan");
    like($plan->{command}, qr/-c:a \Q$target->{ffmpeg_encoder}\E/, "$key encoder");
    like($plan->{command}, qr/-f \Q$target->{ffmpeg_container}\E -$/, "$key container");
    like($plan->{command}, qr/-i \$FILE\$/, "$key input placeholder");
    unlike($plan->{command}, qr/"\$FILE\$"/, "$key does not double-quote FILE");
    like($plan->{capabilities}{D}, qr/soxr/, "$key has resample capability");
    is($plan->{capabilities}{F}, 'noArgs', "$key local capability");
    ok(!exists $plan->{capabilities}{R}, "$key local has no R capability");
}

my $flac = Plugins::CodecSwitch::Config->target_by_key('flc');
my $remote = Plugins::CodecSwitch::CommandBuilder->ffmpeg_plan({
    source     => 'flc',
    target     => $flac,
    lms_format => 'flc',
    tools      => $tools,
    remote     => 1,
});
like($remote->{command}, qr/-i \$URL\$/, 'remote uses URL placeholder');
is($remote->{capabilities}{R}, 'noArgs', 'remote has R capability');
ok(!exists $remote->{capabilities}{F}, 'remote has no F capability');

my $spaced = Plugins::CodecSwitch::CommandBuilder->ffmpeg_plan({
    source     => 'flc',
    target     => $flac,
    lms_format => 'flc',
    tools      => { %$tools, ffmpeg => '/opt/My Tools/ffmpeg' },
});
like($spaced->{command}, qr/^"\/opt\/My Tools\/ffmpeg"/, 'tool path with spaces is quoted');

my $native_targets = {
    flc => [qr/\| "\/usr\/bin\/flac" -cs --totally-silent -/, qr/-t wav - \$RESAMPLE\$/],
    wav => [qr/^"\/usr\/bin\/sox" -q \$FILE\$ -t wav - \$RESAMPLE\$/, qr/-t wav/],
    aif => [qr/-t raw -e signed -b 16 -B - \$RESAMPLE\$/, qr/\-B/],
    mp3 => [qr/\| "\/usr\/bin\/lame" --silent --abr 192 \$BITRATE\$ - -/, qr/-t wav/],
    ogg => [qr/-t ogg -C 5 - \$RESAMPLE\$/, qr/ogg/],
    ops => [qr/\| "\/usr\/bin\/opusenc" --quiet --bitrate 128 \$BITRATE\$ - -/, qr/-t wav/],
};

for my $key (sort keys %$native_targets) {
    my $target = Plugins::CodecSwitch::Config->target_by_key($key);
    my $plan = Plugins::CodecSwitch::CommandBuilder->native_plan({
        source     => 'mp3',
        target     => $target,
        lms_format => $target->{formats}[0],
        tools      => $tools,
    });
    ok($plan, "$key native plan");
    for my $re (@{ $native_targets->{$key} }) {
        like($plan->{command}, $re, "$key native command shape");
    }
    is($plan->{capabilities}{F}, 'noArgs', "$key native F capability");
    like($plan->{capabilities}{D}, qr/rate -v %d/, "$key native resample capability");
    ok(!exists $plan->{capabilities}{T}, "$key native has no seek capability");
}

my $native_flac = Plugins::CodecSwitch::Config->target_by_key('flc');
is(
    Plugins::CodecSwitch::CommandBuilder->native_plan({
        source => 'aac', target => $native_flac, lms_format => 'flc', tools => $tools,
    }),
    undef,
    'native plan rejects unsupported source',
);
is(
    Plugins::CodecSwitch::CommandBuilder->native_plan({
        source => 'flc', target => $native_flac, lms_format => 'flc',
        tools => { sox => '/usr/bin/sox' },
    }),
    undef,
    'native FLAC plan requires flac encoder',
);
is(
    Plugins::CodecSwitch::CommandBuilder->native_plan({
        source => 'mp3', target => $native_flac, lms_format => 'flc',
        tools => $tools, remote => 1,
    }),
    undef,
    'native plan rejects remote input',
);

my $direct = Plugins::CodecSwitch::CommandBuilder->direct_plan({
    source => 'flc', target => 'flc', lms_format => 'flc',
});
is($direct->{command}, '-', 'direct command');
ok($direct->{capabilities}{I} && $direct->{capabilities}{F} && $direct->{capabilities}{R},
    'direct capabilities');


my $pipe_targets = {
    flc => 'flac',
    wav => 'pcm_s16le',
    aif => 'pcm_s16be',
    mp3 => 'libmp3lame',
    aac => 'aac',
    ogg => 'libvorbis',
    ops => 'libopus',
    alc => 'alac',
};

for my $key (sort keys %$pipe_targets) {
    my $target = Plugins::CodecSwitch::Config->target_by_key($key);
    my $plan = Plugins::CodecSwitch::CommandBuilder->ffmpeg_pipe_plan({
        input_format => 'flc',
        target       => $target,
        lms_format   => $target->{formats}[0],
        tools        => $tools,
    });
    ok($plan, "$key ffmpeg pipe plan");
    like($plan->{command}, qr/-f flac -i -/, "$key pipe reads FLAC from stdin");
    like($plan->{command}, qr/-c:a \Q$pipe_targets->{$key}\E/, "$key pipe encoder");
    unlike($plan->{command}, qr/\$FILE\$/, "$key pipe has no FILE placeholder");
    unlike($plan->{command}, qr/\$START\$|\$END\$|\$RESAMPLE\$/, "$key pipe has no base-stage placeholders");
    like($plan->{command}, qr/^"\/usr\/bin\/ffmpeg"/, "$key pipe is direct ffmpeg");
}

my $pipe_native = {
    flc => qr/^"\/usr\/bin\/sox" -q -t flac - -t wav - \| .*flac/,
    wav => qr/^"\/usr\/bin\/sox" -q -t flac - -t wav -/,
    aif => qr/-t raw -e signed -b 16 -B -/,
    mp3 => qr/\| .*lame.* --silent --abr 192 - -/,
    ogg => qr/-t ogg -C 5 -/,
    ops => qr/\| .*opusenc.* --quiet --bitrate 128 - -/,
};

for my $key (sort keys %$pipe_native) {
    my $target = Plugins::CodecSwitch::Config->target_by_key($key);
    my $plan = Plugins::CodecSwitch::CommandBuilder->native_pipe_plan({
        input_format => 'flc',
        target       => $target,
        lms_format   => $target->{formats}[0],
        tools        => $tools,
    });
    ok($plan, "$key native pipe plan");
    like($plan->{command}, $pipe_native->{$key}, "$key native pipe shape");
    unlike($plan->{command}, qr/\$FILE\$|\$START\$|\$END\$|\$RESAMPLE\$/, "$key native pipe has no base-stage placeholders");
}

my $dff_pipe = Plugins::CodecSwitch::CommandBuilder->ffmpeg_pipe_plan({
    input_format => 'dff',
    target       => Plugins::CodecSwitch::Config->target_by_key('flc'),
    lms_format   => 'flc',
    tools        => $tools,
});
like($dff_pipe->{command}, qr/-f iff -i -/, 'DFF pipe uses iff demuxer');
is(
    Plugins::CodecSwitch::CommandBuilder->native_pipe_plan({
        input_format => 'dff',
        target       => Plugins::CodecSwitch::Config->target_by_key('flc'),
        lms_format   => 'flc',
        tools        => $tools,
    }),
    undef,
    'native pipe rejects DFF',
);


# Bitrate capability: only lossy targets expose B and a $BITRATE$ placeholder.
for my $key (qw(mp3 aac ogg ops)) {
    my $target = Plugins::CodecSwitch::Config->target_by_key($key);
    my $plan = Plugins::CodecSwitch::CommandBuilder->ffmpeg_plan({
        source => 'flc', target => $target, lms_format => $target->{formats}[0], tools => $tools,
    });
    is($plan->{capabilities}{B}, 'BITRATE=-b:a %Bk', "$key ffmpeg has B capability");
    like($plan->{command}, qr/\$BITRATE\$/, "$key ffmpeg uses BITRATE");
}
for my $key (qw(flc wav aif alc)) {
    my $target = Plugins::CodecSwitch::Config->target_by_key($key);
    my $plan = Plugins::CodecSwitch::CommandBuilder->ffmpeg_plan({
        source => 'flc', target => $target, lms_format => $target->{formats}[0], tools => $tools,
    });
    ok(!exists $plan->{capabilities}{B}, "$key has no B capability");
    unlike($plan->{command}, qr/\$BITRATE\$/, "$key has no BITRATE placeholder");
}
my $pipe_aac = Plugins::CodecSwitch::CommandBuilder->ffmpeg_pipe_plan({
    input_format => 'pcm', input_sample_fmt => 's24le', input_rate => 176400,
    input_channels => 2, bitrate => 128,
    target => Plugins::CodecSwitch::Config->target_by_key('aac'), lms_format => 'aac', tools => $tools,
});
like($pipe_aac->{command}, qr/-f s24le -ar 176400 -ac 2 -i -/, 'PCM pipe carries sample format/rate/channels');
like($pipe_aac->{command}, qr/-b:a 128k/, 'post encoder uses numeric bitrate');
unlike($pipe_aac->{command}, qr/\$BITRATE\$/, 'post encoder does not leave BITRATE unresolved');

done_testing;
