package Plugins::CodecSwitch::Capabilities;

use strict;
use warnings;
no warnings 'once';

# Provider priorities.  Smaller wins.  Plugins which do not expose a
# capability declaration are deliberately treated as priority 0 so that an
# existing/unknown profile keeps precedence over CodecSwitch's own choices.
our %PRIORITY = (
    unknown => 0,
    sacd    => 50,
    ffmpeg  => 100,
    native  => 200,
);

sub priority_for {
    my ($class, $provider) = @_;
    return $PRIORITY{ lc($provider || '') } if defined $provider;
    return $PRIORITY{unknown};
}

sub provider_priority {
    my ($class, $module) = @_;
    return $PRIORITY{unknown} unless $module;

    my $caps = eval { $module->can('codec_capabilities') ? $module->codec_capabilities : undef };
    if (ref $caps eq 'HASH' && defined $caps->{priority} && $caps->{priority} =~ /^\d+$/) {
        return int($caps->{priority});
    }

    return $PRIORITY{unknown};
}

sub _table {
    return eval { require Slim::Player::TranscodingHelper; 1 }
        ? \%Slim::Player::TranscodingHelper::commandTable
        : {};
}

sub _priority_of_command {
    my ($class, $command) = @_;
    return 0 unless defined $command && length $command;
    return $PRIORITY{sacd}   if $command =~ /SACDPlayer|sacd_dsd|sacd/i;
    return $PRIORITY{ffmpeg} if $command =~ /\[ffmpeg\]/i;
    return 0;
}

sub _keys_for {
    my ($class, $clientid, $player, $source, $target, $remote) = @_;
    my @keys = (
        "$source-$target-$player-$clientid",
        "$source-$target-*-$clientid",
        "$source-$target-$player-*",
        "$source-$target-*-*",
    );
    @keys = map { "$_-1" } @keys if $remote;
    return @keys;
}

sub external_profile {
    my ($class, $client, $source, $lms_target, $remote) = @_;
    return undef unless $client && $source && $lms_target;

    my $table = $class->_table;
    my $id = eval { $client->id } || eval { $client->macaddress } || '';
    my $player = eval { $client->model } || '';
    return undef unless length $id;

    my $best;
    for my $key ($class->_keys_for($id, $player, $source, $lms_target, $remote)) {
        my $command = $table->{$key};
        next unless defined $command && length $command;
        next if eval {
            require Plugins::CodecSwitch::Profiles;
            Plugins::CodecSwitch::Profiles->is_managed_profile($key);
        };
        my $priority = $class->_priority_of_command($command);
        if (!defined $best || $priority < $best->{priority}) {
            $best = {
                profile  => $key,
                command  => $command,
                priority => $priority,
            };
        }
    }
    return $best;
}

sub has_external_profile {
    my ($class, $client, $source, $lms_target, $remote) = @_;
    return $class->external_profile($client, $source, $lms_target, $remote) ? 1 : 0;
}

# For DSD we let an explicitly higher-priority (lower numeric) unknown/legacy
# profile win; an ffmpeg profile (100) is still below SACD (50).
sub unknown_dsd_direct {
    my ($class, $client, $source, $lms_target, $remote) = @_;
    my $edge = $class->external_profile($client, $source, $lms_target, $remote);
    return 0 unless $edge;
    return 1 if $edge->{priority} == $PRIORITY{unknown};
    return 0;
}

1;
