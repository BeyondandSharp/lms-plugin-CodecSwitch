package Slim::Music::Info;

use strict;
use warnings;

sub contentType {
    my ($track) = @_;
    return $track->can('content_type') ? $track->content_type : undef;
}

sub isRemoteURL {
    my ($url) = @_;
    return $url =~ m{^(?:https?|ftp|mms)://}i ? 1 : 0;
}

sub isFileURL {
    my ($url) = @_;
    return $url =~ m{^file://}i ? 1 : 0;
}

sub typeFromPath {
    my ($path) = @_;
    return undef unless $path =~ /\.([a-z0-9]+)$/i;
    my $ext = lc $1;
    my %map = (
        aiff => 'aif', flac => 'flc', m4a => 'mp4',
        opus => 'ops', wv => 'wvp',
    );
    return $map{$ext} || $ext;
}

1;
