package Plugins::CodecSwitch::Orchestrator;

use strict;
use warnings;

use Slim::Utils::Log;
use Slim::Utils::Prefs;

use Plugins::CodecSwitch::Capabilities;
use Plugins::CodecSwitch::Config;
use Plugins::CodecSwitch::Toolchain;

my $log = logger('plugin.codecswitch');
my $prefs = preferences('plugin.codecswitch');

sub max_rate {
    my ($class, $client) = @_;
    return 0 unless $client;

    my $rate = eval { Slim::Utils::Prefs::maxRate($client) };
    return int($rate) if $rate && $rate =~ /^\d+$/;

    my $saved = eval { $prefs->client($client)->get('maxBitrate') };
    return int($saved) if $saved && $saved =~ /^\d+$/;
    return 0;
}

sub wants_bitrate {
    my ($class, $want) = @_;
    return 0 unless ref $want eq 'ARRAY';
    return (grep { defined $_ && $_ eq 'B' } @$want) ? 1 : 0;
}

sub pcm_options {
    my ($class, $target, $source) = @_;
    my $lms = $target->{lms_format} || '';

    if ($lms =~ /^(?:mp3|aac|ogg|ops)$/) {
        return {
            sample_fmt => 's16le',
            rate       => ($lms eq 'ops' ? 48000 : 44100),
            channels   => 2,
        };
    }

    return {
        sample_fmt => 's24le',
        rate       => 176400,
        channels   => 2,
    };
}

sub _decode_plan {
    my ($class, $client, $format, $opts) = @_;
    return eval {
        require Plugins::SACDPlayer::Transcoder;
        Plugins::SACDPlayer::Transcoder->decode_plan($client, $format, $opts);
    };
}

sub _as_base {
    my ($class, $plan, $source, $format) = @_;
    return undef unless ref $plan eq 'HASH' && defined $plan->{command};
    return {
        command          => $plan->{command},
        streamformat     => $format,
        profile          => ($source . '-' . $format . '-*-codecswitch'),
        capabilities     => $plan->{capabilities} || {},
        usedCapabilities => [],
        streamMode       => 'F',
        plugin           => 'CodecSwitch',
    };
}

# Build the final DSD rule.  $base is the SACD FLAC transcoder returned by
# LMS; it is used when a PCM decode plan is not available.
sub sacd_rule {
    my ($class, $client, $source, $target_key, $base, $want_b) = @_;
    return undef unless $client && $source && $target_key;

    my $target = Plugins::CodecSwitch::Config->resolve_target($client, $target_key)
        or return undef;
    my $lms_target = $target->{lms_format};

    # If SACD already produced the final format, stop: never encode FLAC a
    # second time.
    if ($base && ($base->{streamformat} || '') eq $lms_target) {
        return { base => $base, format => $lms_target, stopped => 1 };
    }

    my $bitrate = $want_b ? $class->max_rate($client) : 0;
    my $pcm = $class->pcm_options($target, $source);
    my $decode = $class->_decode_plan($client, 'pcm', $pcm);

    my ($decode_base, $input_format, $input_rate, $input_channels);
    if (ref $decode eq 'HASH' && defined $decode->{command}) {
        $decode_base = $class->_as_base($decode, $source, 'pcm');
        if ($base) {
            # Keep the SACD profile for LMS tokenization (it owns the
            # F/T/U/D capability table); only the command is replaced.
            $decode_base->{profile} = $base->{profile} if $base->{profile};
            $decode_base->{usedCapabilities} = $base->{usedCapabilities} || [];
            $decode_base->{streamMode} = $base->{streamMode} || 'F';
        }
        $input_format = 'pcm';
        $input_rate = $pcm->{rate};
        $input_channels = $pcm->{channels};
    }
    elsif ($base && ($base->{streamformat} || '') eq 'flc') {
        # Fallback: use SACD's FLAC output and let the final encoder decode it.
        $decode_base = $base;
        $input_format = 'flc';
    }
    else {
        return undef;
    }

    my $post = Plugins::CodecSwitch::Toolchain->post_plan(
        $client, $target_key, $input_format,
        bitrate        => $bitrate,
        input_rate       => $input_rate,
        input_channels   => $input_channels,
        input_sample_fmt => ($input_format eq 'pcm' ? $pcm->{sample_fmt} : undef),
    );
    return undef unless $post;

    my %out = %$decode_base;
    $out{command}      = '(' . $decode_base->{command} . ') | ' . $post->{command};
    $out{streamformat} = $lms_target;
    $out{post_format}  = $lms_target;
    $out{post_backend} = $post->{backend};
    $out{codecswitch_chain} = 1;
    $out{capabilities} = {
        %{ $decode_base->{capabilities} || {} },
        B => 'BITRATE=-b:a %Bk',
    } if $bitrate && $target->{bitrate};

    $log->debug(
        "SACD $source -> $input_format -> $lms_target"
        . ($bitrate ? " at ${bitrate}k" : '')
        . " via " . ($post->{backend} || 'unknown')
        . " for " . (eval { $client->name } || $client->id || 'client')
    );

    return {
        base   => $decode_base,
        format => $lms_target,
        post   => $post,
        input_format => $input_format,
        result => \%out,
    };
}

1;
