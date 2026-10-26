use strict;
use warnings;
use Test::More;

use lib 'lib', 't/lib';
use CodecSwitchTest qw(reset_env fake_client set_formats);
use Slim::Player::TranscodingHelper;
use Plugins::CodecSwitch::Capabilities;
use Plugins::CodecSwitch::Orchestrator;

reset_env();
set_formats(qw(flc mp3 aac ogg ops));

my $client = fake_client();
my $id = $client->id;
my $table = \%Slim::Player::TranscodingHelper::commandTable;

is(Plugins::CodecSwitch::Capabilities->priority_for('unknown'), 0, 'unknown priority 0');
is(Plugins::CodecSwitch::Capabilities->priority_for('sacd'), 50, 'SACD priority 50');
is(Plugins::CodecSwitch::Capabilities->priority_for('ffmpeg'), 100, 'FFmpeg priority 100');
is(Plugins::CodecSwitch::Capabilities->priority_for('native'), 200, 'Native priority 200');

{
    no warnings 'once';
    package FakeProvider;
    sub codec_capabilities { return { provider => 'fake', priority => 7 } }
}
is(Plugins::CodecSwitch::Capabilities->provider_priority('FakeProvider'), 7,
    'provider_priority reads optional codec_capabilities');
is(Plugins::CodecSwitch::Capabilities->provider_priority('NoSuchProvider'), 0,
    'provider without declaration is unknown');

$table->{"flc-mp3-*-$id"} = '[ffmpeg] -i $FILE$ -f mp3 -';
my $ff = Plugins::CodecSwitch::Capabilities->external_profile($client, 'flc', 'mp3', 0);
is($ff->{priority}, 100, 'ffmpeg external profile priority 100');
is($ff->{profile}, "flc-mp3-*-$id", 'ffmpeg profile found');
ok(Plugins::CodecSwitch::Capabilities->has_external_profile($client, 'flc', 'mp3', 0),
    'external profile detected');
ok(!Plugins::CodecSwitch::Capabilities->unknown_dsd_direct($client, 'dff', 'mp3', 0),
    'no DSD direct profile');

$table->{"dff-mp3-*-$id"} = 'LEGACY-CMD $FILE$';
my $legacy = Plugins::CodecSwitch::Capabilities->external_profile($client, 'dff', 'mp3', 0);
is($legacy->{priority}, 0, 'legacy profile priority 0');
ok(Plugins::CodecSwitch::Capabilities->unknown_dsd_direct($client, 'dff', 'mp3', 0),
    'unknown DSD direct wins');

delete $table->{"dff-mp3-*-$id"};
$table->{"dff-mp3-*-$id"} = 'SACDPlayer $FILE$';
is(Plugins::CodecSwitch::Capabilities->external_profile($client, 'dff', 'mp3', 0)->{priority},
    50, 'SACD profile priority 50');

is(Plugins::CodecSwitch::Orchestrator->pcm_options({ lms_format => 'mp3' }, 'dff')->{sample_fmt},
    's16le', 'lossy PCM is s16le');
is(Plugins::CodecSwitch::Orchestrator->pcm_options({ lms_format => 'ops' }, 'dff')->{rate},
    48000, 'Opus PCM uses 48k');
is(Plugins::CodecSwitch::Orchestrator->pcm_options({ lms_format => 'wav' }, 'dff')->{sample_fmt},
    's24le', 'lossless PCM keeps 24-bit');
ok(Plugins::CodecSwitch::Orchestrator->wants_bitrate([qw(F B)]), 'B want detected');
ok(!Plugins::CodecSwitch::Orchestrator->wants_bitrate([qw(F)]), 'no B want');

done_testing;
