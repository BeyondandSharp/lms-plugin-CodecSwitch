package Plugins::CodecSwitch::Settings;

use strict;
use warnings;

use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;
use Slim::Web::HTTP::CSRF;

use Plugins::CodecSwitch::Config;
use Plugins::CodecSwitch::Profiles;
use Plugins::CodecSwitch::Toolchain;

my $prefs = preferences('plugin.codecswitch');

my @BACKEND_TARGETS = qw(flc wav aif mp3 ogg ops);
my @TOOL_KEYS       = qw(ffmpeg flac lame sox opusenc);

sub name {
    return Slim::Web::HTTP::CSRF->protectName('PLUGIN_CODECSWITCH');
}

sub page {
    return Slim::Web::HTTP::CSRF->protectURI('plugins/CodecSwitch/settings/basic.html');
}

sub _clean_path {
    my ($value) = @_;
    return '' unless defined $value;
    $value =~ s/^\s+|\s+$//g;
    return '' if $value =~ /[\r\n\0]/;
    return $value;
}

sub handler {
    my ($class, $client, $params, $callback, @args) = @_;

    my @warnings;

    if ($params->{saveSettings}) {
        for my $key (@TOOL_KEYS) {
            my $value = _clean_path($params->{"pref_$key"});
            if (length $value && !-x $value && $value =~ m{[/\\]}) {
                push @warnings, { token => 'PLUGIN_CODECSWITCH_WARN_TOOL', detail => $key };
            }
            $prefs->set($key, $value);
        }

        for my $key (@BACKEND_TARGETS) {
            my $value = $params->{"pref_backend_$key"} || 'auto';
            if ($value !~ /^(?:auto|ffmpeg|native)$/) {
                push @warnings, { token => 'PLUGIN_CODECSWITCH_WARN_BACKEND', detail => $key };
                $value = 'auto';
            }
            $prefs->set("backend_$key", $value);
        }

        Plugins::CodecSwitch::Toolchain->reset_cache;
        Plugins::CodecSwitch::Profiles->setup_all;
        $params->{saved} = 1;
    }

    my @backends;
    for my $key (@BACKEND_TARGETS) {
        my $target = Plugins::CodecSwitch::Config->target_by_key($key) or next;
        my $value  = $prefs->get("backend_$key") || 'auto';
        $value = 'auto' unless $value =~ /^(?:auto|ffmpeg|native)$/;
        push @backends, {
            key   => $key,
            label => $target->{label},
            value => $value,
        };
    }

    $params->{prefs} = {
        map { $_ => ($prefs->get($_) || '') } @TOOL_KEYS,
    };
    $params->{tools}    = Plugins::CodecSwitch::Toolchain->status;
    $params->{backends} = \@backends;
    $params->{warnings} = \@warnings;

    return $class->SUPER::handler($client, $params);
}

1;
