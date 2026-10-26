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

sub _client_name {
    my ($client) = @_;
    return eval { $client->name } || eval { $client->id } || 'client';
}

sub _chain_after_sacd {
    my ($class, $args, $client, $decision) = @_;

    # SACDPlayer's PCM/FLAC output is the intermediate stream.  Force the
    # output format even when the player itself does not support FLAC; the
    # player only ever sees the final target format.
    my @base_args = @$args;
    $base_args[5] = 'flc';
    my $base = $orig_get_convert->(@base_args);

    # The client event should already have registered SACD profiles.  If it
    # has not (for example a very early first playback), ask SACDPlayer once
    # to set them up and retry.
    if (!$base || ref $base ne 'HASH') {
        my $ok = eval {
            require Plugins::SACDPlayer::Transcoder;
            Plugins::SACDPlayer::Transcoder->setup($client);
            1;
        };
        $base = $orig_get_convert->(@base_args) if $ok;
    }

    return undef unless $base && ref $base eq 'HASH';

    my $base_format = $base->{streamformat} || '';
    my $base_command = $base->{command} || '';
    return undef unless $base_format eq 'flc' && $base_command ne '-';

    my $target = Plugins::CodecSwitch::Config->resolve_target(
        $client, $decision->{target}
    ) or return undef;

    return $base if $target->{lms_format} eq 'flc';

    my $post = Plugins::CodecSwitch::Toolchain->post_plan(
        $client, $decision->{target}, 'flc'
    );
    unless ($post) {
        $log->warn(
            "SACD produced FLAC but no CodecSwitch post-encoder is available for "
            . $decision->{target}
        );
        return undef;
    }

    my %out = %$base;
    $out{command}      = '(' . $base_command . ') | ' . $post->{command};
    $out{streamformat} = $target->{lms_format};
    $out{post_backend} = $post->{backend};
    $out{post_format}  = $target->{lms_format};

    $log->debug(
        "chaining SACD FLAC -> " . $target->{lms_format}
        . " via " . ($post->{backend} || 'unknown')
        . " for " . _client_name($client)
        . " (base profile " . ($base->{profile} || '?') . ')'
    );

    return \%out;
}

sub _getConvertCommand2 {
    my @args = @_;
    my ($songOrTrack, $type, $streamModes, $need, $want, $formatOverride, $rateOverride) = @args;

    my ($track, $client) = _track_and_client($songOrTrack);
    my $source = ($track && $client)
        ? Plugins::CodecSwitch::Config->source_for_track($track)
        : undef;
    my $sacd_dsd = $source
        && Plugins::CodecSwitch::Config->is_dsd_source($source)
        && Plugins::CodecSwitch::Config->sacd_enabled;

    # Respect an explicit format choice for non-DSD material.  For DSD with
    # SACDPlayer enabled we deliberately take control so the SACD output can
    # be followed by a CodecSwitch encoder.
    if (defined $formatOverride && length $formatOverride && !$sacd_dsd) {
        return $orig_get_convert->(@args);
    }

    return $orig_get_convert->(@args) unless $track && $client;

    my $decision = Plugins::CodecSwitch::Config->decision($track, $client);
    return $orig_get_convert->(@args) unless $decision->{action} eq 'target';

    if ($sacd_dsd) {
        my $chained = __PACKAGE__->_chain_after_sacd(\@args, $client, $decision);
        return $chained if $chained;
        return $orig_get_convert->(@args);
    }

    eval {
        require Plugins::CodecSwitch::Profiles;
        Plugins::CodecSwitch::Profiles->setup($client)
            unless Plugins::CodecSwitch::Profiles->is_setup($client);
        1;
    };

    my $remote = Plugins::CodecSwitch::Config->is_remote($track) ? 1 : 0;
    my $plan = Plugins::CodecSwitch::Toolchain->plan(
        $client, $decision->{source}, $decision->{target}, $remote
    );

    if ($plan) {
        $args[5] = $plan->{lms_format};
        $log->debug(
            "forcing " . $decision->{source} . " -> " . $plan->{lms_format}
            . " (" . ($plan->{backend} || 'unknown') . ") for "
            . _client_name($client)
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
