use strict;
use warnings;
use Test::More;

use lib 'lib', 't/lib';
use CodecSwitchTest qw(reset_env fake_client set_formats);
use Slim::Player::TranscodingHelper;
use Plugins::CodecSwitch::Capabilities;
use Plugins::CodecSwitch::Profiles;

reset_env();
set_formats(qw(flc mp3 wav aac dff dsf));

my $client = fake_client();
my $id = $client->id;
my $table = \%Slim::Player::TranscodingHelper::commandTable;

ok(!Plugins::CodecSwitch::Capabilities->has_dsd_provider($client, 'dff'),
    'no provider for dff');
ok(!Plugins::CodecSwitch::Capabilities->has_dsd_provider($client, 'dsf'),
    'no provider for dsf');

$table->{"dff-flc-*" . "-$id"} = 'SACD-CMD $FILE$';
is(Plugins::CodecSwitch::Capabilities->dsd_provider($client, 'dff')->{profile},
    "dff-flc-*-$id", 'client-specific dff provider found');

$table->{'dsf-flc-*-*'} = 'DSD-CMD $FILE$';
ok(Plugins::CodecSwitch::Capabilities->has_dsd_provider($client, 'dsf'),
    'wildcard dsf provider found');

$table->{"dff-flc-*" . "-$id"} = '-';
ok(!Plugins::CodecSwitch::Capabilities->has_dsd_provider($client, 'dff'),
    'passthrough is not a provider');

$table->{"dff-flc-*" . "-$id"} = 'SACD-CMD $FILE$';
Plugins::CodecSwitch::Profiles->setup($client);
is($table->{"dff-flc-*-$id"}, 'SACD-CMD $FILE$',
    'CodecSwitch leaves the provider profile alone');
ok(!exists $table->{"dff-mp3-*-$id"},
    'CodecSwitch does not register a competing DSD profile');

Plugins::CodecSwitch::Profiles->remove_all;
delete $table->{"dff-flc-*" . "-$id"};
delete $table->{'dsf-flc-*-*'};

ok(!Plugins::CodecSwitch::Capabilities->has_dsd_provider($client, 'dff'),
    'provider disappears when profiles are removed');

done_testing;
