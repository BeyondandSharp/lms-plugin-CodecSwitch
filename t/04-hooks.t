use strict;
use warnings;
use Test::More;

use lib 'lib', 't/lib';
use CodecSwitchTest qw(reset_env fake_client fake_track fake_song set_formats);
use Slim::Utils::Prefs;
use Slim::Player::TranscodingHelper;
use Plugins::CodecSwitch::Config;
use Plugins::CodecSwitch::Hooks;
use Plugins::CodecSwitch::Toolchain;

my $prefs = preferences('plugin.codecswitch');
reset_env();
set_formats(qw(flc mp3 wav aac));

my $ffmpeg = -x '/usr/bin/ffmpeg' ? '/usr/bin/ffmpeg'
           : -x '/usr/local/bin/ffmpeg' ? '/usr/local/bin/ffmpeg' : undef;
plan skip_all => 'ffmpeg not found' unless $ffmpeg;

$prefs->set('ffmpeg', $ffmpeg);
Plugins::CodecSwitch::Toolchain->reset_cache;
Plugins::CodecSwitch::Hooks->uninstall;
Plugins::CodecSwitch::Hooks->install;

my $client = fake_client();
my $flac   = fake_track(content_type => 'flc', url => 'file:///music/a.flac');
my $song   = fake_song($flac, $client);

sub call_hook {
    my ($formatOverride) = @_;
    Slim::Player::TranscodingHelper::getConvertCommand2(
        $song, 'flc', [ 'I', 'F' ], [], [], $formatOverride, undef,
    );
    return $Slim::Player::TranscodingHelper::CALLS[-1][5];
}

$prefs->client($client)->set('mapping', { flc => 'mp3' });
Plugins::CodecSwitch::Config->invalidate($client);
is(call_hook(undef), 'mp3', 'target mapping forces the target LMS format');

$prefs->client($client)->set('mapping', { flc => 'direct' });
Plugins::CodecSwitch::Config->invalidate($client);
is(call_hook(undef), undef, 'direct does not override the format');

$prefs->client($client)->set('mapping', { flc => 'direct' });
Plugins::CodecSwitch::Config->invalidate($client);
is(call_hook(undef), undef, 'direct does not override the format');

$prefs->client($client)->set('mapping', { flc => 'mp3' });
Plugins::CodecSwitch::Config->invalidate($client);
is(call_hook('wav'), 'wav', 'existing formatOverride is respected');

$prefs->client($client)->set('mapping', { flc => 'aac' });
Plugins::CodecSwitch::Config->invalidate($client);

# Remove AAC from the player to force an unavailable target.
set_formats(qw(flc mp3 wav));
is(call_hook(undef), undef, 'unavailable target leaves the format alone');

set_formats(qw(flc mp3 wav aac));
my $remote = fake_track(content_type => 'flc', url => 'http://example.test/a.flac');
$song = fake_song($remote, $client);
is(call_hook(undef), 'aac', 'remote target uses an ffmpeg plan');

my $unknown = fake_track(content_type => 'wma', url => 'file:///music/a.wma');
$song = fake_song($unknown, $client);
$prefs->client($client)->set('mapping', { wma => 'mp3' });
Plugins::CodecSwitch::Config->invalidate($client);
is(call_hook(undef), 'mp3', 'unlisted source can still be converted by ffmpeg');

Plugins::CodecSwitch::Hooks->uninstall;
ok(1, 'hook uninstalls without error');

# DSD provider chaining: the provider decodes DST/DFF to FLAC, then
# CodecSwitch encodes that FLAC stream into the player's target format.
set_formats(qw(flc mp3 wav aac dff dsf));
$prefs->set('sox', '/bin/true');
$prefs->set('flac', '/bin/true');
$prefs->set('lame', '/bin/true');
$prefs->set('opusenc', '/bin/true');
Plugins::CodecSwitch::Toolchain->reset_cache;
Plugins::CodecSwitch::Hooks->install;
require Plugins::CodecSwitch::Profiles;
Plugins::CodecSwitch::Profiles->remove($client);
$Slim::Player::TranscodingHelper::commandTable{"dff-flc-*-" . $client->id} = 'SACD-FAKE';

$Slim::Player::TranscodingHelper::MOCK = sub {
    my @a = @_;
    return undef unless defined $a[5] && length $a[5];
    if ($a[5] eq 'flc') {
        return {
            command          => 'SACD-CMD $FILE$',
            streamformat     => 'flc',
            profile          => 'dff-flc-*-test',
            capabilities     => { F => 'noArgs', T => 'START=-ss %s' },
            usedCapabilities => ['T'],
            streamMode       => 'F',
            samplerateLimit  => 44100,
            rateLimit        => 320,
        };
    }
    return {
        command      => 'STUB ' . $a[5],
        streamformat => $a[5],
        profile      => 'stub',
        capabilities => { F => 'noArgs' },
    };
};

