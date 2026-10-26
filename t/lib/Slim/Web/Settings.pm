package Slim::Web::Settings;

use strict;
use warnings;

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

sub handler {
    my ($class, $client, $params) = @_;
    return $params;
}

1;
