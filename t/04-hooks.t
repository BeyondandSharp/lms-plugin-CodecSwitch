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

done_testing;
