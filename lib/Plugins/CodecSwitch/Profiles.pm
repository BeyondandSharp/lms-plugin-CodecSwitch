package Plugins::CodecSwitch::Profiles;

use strict;
use warnings;

use Slim::Utils::Log;

use Plugins::CodecSwitch::Capabilities;
use Plugins::CodecSwitch::Config;
use Plugins::CodecSwitch::Toolchain;

my $log = logger('plugin.codecswitch');

# client id => { profile => { old_command, old_capabilities, command } }
my %REGISTERED;
my %SETUP;

sub _client_id {
    my ($client) = @_;
    return eval { $client->id } || eval { $client->macaddress } || "$client";
}

sub _ensure_transcoding {
    return 1 if eval { require Slim::Player::TranscodingHelper; 1 };
    $log->error("Unable to load Slim::Player::TranscodingHelper");
    return 0;
}

sub _add {
    my ($class, $clientid, $profile, $command, $capabilities) = @_;
    my $old_command = $Slim::Player::TranscodingHelper::commandTable{$profile};
    my $old_caps    = $Slim::Player::TranscodingHelper::capabilities{$profile};

    $REGISTERED{$clientid}{$profile} = {
        old_command => $old_command,
        old_caps    => $old_caps,
        command     => $command,
    };

    $Slim::Player::TranscodingHelper::commandTable{$profile} = $command;
    $Slim::Player::TranscodingHelper::capabilities{$profile} = $capabilities;
    return 1;
}

sub setup {
    my ($class, $client) = @_;
    return 0 unless $client;
    return 0 unless _ensure_transcoding();

    my $clientid = _client_id($client);
    return 0 unless defined $clientid && length $clientid;

    $class->remove($client);

    my %formats = map { $_ => 1 } Plugins::CodecSwitch::Config->player_formats($client);
    my $count = 0;

    for my $source_spec (Plugins::CodecSwitch::Config->sources) {
        my $source = $source_spec->{key};

        # Let an already-registered DSD provider own dff/dsf profiles.
        # CodecSwitch chains a second stage after its PCM/FLAC output.
        next if Plugins::CodecSwitch::Config->is_dsd_source($source)
            && Plugins::CodecSwitch::Capabilities->has_dsd_provider($client, $source);

        my $mapping = Plugins::CodecSwitch::Config->mapping_for($client);
        my $mapped  = $mapping->{$source} || 'direct';

        # Only the selected mapping may contribute a profile.  Registering all
        # target profiles makes LMS choose e.g. flc->alc just because the
        # player advertises "alc" before "flc", even when the source is set to
        # pass-through.
        if ($mapped eq 'direct') {
            if ($formats{$source}
                && !Plugins::CodecSwitch::Capabilities->has_external_profile(
                    $client, $source, $source, 0)) {
                $class->_add(
                    $clientid,
                    "$source-$source-*-$clientid",
                    '-',
                    { I => 'noArgs', F => 'noArgs', R => 'noArgs' },
                );
                $count++;
            }
            next;
        }

        my $target = Plugins::CodecSwitch::Config->target_by_key($mapped) or next;
        next unless grep { $formats{$_} } @{ $target->{formats} };
        next unless Plugins::CodecSwitch::Config->resolve_target($client, $target->{key});

        my $local = Plugins::CodecSwitch::Toolchain->plan($client, $source, $target->{key}, 0);
        if ($local && !$local->{direct}
            && !Plugins::CodecSwitch::Capabilities->has_external_profile(
                $client, $source, $local->{lms_format}, 0)) {
            $class->_add(
                $clientid,
                "$source-$local->{lms_format}-*-$clientid",
                $local->{command},
                $local->{capabilities},
            );
            $count++;
        }

        my $remote = Plugins::CodecSwitch::Toolchain->plan($client, $source, $target->{key}, 1);
        if ($remote && !$remote->{direct}
            && !Plugins::CodecSwitch::Capabilities->has_external_profile(
                $client, $source, $remote->{lms_format}, 1)) {
            $class->_add(
                $clientid,
                "$source-$remote->{lms_format}-*-$clientid-1",
                $remote->{command},
                $remote->{capabilities},
            );
            $count++;
        }
    }

    $SETUP{$clientid} = 1;
    $log->debug("registered $count CodecSwitch profiles for $clientid");
    return $count;
}


sub is_managed_profile {
    my ($class, $profile) = @_;
    return 0 unless defined $profile;

    my $table = eval { require Slim::Player::TranscodingHelper; 1 }
        ? \%Slim::Player::TranscodingHelper::commandTable
        : {};

    for my $clientid (keys %REGISTERED) {
        my $entry = $REGISTERED{$clientid}{$profile} or next;
        my $current = $table->{$profile};
        # Only count the profile as managed while our command is still the
        # active one.  A provider may overwrite the same client profile
        # later; that profile must then be visible as an external provider.
        return 1 if defined $current && defined $entry->{command}
            && $current eq $entry->{command};
    }
    return 0;
}

sub remove {
    my ($class, $client) = @_;
    return 0 unless $client;
    my $clientid = _client_id($client);
    delete $SETUP{$clientid};
    my $registered = delete $REGISTERED{$clientid} or return 0;
    return 0 unless _ensure_transcoding();

    for my $profile (keys %$registered) {
        my $entry = $registered->{$profile};
        my $current = $Slim::Player::TranscodingHelper::commandTable{$profile};

        # Do not clobber a profile another plugin installed after us.
        next if defined $current && defined $entry->{command} && $current ne $entry->{command};

        if (defined $entry->{old_command}) {
            $Slim::Player::TranscodingHelper::commandTable{$profile} = $entry->{old_command};
        }
        else {
            delete $Slim::Player::TranscodingHelper::commandTable{$profile};
        }

        if (defined $entry->{old_caps}) {
            $Slim::Player::TranscodingHelper::capabilities{$profile} = $entry->{old_caps};
        }
        else {
            delete $Slim::Player::TranscodingHelper::capabilities{$profile};
        }
    }

    return 1;
}

sub is_setup {
    my ($class, $client) = @_;
    return 0 unless $client;
    my $clientid = _client_id($client);
    return $SETUP{$clientid} ? 1 : 0;
}

sub setup_all {
    my ($class) = @_;
    return 0 unless eval { require Slim::Player::Client; 1 };

    my @clients = eval { Slim::Player::Client::clients() };
    my $count = 0;
    for my $client (@clients) {
        next unless $client;
        $class->setup($client);
        $count++;
    }
    return $count;
}

sub remove_all {
    my ($class) = @_;
    %SETUP = ();
    for my $clientid (keys %REGISTERED) {
        my $entry = delete $REGISTERED{$clientid};
        next unless $entry && _ensure_transcoding();
        for my $profile (keys %$entry) {
            my $data = $entry->{$profile};
            my $current = $Slim::Player::TranscodingHelper::commandTable{$profile};
            next if defined $current && defined $data->{command} && $current ne $data->{command};
            if (defined $data->{old_command}) {
                $Slim::Player::TranscodingHelper::commandTable{$profile} = $data->{old_command};
            }
            else {
                delete $Slim::Player::TranscodingHelper::commandTable{$profile};
            }
            if (defined $data->{old_caps}) {
                $Slim::Player::TranscodingHelper::capabilities{$profile} = $data->{old_caps};
            }
            else {
                delete $Slim::Player::TranscodingHelper::capabilities{$profile};
            }
        }
    }
    return 1;
}

1;
