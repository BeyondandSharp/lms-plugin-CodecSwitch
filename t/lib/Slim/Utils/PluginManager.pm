package Slim::Utils::PluginManager;

use strict;
use warnings;

our %ENABLED;

sub reset {
    %ENABLED = ();
    return 1;
}

sub set_enabled {
    my ($class, $module, $value) = @_;
    if ($value) {
        $ENABLED{$module} = { name => $module };
    }
    else {
        delete $ENABLED{$module};
    }
    return 1;
}

sub isEnabled {
    my ($class, $module) = @_;
    return $ENABLED{$module};
}

1;
