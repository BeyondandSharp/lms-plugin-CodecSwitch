package Plugins::CodecSwitch::Hooks;

use strict;
use warnings;

use Slim::Utils::Log;

use Plugins::CodecSwitch::Capabilities;
use Plugins::CodecSwitch::Config;
use Plugins::CodecSwitch::Orchestrator;
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
    my ($class, $args, $client, $decision, $want) = @_;

    my $target = Plugins::CodecSwitch::Config->resolve_target(
        $client, $decision->{target}
    ) or return undef;

    # Unknown/legacy direct DSD profile wins (priority 0).
    return undef if Plugins::CodecSwitch::Capabilities->unknown_dsd_direct(
        $client, $decision->{source}, $target->{lms_format}, 0
    );

    # The registered DSD provider's PCM/FLAC output is the intermediate stream.
    my @base_args = @$args;
    $base_args[5] = 'flc';
    my $base = $orig_get_convert->(@base_args);

    return undef unless $base && ref $base eq 'HASH';

    my $want_b = Plugins::CodecSwitch::Orchestrator->wants_bitrate($want);
    my $rule = Plugins::CodecSwitch::Orchestrator->sacd_rule(
        $client, $decision->{source}, $decision->{target}, $base, $want_b
    );

    if ($rule && $rule->{result}) {
        return $rule->{result};
    }

    if ($rule && $rule->{stopped}) {
        return $rule->{base};
    }

    # Fallback to the old FLAC-only chain for older DSD providers.
    return undef unless ($base->{streamformat} || '') eq 'flc';

    my $post = Plugins::CodecSwitch::Toolchain->post_plan(
        $client, $decision->{target}, 'flc',
        bitrate => $want_b
            ? Plugins::CodecSwitch::Orchestrator->max_rate($client) : 0,
    );
    return undef unless $post;

    my %out = %$base;
    $out{command}      = '(' . $base->{command} . ') | ' . $post->{command};
    $out{streamformat} = $target->{lms_format};
    $out{post_backend} = $post->{backend};
    $out{post_format}  = $target->{lms_format};
    $out{codecswitch_chain} = 1;

    return \%out;
}

sub _getConvertCommand2 {
    my @args = @_;
    my ($songOrTrack, $type, $streamModes, $need, $want, $formatOverride, $rateOverride) = @args;

    my ($track, $client) = _track_and_client($songOrTrack);
    my $source = ($track && $client)
        ? Plugins::CodecSwitch::Config->source_for_track($track)
        : undef;
    my $dsd_provider = $source
        && Plugins::CodecSwitch::Config->is_dsd_source($source)
        && Plugins::CodecSwitch::Capabilities->has_dsd_provider($client, $source);

    # Respect an explicit format choice for non-DSD material.  For DSD with a
    # registered provider we deliberately take control so the provider output
    # can be followed by a CodecSwitch encoder.
    if (defined $formatOverride && length $formatOverride && !$dsd_provider) {
        return $orig_get_convert->(@args);
    }

    return $orig_get_convert->(@args) unless $track && $client;

    my $decision = Plugins::CodecSwitch::Config->decision($track, $client);

    if ($decision->{action} eq 'direct') {
        # Do not merely leave the format choice to LMS: other plugins may have
        # registered target profiles (for example FFmpeg's flc->aac), and LMS
        # may select one when the player advertises that target before the
        # source format.  Pass-through means the original source format.
        if ($source && grep { $_ eq $source }
            Plugins::CodecSwitch::Config->player_formats($client)) {
            $args[5] = $source;
            $log->debug("forcing direct source $source for " . _client_name($client));
        }
        return $orig_get_convert->(@args);
    }

    if ($dsd_provider) {
        my $chained = __PACKAGE__->_chain_after_sacd(\@args, $client, $decision, $want);
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
