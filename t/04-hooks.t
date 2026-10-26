use strict;
use warnings;
use Test::More;

use lib 'lib', 't/lib';
use CodecSwitchTest qw(reset_env fake_client fake_track fake_song set_formats);
use Slim::Utils::Prefs;
use Slim::Utils::PluginManager;
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

$prefs->client($client)->set('mapping', { flc => 'skip' });
Plugins::CodecSwitch::Config->invalidate($client);
is(call_hook(undef), undef, 'skip does not override the format');

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

# SACDPlayer chaining: SACD decodes DST/DFF to FLAC, then CodecSwitch encodes
# that FLAC stream into the player's target format.
Slim::Utils::PluginManager->set_enabled('Plugins::SACDPlayer::Plugin', 1);
set_formats(qw(flc mp3 wav aac dff dsf));
$prefs->set('sox', '/bin/true');
$prefs->set('flac', '/bin/true');
$prefs->set('lame', '/bin/true');
$prefs->set('opusenc', '/bin/true');
Plugins::CodecSwitch::Toolchain->reset_cache;
Plugins::CodecSwitch::Hooks->install;

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

$prefs->client($client)->set('mapping', { dff => 'flc' });
Plugins::CodecSwitch::Config->invalidate($client);
my $flac_chain = run_hook('dff');
is($flac_chain->{streamformat}, 'flc', 'target FLAC needs no second stage');
is($flac_chain->{command}, 'SACD-CMD $FILE$', 'target FLAC returns the SACD command unchanged');

Slim::Utils::PluginManager->set_enabled('Plugins::SACDPlayer::Plugin', 0);
$prefs->client($client)->set('mapping', { dff => 'mp3' });
Plugins::CodecSwitch::Config->invalidate($client);
my $direct = run_hook(undef);
is($direct->{streamformat}, 'mp3', 'without SACD, CodecSwitch uses its own DFF profile');
like($direct->{command}, qr/^STUB /, 'without SACD, the original transcoder is used');

$Slim::Player::TranscodingHelper::MOCK = undef;
Plugins::CodecSwitch::Hooks->uninstall;

done_testing;
