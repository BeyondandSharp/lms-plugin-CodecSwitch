package Slim::Player::CapabilitiesHelper;

use strict;
use warnings;

our %FORMATS;

sub set_formats {
    my ($class, @formats) = @_;
    %FORMATS = map { $_ => 1 } @formats;
    return 1;
}

sub supportedFormats {
    my ($client) = @_;
    return keys %FORMATS if %FORMATS;
    return $client->can('formats') ? $client->formats : ();
}

sub samplerateLimit { return undef }

1;
