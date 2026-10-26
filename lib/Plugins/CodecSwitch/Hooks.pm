package Plugins::CodecSwitch::Hooks;

use strict;
use warnings;

use Slim::Utils::Log;

use Plugins::CodecSwitch::Config;
use Plugins::CodecSwitch::Toolchain;

my $log = logger('plugin.codecswitch');

my $installed = 0;
my $orig_get_convert;

sub install {
    my ($class) = @_;
    return 1 if $installed;

    return 0 unless eval { require Slim::Player::TranscodingHelper; 1 };
    return 0 unless Slim::Player::TranscodingHelper->can('getConvertCommand2');

    $orig_get_convert = \&Slim::Player::TranscodingHelper::getConvertCommand2;

    no warnings 'redefine';
    *Slim::Player::TranscodingHelper::getConvertCommand2 = \&_getConvertCommand2;

    $installed = 1;
    return 1;
}

sub uninstall {
    my ($class) = @_;
    return 1 unless $installed;
    return 0 unless $orig_get_convert;

    no warnings 'redefine';
    *Slim::Player::TranscodingHelper::getConvertCommand2 = $orig_get_convert;
    $installed = 0;
    $orig_get_convert = undef;
    return 1;
}

sub _track_and_client {
    my ($songOrTrack) = @_;
    return (undef, undef) unless $songOrTrack;

    if (ref $songOrTrack && eval { $songOrTrack->isa('Slim::Player::Song') }) {
        my $track  = eval { $songOrTrack->currentTrack };
        my $client = eval { $songOrTrack->master };
        return ($track, $client);
    }

    return ($songOrTrack, undef);
}

sub _getConvertCommand2 {
    my @args = @_;
    my ($songOrTrack, $type, $streamModes, $need, $want, $formatOverride, $rateOverride) = @args;

    return $orig_get_convert->(@args)
        if defined $formatOverride && length $formatOverride;

    my ($track, $client) = _track_and_client($songOrTrack);
    return $orig_get_convert->(@args) unless $track && $client;

    my $decision = Plugins::CodecSwitch::Config->decision($track, $client);
    return $orig_get_convert->(@args) unless $decision->{action} eq 'target';

    eval {
        require Plugins::CodecSwitch::Profiles;
        Plugins::CodecSwitch::Profiles->setup($client)
            unless Plugins::CodecSwitch::Profiles->is_setup($client);
        1;
    };

    my $remote = Plugins::CodecSwitch::Config->is_remote($track) ? 1 : 0;
    my $plan = Plugins::CodecSwitch::Toolchain->plan($client, $decision->{source}, $decision->{target}, $remote);

    if ($plan) {
        $args[5] = $plan->{lms_format};
        my $name = eval { $client->name } || eval { $client->id } || 'client';
        $log->debug(
            "forcing " . $decision->{source} . " -> " . $plan->{lms_format}
            . " (" . ($plan->{backend} || 'unknown') . ") for " . $name
        );
    }
    else {
        $log->debug(
            "no usable " . $decision->{target} . " plan for "
            . $decision->{source} . "; leaving LMS to choose"
        );
    }

    return $orig_get_convert->(@args);
}

1;
