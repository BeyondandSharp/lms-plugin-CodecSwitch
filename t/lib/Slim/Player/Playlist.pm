package Slim::Player::Playlist;

use strict;
use warnings;

our @PLAYLIST;
our $INDEX = 0;

sub set_playlist {
    my ($class, @tracks) = @_;
    @PLAYLIST = @tracks;
    $INDEX = 0;
    return 1;
}

sub set_index {
    my ($class, $index) = @_;
    $INDEX = $index;
    return 1;
}

sub track {
    my ($client, $index) = @_;
    $index = $INDEX unless defined $index;
    return $PLAYLIST[$index];
}

sub count {
    return scalar @PLAYLIST;
}

1;
