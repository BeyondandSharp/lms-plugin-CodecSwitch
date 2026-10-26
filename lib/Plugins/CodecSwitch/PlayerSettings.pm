package Plugins::CodecSwitch::PlayerSettings;

use strict;
use warnings;

use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;
use Slim::Web::HTTP::CSRF;

use Plugins::CodecSwitch::Config;
use Plugins::CodecSwitch::Plugin;
use Plugins::CodecSwitch::Profiles;
use Plugins::CodecSwitch::Toolchain;

my $prefs = preferences('plugin.codecswitch');

sub getDisplayName {
    return 'PLUGIN_CODECSWITCH';
}

sub needsClient {
    return 1;
}

sub name {
    return Slim::Web::HTTP::CSRF->protectName('PLUGIN_CODECSWITCH');
}

sub page {
    return Slim::Web::HTTP::CSRF->protectURI('plugins/CodecSwitch/settings/player.html');
}

sub _options_for {
    my ($class, $client, $source) = @_;

    my @options = (
        { value => 'direct', string => 'PLUGIN_CODECSWITCH_DIRECT' },
        { value => 'skip',   string => 'PLUGIN_CODECSWITCH_SKIP' },
    );
    my %valid = (direct => 1, skip => 1);

    for my $target (Plugins::CodecSwitch::Config->targets) {
        next unless Plugins::CodecSwitch::Toolchain->target_available(
            $client, $source, $target->{key}
        );
        push @options, {
            value => $target->{key},
            label => $target->{label},
        };
        $valid{ $target->{key} } = 1;
    }

    return (\@options, \%valid);
}

sub handler {
    my ($class, $client, $params, $callback, @args) = @_;

    return $class->SUPER::handler($client, $params) unless $client;

    my @warnings;

    if ($params->{saveSettings}) {
        my %mapping;
        for my $source (Plugins::CodecSwitch::Config->sources) {
            my $key = $source->{key};
            my (undef, $valid) = $class->_options_for($client, $key);
            my $value = $params->{"pref_map_$key"};
            $value = 'direct' unless defined $value && length $value;
            if (!$valid->{$value}) {
                push @warnings, { token => 'PLUGIN_CODECSWITCH_WARN_MAPPING', detail => $key };
                $value = 'direct';
            }
            $mapping{$key} = $value;
        }

        $prefs->client($client)->set('mapping', \%mapping);
        Plugins::CodecSwitch::Plugin->setupPlayer($client);
        $params->{saved} = 1;
    }

    my @rows;
    for my $source (Plugins::CodecSwitch::Config->sources) {
        my $key = $source->{key};
        my ($options, $valid) = $class->_options_for($client, $key);
        my $value = Plugins::CodecSwitch::Config->mapping_value($client, $key);
        $value = 'direct' unless $valid->{$value};
        push @rows, {
            key     => $key,
            label   => $source->{label},
            value   => $value,
            options => $options,
        };
    }

    $params->{rows}     = \@rows;
    $params->{formats}  = join(', ', Plugins::CodecSwitch::Config->player_formats($client));
    $params->{warnings} = \@warnings;

    return $class->SUPER::handler($client, $params);
}

1;
