use strict;
use warnings;
use Test::More;

use lib 'lib', 't/lib';
use CodecSwitchTest qw(reset_env fake_client set_formats);
use Slim::Utils::Prefs;
use Slim::Player::TranscodingHelper;
use Slim::Player::Client;
use Plugins::CodecSwitch::Config;
use Plugins::CodecSwitch::Profiles;
use Plugins::CodecSwitch::Toolchain;

my $prefs = preferences('plugin.codecswitch');
reset_env();

# Deliberately put alc before flc: LMS must still choose direct FLAC when the
# source is mapped to pass-through.  This is the regression that caused ALAC
# to be selected for a FLAC file.
set_formats(qw(alc flc mp3 wav aac ops));

my $ffmpeg = -x '/usr/bin/ffmpeg' ? '/usr/bin/ffmpeg'
           : -x '/usr/local/bin/ffmpeg' ? '/usr/local/bin/ffmpeg' : undef;
plan skip_all => 'ffmpeg not found' unless $ffmpeg;

$prefs->set('ffmpeg', $ffmpeg);
$prefs->set('sox', '/bin/true');
$prefs->set('flac', '/bin/true');
$prefs->set('lame', '/bin/true');
$prefs->set('opusenc', '/bin/true');
Plugins::CodecSwitch::Toolchain->reset_cache;

my $client = fake_client();
my $id = $client->id;
my $t = \%Slim::Player::TranscodingHelper::commandTable;
my $c = \%Slim::Player::TranscodingHelper::capabilities;

sub setup {
    Plugins::CodecSwitch::Config->invalidate($client);
    return Plugins::CodecSwitch::Profiles->setup($client);
}

sub set_mapping {
    my (%mapping) = @_;
    $prefs->client($client)->set('mapping', \%mapping);
    return setup();
}

# --- pass-through: no target profiles at all -------------------------------
ok(setup() > 0, 'profiles registered');
ok(exists $t->{"flc-flc-*-$id"}, 'direct FLAC profile exists');
is($t->{"flc-flc-*-$id"}, '-', 'direct FLAC profile is pass-through');
ok(!exists $t->{"flc-alc-*-$id"}, 'direct FLAC must not register flc->alc');
ok(!exists $t->{"flc-aac-*-$id"}, 'direct FLAC must not register flc->aac');
ok(exists $t->{"mp3-mp3-*-$id"}, 'direct MP3 profile exists');

# --- only the selected mapping contributes a target profile ----------------
set_mapping(flc => 'aac', mp3 => 'flc', wav => 'direct');

ok(exists $t->{"flc-aac-*-$id"}, 'mapped FLAC -> AAC profile exists');
ok(!exists $t->{"flc-flc-*-$id"}, 'mapped FLAC does not also register direct');
ok(!exists $t->{"flc-alc-*-$id"}, 'mapped FLAC does not register ALAC');
ok(exists $t->{"mp3-flc-*-$id"}, 'local MP3 -> FLAC profile exists');
ok(exists $t->{"mp3-flc-*-$id-1"}, 'remote MP3 -> FLAC profile exists');
like($t->{"mp3-flc-*-$id-1"}, qr/-i \$URL\$/, 'remote profile uses URL');
is($c->{"mp3-flc-*-$id"}{F}, 'noArgs', 'local profile has F');
is($c->{"mp3-flc-*-$id-1"}{R}, 'noArgs', 'remote profile has R');
is($c->{"flc-aac-*-$id"}{B}, 'BITRATE=-b:a %Bk', 'AAC profile exposes B capability');
ok(!exists $c->{"mp3-flc-*-$id"}{B}, 'lossless profile has no B capability');
is($t->{"wav-wav-*-$id"}, '-', 'direct WAV profile remains pass-through');
ok(!exists $t->{"wav-aac-*-$id"}, 'direct WAV has no target profiles');

# backend selection still works for the selected mapping
$prefs->set('backend_flc', 'ffmpeg');
Plugins::CodecSwitch::Toolchain->reset_cache;
set_mapping(mp3 => 'flc');
like($t->{"mp3-flc-*-$id"}, qr/ffmpeg/, 'forced FFmpeg backend is used');

$prefs->set('backend_flc', 'native');
Plugins::CodecSwitch::Toolchain->reset_cache;
set_mapping(mp3 => 'flc');
like($t->{"mp3-flc-*-$id"}, qr/\/bin\/true.*\|/, 'forced native backend is used');
$prefs->set('backend_flc', 'auto');
Plugins::CodecSwitch::Toolchain->reset_cache;

# --- external profile precedence -------------------------------------------
my $old_profile = "mp3-flc-*-$id";
$t->{$old_profile} = 'OLD-COMMAND';
$c->{$old_profile} = { F => 'noArgs' };
set_mapping(mp3 => 'flc');
is($t->{$old_profile}, 'OLD-COMMAND', 'existing external profile keeps precedence');
Plugins::CodecSwitch::Profiles->remove($client);
is($t->{$old_profile}, 'OLD-COMMAND', 'external profile is not removed');
ok(!exists $t->{"flc-aac-*-$id"}, 'plugin profiles are removed');

Slim::Player::Client->set_clients($client);
is(Plugins::CodecSwitch::Profiles->setup_all() >= 1, 1, 'setup_all visits connected clients');
Plugins::CodecSwitch::Profiles->remove_all;
ok(!exists $t->{"flc-aac-*-$id"}, 'remove_all clears profiles');

# --- DSD provider is left alone; without one, only the mapped profile exists
set_formats(qw(alc flc mp3 wav aac ops dff dsf));
$t->{"dff-flc-*-$id"} = 'SACD-FAKE';
$t->{"dsf-flc-*-$id"} = 'SACD-FAKE';
Plugins::CodecSwitch::Toolchain->reset_cache;
set_mapping(flc => 'aac', dff => 'mp3');
is($t->{"dff-flc-*-$id"}, 'SACD-FAKE', 'registered dff provider keeps its profile');
is($t->{"dsf-flc-*-$id"}, 'SACD-FAKE', 'registered dsf provider keeps its profile');
ok(!exists $t->{"dff-mp3-*-$id"}, 'CodecSwitch does not add DSD profiles when a provider exists');
ok(exists $t->{"flc-aac-*-$id"}, 'non-DSD mapped profiles are still registered');

ok(Plugins::CodecSwitch::Toolchain->target_available($client, 'dff', 'flc'),
    'DSD provider FLAC output makes the FLAC target available');
ok(Plugins::CodecSwitch::Toolchain->target_available($client, 'dff', 'mp3'),
    'post encoder makes the MP3 target available');

delete $t->{"dff-flc-*-$id"};
delete $t->{"dsf-flc-*-$id"};
Plugins::CodecSwitch::Toolchain->reset_cache;
set_mapping(flc => 'aac', dff => 'mp3');
ok(exists $t->{"dff-mp3-*-$id"}, 'mapped dff profile returns without a provider');
Plugins::CodecSwitch::Profiles->remove_all;

done_testing;
