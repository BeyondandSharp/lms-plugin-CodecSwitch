package Slim::Player::TranscodingHelper;

use strict;
use warnings;

our %commandTable;
our %capabilities;
our @CALLS;

sub reset {
    %commandTable = ();
    %capabilities = ();
    @CALLS = ();
}

sub getConvertCommand2 {
    my @args = @_;
    push @CALLS, [ @args ];
    return { command => 'stub', profile => 'stub', streamformat => 'stub' };
}

1;
