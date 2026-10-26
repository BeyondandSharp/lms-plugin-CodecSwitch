package Plugins::CodecSwitch::Plugin;

use strict;
use warnings;

use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $log = logger('plugin.codecswitch');
my $prefs = preferences('plugin.codecswitch');

sub initPlugin {
    my ($class) = @_;

    $log->info('CodecSwitch initializing');

    unless (eval { main::SCANNER() } ? 1 : 0) {
        eval {
            require Plugins::CodecSwitch::Settings;
            Plugins::CodecSwitch::Settings->new;
            1;
        } or $log->error("unable to load server settings: $@");

        eval {
            require Plugins::CodecSwitch::PlayerSettings;
            Plugins::CodecSwitch::PlayerSettings->new;
            1;
        } or $log->error("unable to load player settings: $@");

        eval {
            require Slim::Control::Request;
            Slim::Control::Request::subscribe(
                \&clientConnected,
                [ ['client'], ['new', 'reconnect'] ],
            );
            1;
        } or $log->error("unable to subscribe to client events: $@");

        eval {
            require Plugins::CodecSwitch::Skip;
            Plugins::CodecSwitch::Skip->install;
            1;
        } or $log->error("unable to install skip handler: $@");
    }

    return 1;
}

sub postinitPlugin {
    my ($class) = @_;
    return 1 if eval { main::SCANNER() } ? 1 : 0;

    eval {
        require Plugins::CodecSwitch::Profiles;
        require Plugins::CodecSwitch::Hooks;
        Plugins::CodecSwitch::Profiles->setup_all;
        Plugins::CodecSwitch::Hooks->install;
        1;
    } or $log->error("unable to install transcoding hooks: $@");

    return 1;
}

sub shutdownPlugin {
    my ($class) = @_;

    eval { require Plugins::CodecSwitch::Hooks; Plugins::CodecSwitch::Hooks->uninstall; 1 };
    eval { require Plugins::CodecSwitch::Skip; Plugins::CodecSwitch::Skip->uninstall; 1 };
    eval { require Plugins::CodecSwitch::Profiles; Plugins::CodecSwitch::Profiles->remove_all; 1 };

    return 1;
}

sub clientConnected {
    my ($request) = @_;
    my $client = eval { $request->client } or return;
    eval {
        require Plugins::CodecSwitch::Profiles;
        Plugins::CodecSwitch::Profiles->setup($client);
        1;
    } or $log->warn("unable to set up CodecSwitch profiles: $@");
    return 1;
}

# Called by settings handlers after saving.
sub setupPlayer {
    my ($class, $client) = @_;
    return 1 unless $client;
    require Plugins::CodecSwitch::Config;
    require Plugins::CodecSwitch::Profiles;
    Plugins::CodecSwitch::Config->invalidate($client);
    Plugins::CodecSwitch::Profiles->setup($client);
    return 1;
}

sub refreshAll {
    my ($class) = @_;
    require Plugins::CodecSwitch::Toolchain;
    require Plugins::CodecSwitch::Profiles;
    Plugins::CodecSwitch::Toolchain->reset_cache;
    Plugins::CodecSwitch::Profiles->setup_all;
    return 1;
}

1;
