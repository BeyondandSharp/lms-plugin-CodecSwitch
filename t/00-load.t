use strict;
use warnings;
use Test::More;

use lib 'lib', 't/lib';

use_ok('Plugins::CodecSwitch::Config');
use_ok('Plugins::CodecSwitch::CommandBuilder');
use_ok('Plugins::CodecSwitch::Toolchain');
use_ok('Plugins::CodecSwitch::Profiles');
use_ok('Plugins::CodecSwitch::Hooks');
use_ok('Plugins::CodecSwitch::Skip');
use_ok('Plugins::CodecSwitch::Settings');
use_ok('Plugins::CodecSwitch::PlayerSettings');
use_ok('Plugins::CodecSwitch::Plugin');

done_testing;
