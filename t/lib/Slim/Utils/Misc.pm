package Slim::Utils::Misc;

use strict;
use warnings;

our %OVERRIDE;

sub findbin {
    my ($name) = @_;
    return $OVERRIDE{$name} if $OVERRIDE{$name};
    for my $dir (split /:/, $ENV{PATH} || '') {
        next unless length $dir;
        my $path = "$dir/$name";
        return $path if -x $path;
    }
    return undef;
}

sub set_bin {
    my ($name, $path) = @_;
    $OVERRIDE{$name} = $path;
}

sub clear_bins {
    %OVERRIDE = ();
}

sub pathFromFileURL {
    my ($url) = @_;
    $url =~ s{^file://}{};
    $url =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;
    return $url;
}

1;