sub run_hook {
    my ($formatOverride) = @_;
    return Slim::Player::TranscodingHelper::getConvertCommand2(
        $song, 'dff', [ 'I', 'F' ], [], [], $formatOverride, undef,
    );
}

my $dff = fake_track(content_type => 'dff', url => 'file:///music/a.dff');
$song = fake_song($dff, $client);

$prefs->client($client)->set('mapping', { dff => 'mp3' });
Plugins::CodecSwitch::Config->invalidate($client);
my $chained = run_hook('dff');
ok($chained, 'SACD chain returns a transcoder');
is($chained->{streamformat}, 'mp3', 'chained output format is the player target');
like($chained->{command}, qr/^\(SACD-CMD \$FILE\$\) \| /, 'SACD command is piped into the encoder');
like($chained->{command}, qr/\/bin\/true/, 'post encoder is present in the chained command');
is($chained->{post_backend}, 'native', 'post backend is reported');
is($chained->{profile}, 'dff-flc-*-test', 'SACD base profile is preserved for sample-rate handling');
is($chained->{samplerateLimit}, 44100, 'samplerateLimit is preserved for tokenization');
is($chained->{rateLimit}, 320, 'rateLimit is preserved for tokenization');

$prefs->client($client)->set('maxBitrate', 128);
my $bchained = Slim::Player::TranscodingHelper::getConvertCommand2(
    $song, 'dff', [ 'I', 'F' ], [], [ 'B' ], 'dff', undef,
);
ok($bchained, 'SACD bitrate chain returns a transcoder');
like($bchained->{command}, qr/(?:-b:a 128k|--abr 128)/, 'SACD bitrate chain uses 128k');
is($bchained->{post_format}, 'mp3', 'SACD bitrate chain reports final format');
ok($bchained->{codecswitch_chain}, 'SACD bitrate chain is marked');
delete $Slim::Utils::Prefs::CLIENT_PREFS{'plugin.codecswitch'}{$client->id}{maxBitrate};

$prefs->client($client)->set('mapping', { dff => 'flc' });
Plugins::CodecSwitch::Config->invalidate($client);
my $flac_chain = run_hook('dff');
is($flac_chain->{streamformat}, 'flc', 'target FLAC needs no second stage');
is($flac_chain->{command}, 'SACD-CMD $FILE$', 'target FLAC returns the SACD command unchanged');

# Simulate a SACD provider that can decode directly to raw PCM.
{
    package Plugins::SACDPlayer::Transcoder;
    sub decode_plan {
        my ($class, $client, $format, $opts) = @_;
        return undef unless $format eq 'pcm';
        return {
            command      => 'SACD-PCM-CMD $FILE$',
            capabilities => { F => 'noArgs' },
            format       => 'pcm',
        };
    }
}
$INC{'Plugins/SACDPlayer/Transcoder.pm'} = __FILE__;
$prefs->client($client)->set('mapping', { dff => 'mp3' });
Plugins::CodecSwitch::Config->invalidate($client);
my $pcm_chain = run_hook('dff');
ok($pcm_chain, 'SACD PCM chain returns a transcoder');
like($pcm_chain->{command}, qr/^\(SACD-PCM-CMD \$FILE\$\) \| /, 'SACD PCM command is piped');
like($pcm_chain->{command}, qr/-f s16le -ar 44100 -ac 2 -i -/, 'PCM pipe declares format');
is($pcm_chain->{streamformat}, 'mp3', 'PCM chain final format');
is($pcm_chain->{post_format}, 'mp3', 'PCM chain marks post format');
is($pcm_chain->{samplerateLimit}, 44100, 'PCM chain preserves samplerateLimit');
delete $INC{'Plugins/SACDPlayer/Transcoder.pm'};

delete $Slim::Player::TranscodingHelper::commandTable{"dff-flc-*-" . $client->id};
$prefs->client($client)->set('mapping', { dff => 'mp3' });
Plugins::CodecSwitch::Config->invalidate($client);
my $direct = run_hook(undef);
is($direct->{streamformat}, 'mp3', 'without a DSD provider, CodecSwitch uses its own DFF profile');
like($direct->{command}, qr/^STUB /, 'without a DSD provider, the original transcoder is used');

$Slim::Player::TranscodingHelper::MOCK = undef;
Plugins::CodecSwitch::Hooks->uninstall;

done_testing;
