use strict;
use warnings;
use Test::More;

use lib 'lib', 't/lib';
use CodecSwitchTest qw(reset_env fake_client fake_track set_formats);
use Slim::Utils::Prefs;
use Slim::Player::Playlist;
use Plugins::CodecSwitch::Config;
use Plugins::CodecSwitch::Skip;

{
    package FakeRequest;
    sub new { my ($class, $client) = @_; return bless { client => $client }, $class }
    sub client { return $_[0]->{client} }
}

my $prefs = preferences('plugin.codecswitch');
reset_env();
set_formats(qw(flc mp3 wav));

my $client = fake_client();
$prefs->client($client)->set('mapping', {
    flc => 'skip',
    mp3 => 'skip',
});
Plugins::CodecSwitch::Config->invalidate($client);

my $current = fake_track(content_type => 'flc', url => 'file:///music/current.flac');
my $skip1 = fake_track(content_type => 'flc', url => 'file:///music/skip1.flac');
my $skip2 = fake_track(content_type => 'mp3', url => 'file:///music/skip2.mp3');
my $play  = fake_track(content_type => 'wav', url => 'file:///music/play.wav');
my $skip3 = fake_track(content_type => 'flc', url => 'file:///music/skip3.flac');

Slim::Player::Playlist->set_playlist($current, $play);
Slim::Player::Playlist->set_index(0);

my $request = FakeRequest->new($client);
is(Plugins::CodecSwitch::Skip::on_newsong($request), 1, 'current skipped track is removed');
my @executed = $client->executed;
is(scalar @executed, 1, 'one deleteitem executed');
is_deeply($executed[0], [ 'playlist', 'deleteitem', $current->url ], 'deleteitem for current URL');

$client->{executed} = [];
Slim::Player::Playlist->set_playlist($play, $skip2, $skip3, $skip1);
Slim::Player::Playlist->set_index(0);
is(Plugins::CodecSwitch::Skip::on_newsong($request), 3, 'all upcoming skipped tracks are removed');
@executed = $client->executed;
is(scalar @executed, 3, 'three lookahead deleteitem commands');
is_deeply(
    [ sort map { $_->[2] } @executed ],
    [ sort map { $_->url } ($skip2, $skip3, $skip1) ],
    'lookahead removes exactly the skipped URLs',
);

$client->{executed} = [];
Slim::Player::Playlist->set_playlist($play);
Slim::Player::Playlist->set_index(0);
is(Plugins::CodecSwitch::Skip::on_newsong($request), 0, 'direct current track is not removed');
is(scalar $client->executed, 0, 'no deleteitem for direct track');

$client->{executed} = [];
my $dup = fake_track(content_type => 'flc', url => 'file:///music/duplicate.flac');
is(Plugins::CodecSwitch::Skip->delete_track($client, $dup, 'flc'), 1, 'first delete succeeds');
is(Plugins::CodecSwitch::Skip->delete_track($client, $dup, 'flc'), 0, 'duplicate is debounced');
is(scalar $client->executed, 1, 'debounce avoids a second delete');

done_testing;
