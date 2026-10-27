package Slim::Utils::Log;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw(logger logError logWarning logBacktrace);

our %CATEGORIES;
our %LEVELS;
our $PERSIST = 0;

sub logger {
    my ($name) = @_;
    return bless { name => $name // '' }, 'Slim::Utils::Log::Logger';
}

sub addLogCategory {
    my ($class, $args) = @_;
    my $category = $args->{category} or return;
    $CATEGORIES{$category} = $args;
    $LEVELS{$category} = $args->{defaultLevel} || 'ERROR'
        unless exists $LEVELS{$category};
    return logger($category);
}

sub setLogLevelForCategory {
    my ($class, $category, $level) = @_;
    return 0 unless defined $category && defined $level;
    $LEVELS{$category} = $level;
    return 1;
}

sub allCategories {
    my ($class) = @_;
    return { %LEVELS };
}

sub persist {
    my ($class, $value) = @_;
    $PERSIST = $value ? 1 : 0 if defined $value;
    return $PERSIST;
}

sub reInit { return 1 }

sub logError   { return 1 }
sub logWarning { return 1 }
sub logBacktrace { return 1 }

package Slim::Utils::Log::Logger;

sub debug { return 1 }
sub info  { return 1 }
sub warn  { return 1 }
sub error { return 1 }
sub is_debug { return 0 }
sub is_info  { return 0 }

1;
