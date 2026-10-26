use strict;
use warnings;
use Test::More;

use lib 'lib', 't/lib';
use CodecSwitchTest qw(reset_env fake_client fake_track set_formats);
use Slim::Utils::Prefs;
use Slim::Utils::PluginManager;
use Plugins::CodecSwitch::Config;

my $prefs = preferences('plugin.codecswitch');
reset_env();
set_formats(qw(flc mp3 wav aac ops));

my $client = fake_client();

is(scalar(Plugins::CodecSwitch::Config->sources), 21, 'source list is populated');
ok(Plugins::CodecSwitch::Config->target_by_key('flc'), 'FLAC target exists');
ok(Plugins::CodecSwitch::Config->target_by_key('aac'), 'AAC target exists');
ok(!Plugins::CodecSwitch::Config->target_by_key('bogus'), 'unknown target is rejected');

my $flac = fake_track(content_type => 'flc');
my $mp3  = fake_track(content_type => 'mp3', url => 'file:///music/a.mp3');
my $aiff = fake_track(content_type => 'aiff', url => 'file:///music/a.aiff');

is(Plugins::CodecSwitch::Config->source_for_track($flac), 'flc', 'FLAC source');
is(Plugins::CodecSwitch::Config->source_for_track($mp3), 'mp3', 'MP3 source');
is(Plugins::CodecSwitch::Config->source_for_track($aiff), undef, 'unsupported source type');

my $fallback = fake_track(content_type => '', url => 'file:///music/a.flac');
is(Plugins::CodecSwitch::Config->source_for_track($fallback), 'flc', 'URL extension fallback');

is_deeply(
    [ sort Plugins::CodecSwitch::Config->player_formats($client) ],
    [ sort qw(flc mp3 wav aac ops) ],
    'player formats are read from capabilities',
);

my $target = Plugins::CodecSwitch::Config->resolve_target($client, 'flc');
is($target->{lms_format}, 'flc', 'FLAC target resolves for capable player');
is(Plugins::CodecSwitch::Config->resolve_target($client, 'aif'), undef,
    'unsupported target does not resolve');

my $direct = Plugins::CodecSwitch::Config->decision($flac, $client);
is($direct->{action}, 'direct', 'default action is direct');
is(Plugins::CodecSwitch::Config->mapping_value($client, 'flc'), 'direct', 'default mapping value');

$prefs->client($client)->set('mapping', { flc => 'skip', mp3 => 'aac', wav => 'bogus' });
Plugins::CodecSwitch::Config->invalidate($client);

my $skip = Plugins::CodecSwitch::Config->decision($flac, $client);
is($skip->{action}, 'skip', 'skip mapping');
my $convert = Plugins::CodecSwitch::Config->decision($mp3, $client);
is($convert->{action}, 'target', 'target mapping');
is($convert->{target}, 'aac', 'target key');
my $wav = fake_track(content_type => 'wav');
is(Plugins::CodecSwitch::Config->decision($wav, $client)->{action}, 'direct',
    'invalid stored value falls back to direct');

my $normalized = Plugins::CodecSwitch::Config->normalize_mapping(
    { flc => 'skip', mp3 => 'aac', wav => 'nope' },
    { aac => 1 },
);
is($normalized->{flc}, 'skip', 'normalize keeps skip');
is($normalized->{mp3}, 'aac', 'normalize keeps allowed target');
is($normalized->{wav}, 'direct', 'normalize resets invalid target');
is($normalized->{ape}, 'direct', 'normalize fills missing source');

ok(Plugins::CodecSwitch::Config->is_remote(fake_track(url => 'http://example.test/a.flac')),
    'remote URL detected');
ok(!Plugins::CodecSwitch::Config->is_remote($flac), 'local file not remote');

ok(!Plugins::CodecSwitch::Config->sacd_enabled, 'SACDPlayer is not enabled by default');
Slim::Utils::PluginManager->set_enabled('Plugins::SACDPlayer::Plugin', 1);
ok(Plugins::CodecSwitch::Config->sacd_enabled, 'SACDPlayer enabled is detected');
ok(Plugins::CodecSwitch::Config->is_dsd_source('dff'), 'DFF is a DSD source');
ok(Plugins::CodecSwitch::Config->is_dsd_source('dsf'), 'DSF is a DSD source');
ok(!Plugins::CodecSwitch::Config->is_dsd_source('flc'), 'FLAC is not a DSD source');

done_testing;
