package Slim::Player::Client;

use strict;
use warnings;

our @CLIENTS;

sub clients {
    return @CLIENTS;
}

sub set_clients {
    @CLIENTS = @_;
}

1;
