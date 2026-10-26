package Slim::Utils::Log;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw(logger logError logWarning logBacktrace);

sub logger {
    my ($name) = @_;
    return bless { name => $name // '' }, 'Slim::Utils::Log::Logger';
}

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
