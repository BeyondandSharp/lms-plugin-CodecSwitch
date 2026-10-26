package Plugins::CodecSwitch::Profiles;

use strict;
use warnings;

use Slim::Utils::Log;

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

        if ($formats{$source}) {
            $class->_add(
                $clientid,
                "$source-$source-*-$clientid",
                '-',
                { I => 'noArgs', F => 'noArgs', R => 'noArgs' },
            );
            $count++;
        }

        for my $target (Plugins::CodecSwitch::Config->targets) {
            next unless grep { $formats{$_} } @{ $target->{formats} };

            my $local = Plugins::CodecSwitch::Toolchain->plan($client, $source, $target->{key}, 0);
            if ($local && !$local->{direct}) {
                $class->_add(
                    $clientid,
                    "$source-$local->{lms_format}-*-$clientid",
                    $local->{command},
                    $local->{capabilities},
                );
                $count++;
            }

            my $remote = Plugins::CodecSwitch::Toolchain->plan($client, $source, $target->{key}, 1);
            if ($remote && !$remote->{direct}) {
                $class->_add(
                    $clientid,
                    "$source-$remote->{lms_format}-*-$clientid-1",
                    $remote->{command},
                    $remote->{capabilities},
                );
                $count++;
            }
        }
    }

    $SETUP{$clientid} = 1;
    $log->debug("registered $count CodecSwitch profiles for $clientid");
    return $count;
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
