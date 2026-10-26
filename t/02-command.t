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

my $gate = { bin => '/opt/plugin/Bin/codecswitch-gate', max => 2, dir => '/tmp/cs locks' };
my $gated = Plugins::CodecSwitch::CommandBuilder->ffmpeg_plan({
    source     => 'flc',
    target     => $flac,
    lms_format => 'flc',
    tools      => $tools,
    gate       => $gate,
});
like($gated->{command}, qr/^"\/opt\/plugin\/Bin\/codecswitch-gate" 2 "\/tmp\/cs locks" "/,
    'ffmpeg is gated');

my $native_targets = {
    flc => [qr/\| "\/usr\/bin\/flac" -cs --totally-silent -/, qr/-t wav - \$RESAMPLE\$/],
    wav => [qr/^"\/usr\/bin\/sox" -q \$FILE\$ -t wav - \$RESAMPLE\$/, qr/-t wav/],
    aif => [qr/-t raw -e signed -b 16 -B - \$RESAMPLE\$/, qr/\-B/],
    mp3 => [qr/\| "\/usr\/bin\/lame" --silent -q 2 - -/, qr/-t wav/],
    ogg => [qr/-t ogg -C 5 - \$RESAMPLE\$/, qr/ogg/],
    ops => [qr/\| "\/usr\/bin\/opusenc" --quiet --bitrate 128 - -/, qr/-t wav/],
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

my $native_gated = Plugins::CodecSwitch::CommandBuilder->native_plan({
    source => 'mp3', target => $native_flac, lms_format => 'flc',
    tools => $tools, gate => $gate,
});
like($native_gated->{command}, qr/\| "\/opt\/plugin\/Bin\/codecswitch-gate" 2 "\/tmp\/cs locks" "\/usr\/bin\/flac"/,
    'native pipeline gates the encoder');

my $direct = Plugins::CodecSwitch::CommandBuilder->direct_plan({
    source => 'flc', target => 'flc', lms_format => 'flc',
});
is($direct->{command}, '-', 'direct command');
ok($direct->{capabilities}{I} && $direct->{capabilities}{F} && $direct->{capabilities}{R},
    'direct capabilities');

done_testing;
