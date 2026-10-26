package Slim::Control::Request;

use strict;
use warnings;

our @SUBSCRIBED;
our @UNSUBSCRIBED;

sub subscribe {
    my ($cb, $requests, $client) = @_;
    push @SUBSCRIBED, [ $cb, $requests, $client ];
    return 1;
}

sub unsubscribe {
    my ($cb, $client) = @_;
    push @UNSUBSCRIBED, [ $cb, $client ];
    return 1;
}

sub reset {
    @SUBSCRIBED = ();
    @UNSUBSCRIBED = ();
}

1;
