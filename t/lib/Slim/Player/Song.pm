package Slim::Player::Song;

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    return bless { %args }, $class;
}

sub currentTrack { return $_[0]->{track} }
sub master       { return $_[0]->{client} }

1;
