use strict;
use warnings;
use Test::More;

use lib 'lib', 't/lib';
use CodecSwitchTest qw(reset_env fake_client set_formats);
use Slim::Utils::Prefs;
use Plugins::CodecSwitch::Config;
use Plugins::CodecSwitch::Toolchain;
use Plugins::CodecSwitch::Settings;
use Plugins::CodecSwitch::PlayerSettings;

my $prefs = preferences('plugin.codecswitch');
reset_env();
set_formats(qw(flc mp3 wav aac));

my $ffmpeg = -x '/usr/bin/ffmpeg' ? '/usr/bin/ffmpeg'
           : -x '/usr/local/bin/ffmpeg' ? '/usr/local/bin/ffmpeg' : undef;
plan skip_all => 'ffmpeg not found' unless $ffmpeg;

$prefs->set('ffmpeg', $ffmpeg);
$prefs->set('sox', '/bin/true');
$prefs->set('flac', '/bin/true');
$prefs->set('lame', '/bin/true');
$prefs->set('opusenc', '/bin/true');
Plugins::CodecSwitch::Toolchain->reset_cache;

is(Plugins::CodecSwitch::Settings->name, 'PLUGIN_CODECSWITCH', 'server settings name');
is(Plugins::CodecSwitch::Settings->page, 'plugins/CodecSwitch/settings/basic.html', 'server settings page');

my $params = {
    saveSettings   => 1,
    pref_ffmpeg    => '/nope/ffmpeg',
    pref_backend_flc => 'bogus',
    pref_log_plugin_codecswitch => 'DEBUG',
    pref_log_player_source => 'BOGUS',
    pref_log_plugin_sacdplayer => 'INFO',
};
my $result = Plugins::CodecSwitch::Settings->handler(undef, $params);
is($prefs->get('backend_flc'), 'auto', 'invalid backend reset to auto');
ok(@{ $result->{warnings} }, 'server warnings recorded');
ok($result->{saved}, 'server saved flag');
ok(ref $result->{tools} eq 'ARRAY' && @{ $result->{tools} }, 'tool status is populated');
ok(ref $result->{backends} eq 'ARRAY' && @{ $result->{backends} }, 'backend rows are populated');
ok(ref $result->{log_rows} eq 'ARRAY' && @{ $result->{log_rows} }, 'log rows are populated');
is($Slim::Utils::Log::LEVELS{'plugin.codecswitch'}, 'DEBUG', 'CodecSwitch log level saved');
is($Slim::Utils::Log::LEVELS{'plugin.sacdplayer'}, 'INFO', 'SACD log level saved');
is($Slim::Utils::Log::LEVELS{'player.source'}, 'ERROR', 'invalid log level reset to ERROR');
is($Slim::Utils::Log::PERSIST, 1, 'log levels are persisted');

my $client = fake_client(formats => [qw(flc mp3 wav aac)]);
my $playerParams = {
    saveSettings => 1,
    pref_map_flc => 'mp3',
    pref_map_mp3 => 'aac',
    pref_map_wav => 'bogus',
};
my $playerResult = Plugins::CodecSwitch::PlayerSettings->handler($client, $playerParams);
my $mapping = Plugins::CodecSwitch::Config->mapping_for($client);
is($mapping->{flc}, 'mp3', 'player target mapping saved');
is($mapping->{mp3}, 'aac', 'player target mapping saved');
is($mapping->{wav}, 'direct', 'invalid player target reset to direct');
ok($playerResult->{saved}, 'player saved flag');
ok(@{ $playerResult->{warnings} }, 'player warnings recorded');
ok(ref $playerResult->{rows} eq 'ARRAY' && @{ $playerResult->{rows} }, 'player rows are populated');

my ($flcRow) = grep { $_->{key} eq 'flc' } @{ $playerResult->{rows} };
is($flcRow->{value}, 'mp3', 'rendered row reflects saved value');
ok(grep({ $_->{value} eq 'aac' } @{ $flcRow->{options} }), 'AAC target offered when available');

done_testing;
