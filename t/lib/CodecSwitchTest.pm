package CodecSwitchTest;

use strict;
use warnings;

use Exporter 'import';
use File::Temp qw(tempdir);

use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Player::TranscodingHelper;
use Slim::Player::CapabilitiesHelper;
use Slim::Player::Playlist;
use Slim::Player::Client;
use Slim::Player::Song;
use Slim::Control::Request;
use Slim::Utils::PluginManager;

our @EXPORT_OK = qw(reset_env fake_client fake_track fake_song set_formats);

my $TMPDIR;

sub reset_env {
    Slim::Utils::Prefs::reset();
    Slim::Player::TranscodingHelper::reset();
    Slim::Control::Request::reset();
    Slim::Utils::PluginManager->reset();
    Slim::Utils::Misc::clear_bins();
    Slim::Player::CapabilitiesHelper::set_formats();
    Slim::Player::Playlist->set_playlist();
    Slim::Player::Client->set_clients();

    $TMPDIR = tempdir(CLEANUP => 1) unless $TMPDIR && -d $TMPDIR;
    $Slim::Utils::Prefs::PREFS{server}{cachedir} = $TMPDIR;

    return 1;
}

sub set_formats {
    my @formats = @_;
    Slim::Player::CapabilitiesHelper->set_formats(@formats);
    return 1;
}

sub fake_client {
    my (%args) = @_;
    return CodecSwitchTest::Client->new(%args);
}

sub fake_track {
    my (%args) = @_;
    return CodecSwitchTest::Track->new(%args);
}

sub fake_song {
    my ($track, $client) = @_;
    return Slim::Player::Song->new(track => $track, client => $client);
}

package CodecSwitchTest::Client;

sub new {
    my ($class, %args) = @_;
    return bless {
        id         => $args{id} || 'aa:bb:cc:dd:ee:ff',
        name       => $args{name} || 'Test Player',
        formats    => $args{formats} || [qw(flc mp3 wav aif aac ogg ops)],
        executed   => [],
        max_rate   => $args{max_rate} || 192000,
    }, $class;
}

sub id   { return $_[0]->{id} }
sub name { return $_[0]->{name} }
sub formats { return @{ $_[0]->{formats} } }
sub maxSupportedSamplerate { return $_[0]->{max_rate} }
sub masterOrSelf { return $_[0] }
sub master       { return $_[0] }

sub execute {
    my ($self, $command) = @_;
    push @{ $self->{executed} }, $command;
    return 1;
}

sub executed {
    my ($self) = @_;
    return @{ $self->{executed} };
}

package CodecSwitchTest::Track;

sub new {
    my ($class, %args) = @_;
    return bless {
        url          => $args{url} || 'file:///music/test.flac',
        content_type => $args{content_type} || 'flc',
        title        => $args{title} || 'Test Track',
    }, $class;
}

sub url          { return $_[0]->{url} }
sub content_type { return $_[0]->{content_type} }
sub title        { return $_[0]->{title} }

1;
