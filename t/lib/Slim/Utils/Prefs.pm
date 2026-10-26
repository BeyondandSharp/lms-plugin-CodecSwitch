package Slim::Utils::Prefs;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw(preferences);
our %PREFS;
our %CLIENT_PREFS;

sub preferences {
    my ($ns) = @_;
    return bless { ns => $ns // '' }, 'Slim::Utils::Prefs::Namespace';
}

sub reset {
    %PREFS = ();
    %CLIENT_PREFS = ();
    return 1;
}

package Slim::Utils::Prefs::Namespace;

sub get {
    my ($self, $key) = @_;
    return $Slim::Utils::Prefs::PREFS{ $self->{ns} }{$key};
}

sub set {
    my ($self, $key, $value) = @_;
    $Slim::Utils::Prefs::PREFS{ $self->{ns} }{$key} = $value;
    return $value;
}

sub client {
    my ($self, $client) = @_;
    my $id = ref $client && $client->can('id') ? $client->id : "$client";
    return bless { ns => $self->{ns}, id => $id }, 'Slim::Utils::Prefs::Client';
}

package Slim::Utils::Prefs::Client;

sub get {
    my ($self, $key) = @_;
    return $Slim::Utils::Prefs::CLIENT_PREFS{ $self->{ns} }{ $self->{id} }{$key};
}

sub set {
    my ($self, $key, $value) = @_;
    $Slim::Utils::Prefs::CLIENT_PREFS{ $self->{ns} }{ $self->{id} }{$key} = $value;
    return $value;
}

1;
