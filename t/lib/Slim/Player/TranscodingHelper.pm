package Slim::Player::TranscodingHelper;

use strict;
use warnings;

our %commandTable;
our %capabilities;
our @CALLS;
our $MOCK;

sub reset {
    %commandTable = ();
    %capabilities = ();
    @CALLS = ();
    $MOCK = undef;
}

sub Conversions {
    return \%commandTable;
}

sub getConvertCommand2 {
    my @args = @_;
    push @CALLS, [ @args ];
    return $MOCK->(@args) if $MOCK;
    return { command => 'stub', profile => 'stub', streamformat => 'stub' };
}

1;
