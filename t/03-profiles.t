use strict;
use warnings;
use Test::More;

use lib 'lib', 't/lib';
use CodecSwitchTest qw(reset_env fake_client set_formats);
use Slim::Utils::Prefs;
use Slim::Utils::PluginManager;
use Slim::Player::TranscodingHelper;
use Slim::Player::Client;
use Plugins::CodecSwitch::Profiles;
use Plugins::CodecSwitch::Toolchain;

my $prefs = preferences('plugin.codecswitch');
reset_env();
set_formats(qw(flc mp3 wav aac ops));

my $ffmpeg = -x '/usr/bin/ffmpeg' ? '/usr/bin/ffmpeg'
           : -x '/usr/local/bin/ffmpeg' ? '/usr/local/bin/ffmpeg' : undef;
plan skip_all => 'ffmpeg not found' unless $ffmpeg;

$prefs->set('ffmpeg', $ffmpeg);
$prefs->set('sox', '/bin/true');
$prefs->set('flac', '/bin/true');
$prefs->set('lame', '/bin/true');
$prefs->set('opusenc', '/bin/true');
$prefs->set('max_jobs', 2);
Plugins::CodecSwitch::Toolchain->reset_cache;

my $client = fake_client();
my $id = $client->id;

is(Plugins::CodecSwitch::Profiles->setup($client) > 0, 1, 'profiles registered');

my $t = \%Slim::Player::TranscodingHelper::commandTable;
my $c = \%Slim::Player::TranscodingHelper::capabilities;

ok(exists $t->{"flc-flc-*-$id"}, 'direct FLAC profile exists');
is($t->{"flc-flc-*-$id"}, '-', 'direct FLAC profile is pass-through');
ok(exists $t->{"mp3-flc-*-$id"}, 'local MP3 -> FLAC profile exists');
ok(exists $t->{"mp3-flc-*-$id-1"}, 'remote MP3 -> FLAC profile exists');
like($t->{"mp3-flc-*-$id-1"}, qr/-i \$URL\$/, 'remote profile uses URL');
is($c->{"mp3-flc-*-$id"}{F}, 'noArgs', 'local profile has F');
is($c->{"mp3-flc-*-$id-1"}{R}, 'noArgs', 'remote profile has R');
ok(exists $t->{"mp3-aac-*-$id"}, 'MP3 -> AAC profile exists');
like($t->{"mp3-aac-*-$id"}, qr/libf?f?mpeg|ffmpeg/, 'AAC profile uses ffmpeg');
like($t->{"mp3-wav-*-$id"}, qr/\/bin\/true/, 'native WAV profile uses configured sox');
like($t->{"mp3-flc-*-$id"}, qr/codecswitch-gate/, 'profiles use the worker gate when max_jobs > 0');

$prefs->set('backend_flc', 'ffmpeg');
Plugins::CodecSwitch::Toolchain->reset_cache;
Plugins::CodecSwitch::Profiles->setup($client);
like($t->{"mp3-flc-*-$id"}, qr/ffmpeg/, 'forced FFmpeg backend is used');

$prefs->set('backend_flc', 'native');
Plugins::CodecSwitch::Toolchain->reset_cache;
Plugins::CodecSwitch::Profiles->setup($client);
like($t->{"mp3-flc-*-$id"}, qr/\/bin\/true.*\|/, 'forced native backend is used');
$prefs->set('backend_flc', 'auto');
Plugins::CodecSwitch::Toolchain->reset_cache;

my @before = sort keys %$t;
Plugins::CodecSwitch::Profiles->setup($client);
my @after = sort keys %$t;
is_deeply(\@after, \@before, 're-running setup does not leave stale profiles');

my $old_profile = "mp3-flc-*-$id";
$t->{$old_profile} = 'OLD-COMMAND';
$c->{$old_profile} = { F => 'noArgs' };
Plugins::CodecSwitch::Profiles->setup($client);
isnt($t->{$old_profile}, 'OLD-COMMAND', 'plugin overrides old exact-client profile');
Plugins::CodecSwitch::Profiles->remove($client);
is($t->{$old_profile}, 'OLD-COMMAND', 'old profile is restored on remove');
ok(!exists $t->{"mp3-aac-*-$id"}, 'plugin profiles are removed');

Slim::Player::Client->set_clients($client);
is(Plugins::CodecSwitch::Profiles->setup_all() >= 1, 1, 'setup_all visits connected clients');
Plugins::CodecSwitch::Profiles->remove_all;
ok(!exists $t->{"mp3-aac-*-$id"}, 'remove_all clears profiles');

set_formats(qw(flc mp3 wav aac ops dff dsf));
Slim::Utils::PluginManager->set_enabled('Plugins::SACDPlayer::Plugin', 1);
Plugins::CodecSwitch::Toolchain->reset_cache;
Plugins::CodecSwitch::Profiles->setup($client);
ok(!exists $t->{"dff-flc-*-$id"}, 'SACDPlayer owns dff-flc profile');
ok(!exists $t->{"dsf-flc-*-$id"}, 'SACDPlayer owns dsf-flc profile');
ok(exists $t->{"mp3-flc-*-$id"}, 'non-DSD profiles are still registered');

$t->{"dff-flc-*-$id"} = 'SACD-FAKE';
ok(Plugins::CodecSwitch::Toolchain->target_available($client, 'dff', 'flc'),
    'SACD FLAC output makes the FLAC target available');
ok(Plugins::CodecSwitch::Toolchain->target_available($client, 'dff', 'mp3'),
    'post encoder makes the MP3 target available');
delete $t->{"dff-flc-*-$id"};

Slim::Utils::PluginManager->set_enabled('Plugins::SACDPlayer::Plugin', 0);
Plugins::CodecSwitch::Toolchain->reset_cache;
Plugins::CodecSwitch::Profiles->setup($client);
ok(exists $t->{"dff-flc-*-$id"}, 'dff profiles return when SACDPlayer is disabled');
Plugins::CodecSwitch::Profiles->remove_all;

done_testing;
