package Plugins::CodecSwitch::Toolchain;

use strict;
use warnings;

use File::Basename qw(dirname);
use File::Path qw(mkpath);
use File::Spec;
use File::Spec::Functions qw(catdir catfile);

use Slim::Utils::Prefs;

use Plugins::CodecSwitch::Config;
use Plugins::CodecSwitch::CommandBuilder;

my $prefs = preferences('plugin.codecswitch');

my $ROOT = File::Spec->rel2abs(catdir(dirname(__FILE__), '..', '..', '..'));

my %BIN_CACHE;
my %PROBE_CACHE;
my $TOOLS_CACHE;
my $GATE_CACHE;
my $GATE_CACHE_SET = 0;

sub reset_cache {
    %BIN_CACHE   = ();
    %PROBE_CACHE = ();
    $TOOLS_CACHE = undef;
    $GATE_CACHE = undef;
    $GATE_CACHE_SET = 0;
    return 1;
}

sub _trim {
    my ($value) = @_;
    return '' unless defined $value;
    $value =~ s/^\s+|\s+$//g;
    return $value;
}

sub _which {
    my ($class, $name) = @_;
    return undef unless defined $name && length $name;

    if (eval { require Slim::Utils::Misc; 1 }) {
        my $found = eval { Slim::Utils::Misc::findbin($name) };
        return $found if $found && -x $found;
    }

    for my $dir (split /:/, $ENV{PATH} || '') {
        next unless length $dir;
        my $path = "$dir/$name";
        return $path if -x $path;
    }

    return undef;
}

sub bin {
    my ($class, $name) = @_;
    return $BIN_CACHE{$name} if exists $BIN_CACHE{$name};
    return $BIN_CACHE{$name} = undef unless defined $name && length $name;

    my $value = _trim($class->_pref_for_bin($name));
    my $path;
    if (length $value) {
        if (-x $value) {
            $path = $value;
        }
        else {
            # A stale or mistyped path falls back to auto-detection so a
            # bad preference does not silently disable all conversion.
            $path = $class->_which($name);
        }
    }
    else {
        $path = $class->_which($name);
    }

    return $BIN_CACHE{$name} = $path;
}

sub _pref_for_bin {
    my ($class, $name) = @_;
    return undef unless $name =~ /^(?:ffmpeg|flac|lame|sox|opusenc)$/;
    return $prefs->get($name);
}

sub _run {
    my ($class, $bin, @args) = @_;
    return undef unless $bin && -x $bin;

    my $fh;
    my $pid = eval { open($fh, '-|', $bin, @args) };
    return undef unless $pid;

    my $out = '';
    eval {
        local $SIG{ALRM} = sub { die "probe timeout\n" };
        alarm 5;
        local $/;
        $out = <$fh>;
        alarm 0;
        1;
    };
    alarm 0;
    close $fh;
    return $out;
}

sub _first_line {
    my ($text) = @_;
    return '' unless defined $text && length $text;
    my ($line) = split /\r?\n/, $text;
    $line = '' unless defined $line;
    $line =~ s/^\s+|\s+$//g;
    return $line;
}

sub probe {
    my ($class, $name) = @_;
    my $bin = $class->bin($name);
    return { ok => 0, path => '', version => '' }
        unless $bin;

    my @st = stat($bin);
    my $key = join('|', $name, $bin, $st[9] || 0, $st[7] || 0);
    return $PROBE_CACHE{$key} if $PROBE_CACHE{$key};

    my %probe = (
        ok      => 1,
        path    => $bin,
        version => '',
    );

    if ($name eq 'ffmpeg') {
        $probe{version} = _first_line($class->_run($bin, '-version'));
        my $encoders = $class->_run($bin, '-hide_banner', '-encoders') || '';
        my %enc;
        while ($encoders =~ /^\s*[A-Z.]{6}\s+(\S+)/mg) {
            $enc{$1} = 1;
        }
        $probe{encoders} = \%enc;
        my $filters = $class->_run($bin, '-hide_banner', '-filters') || '';
        $probe{soxr} = $filters =~ /\bsoxr\b/ ? 1 : 0;
    }
    else {
        $probe{version} = _first_line($class->_run($bin, '--version'));
        if (!$probe{version} && $name eq 'lame') {
            $probe{version} = _first_line($class->_run($bin, '-v'));
        }
    }

    $PROBE_CACHE{$key} = \%probe;
    return \%probe;
}

sub tools {
    my ($class) = @_;
    return $TOOLS_CACHE if $TOOLS_CACHE;
    my %tools;
    for my $name (qw(ffmpeg flac lame sox opusenc)) {
        my $probe = $class->probe($name);
        $tools{$name} = $probe->{path} if $probe->{ok} && $probe->{path};
    }
    return $TOOLS_CACHE = \%tools;
}

sub ffmpeg_encoder_ok {
    my ($class, $target) = @_;
    return 0 unless $target && $target->{ffmpeg_encoder};
    my $probe = $class->probe('ffmpeg');
    return 0 unless $probe->{ok} && $probe->{encoders};
    return $probe->{encoders}{ $target->{ffmpeg_encoder} } ? 1 : 0;
}

sub native_ok {
    my ($class, $source, $target) = @_;
    return 0 unless $target && $target->{native};
    return 0 unless Plugins::CodecSwitch::CommandBuilder->native_source_ok($source);

    my $tools = $class->tools;
    return 0 unless $tools->{sox};

    my $native = $target->{native};
    if ($native eq 'flc') {
        return $tools->{flac} ? 1 : 0;
    }
    if ($native eq 'mp3') {
        return $tools->{lame} ? 1 : 0;
    }
    if ($native eq 'ops') {
        return $tools->{opusenc} ? 1 : 0;
    }
    return 1;
}

sub backend_pref {
    my ($class, $target) = @_;
    my $value = $prefs->get('backend_' . $target->{key});
    $value = 'auto' unless defined $value && $value =~ /^(?:auto|ffmpeg|native)$/;
    return $value;
}

sub _gate {
    my ($class) = @_;
    return $GATE_CACHE if $GATE_CACHE_SET;
    $GATE_CACHE_SET = 1;

    return $GATE_CACHE = undef if $^O eq 'MSWin32';

    my $max = $prefs->get('max_jobs') || 0;
    return $GATE_CACHE = undef unless $max =~ /^\d+$/ && $max > 0;
    $max = 64 if $max > 64;

    my $gate = $class->gate_bin or return $GATE_CACHE = undef;
    my $flock = $class->_which('flock') or return $GATE_CACHE = undef;

    my $dir = $class->lock_dir;
    mkpath($dir, 0, 0755) unless -d $dir;
    return $GATE_CACHE = undef unless -d $dir && -w $dir;

    return $GATE_CACHE = {
        bin => $gate,
        max => int($max),
        dir => $dir,
    };
}

sub gate_bin {
    my ($class) = @_;
    my $path = catfile($ROOT, 'Bin', 'codecswitch-gate');
    return -x $path ? $path : undef;
}

sub lock_dir {
    my ($class) = @_;
    my $cachedir;
    if (eval { require Slim::Utils::Prefs; 1 }) {
        my $server = eval { preferences('server') };
        $cachedir = eval { $server->get('cachedir') } if $server;
    }
    $cachedir ||= File::Spec->tmpdir;
    return catdir($cachedir, 'codecswitch-locks');
}

sub resampler {
    my ($class) = @_;
    my $probe = $class->probe('ffmpeg');
    return $probe->{soxr} ? 'soxr' : 'swr';
}

sub _candidates {
    my ($class, $source, $target, $remote) = @_;
    return ('ffmpeg') if $remote;
    return ('ffmpeg') unless $target->{native};

    my $pref = $class->backend_pref($target);
    return ('native', 'ffmpeg') if $pref eq 'auto';
    return ($pref, $pref eq 'native' ? 'ffmpeg' : 'native');
}

sub plan {
    my ($class, $client, $source, $target_key, $remote) = @_;
    my $target = Plugins::CodecSwitch::Config->target_by_key($target_key) or return undef;
    my $resolved = Plugins::CodecSwitch::Config->resolve_target($client, $target_key) or return undef;
    my $lms_format = $resolved->{lms_format};

    if ($lms_format eq $source) {
        return Plugins::CodecSwitch::CommandBuilder->direct_plan({
            source     => $source,
            target     => $target_key,
            lms_format => $lms_format,
            remote     => $remote,
        });
    }

    my $tools = $class->tools;
    my $gate = $class->_gate;
    my %seen;

    for my $backend ($class->_candidates($source, $target, $remote)) {
        next if $seen{$backend}++;
        my $plan;
        if ($backend eq 'ffmpeg') {
            next unless $class->ffmpeg_encoder_ok($target);
            $plan = Plugins::CodecSwitch::CommandBuilder->ffmpeg_plan({
                source     => $source,
                target     => $target,
                lms_format => $lms_format,
                tools      => $tools,
                remote     => $remote,
                resampler  => $class->resampler,
                gate       => $gate,
            });
        }
        else {
            next unless $class->native_ok($source, $target);
            $plan = Plugins::CodecSwitch::CommandBuilder->native_plan({
                source     => $source,
                target     => $target,
                lms_format => $lms_format,
                tools      => $tools,
                gate       => $gate,
            });
        }
        return $plan if $plan;
    }

    return undef;
}

sub _post_candidates {
    my ($class, $input_format, $target) = @_;
    return ('ffmpeg') unless $target->{native};
    my $pref = $class->backend_pref($target);
    return ('native', 'ffmpeg') if $pref eq 'auto';
    return ($pref, $pref eq 'native' ? 'ffmpeg' : 'native');
}

sub post_plan {
    my ($class, $client, $target_key, $input_format) = @_;
    my $target = Plugins::CodecSwitch::Config->target_by_key($target_key) or return undef;
    my $resolved = Plugins::CodecSwitch::Config->resolve_target($client, $target_key) or return undef;
    return undef if $resolved->{lms_format} eq $input_format;

    my $tools = $class->tools;
    my $gate = $class->_gate;
    my %seen;

    for my $backend ($class->_post_candidates($input_format, $target)) {
        next if $seen{$backend}++;
        my $plan;
        if ($backend eq 'ffmpeg') {
            next unless $class->ffmpeg_encoder_ok($target);
            $plan = Plugins::CodecSwitch::CommandBuilder->ffmpeg_pipe_plan({
                source       => $input_format,
                target       => $target,
                lms_format   => $resolved->{lms_format},
                input_format => $input_format,
                tools        => $tools,
                gate         => $gate,
            });
        }
        else {
            next unless $class->native_ok($input_format, $target);
            $plan = Plugins::CodecSwitch::CommandBuilder->native_pipe_plan({
                source       => $input_format,
                target       => $target,
                lms_format   => $resolved->{lms_format},
                input_format => $input_format,
                tools        => $tools,
                gate         => $gate,
            });
        }
        return $plan if $plan;
    }

    return undef;
}

sub sacd_flc_available {
    my ($class, $client, $source) = @_;
    return 0 unless Plugins::CodecSwitch::Config->sacd_enabled;
    return 0 unless Plugins::CodecSwitch::Config->is_dsd_source($source);
    return 0 unless $client;

    my $id = eval { $client->id } || eval { $client->macaddress } || '';
    return 0 unless length $id;

    if (eval { require Slim::Player::TranscodingHelper; 1 }) {
        my $table  = eval { Slim::Player::TranscodingHelper::Conversions() } || {};
        my $player = eval { $client->model } || '';
        for my $profile (
            "$source-flc-*-$id",
            "$source-flc-$player-$id",
            "$source-flc-*-*",
        ) {
            return 1 if $table->{$profile};
        }
    }

    # SACD profiles may not have been registered yet on first playback; if
    # SACDPlayer has an ffmpeg binary it can produce the intermediate FLAC.
    my $ffmpeg = eval {
        require Plugins::SACDPlayer::Transcoder;
        Plugins::SACDPlayer::Transcoder->ffmpeg_bin;
    };
    return $ffmpeg ? 1 : 0;
}

sub target_available {
    my ($class, $client, $source, $target_key) = @_;
    return 0 unless $client && $source && $target_key;

    my $resolved = Plugins::CodecSwitch::Config->resolve_target($client, $target_key)
        or return 0;

    if (Plugins::CodecSwitch::Config->is_dsd_source($source)
        && Plugins::CodecSwitch::Config->sacd_enabled) {
        return 0 unless $class->sacd_flc_available($client, $source);
        return 1 if $resolved->{lms_format} eq 'flc';
        return 1 if $class->post_plan($client, $target_key, 'flc');
        return 0;
    }

    return 1 if $class->plan($client, $source, $target_key, 0);
    return 1 if $class->plan($client, $source, $target_key, 1);
    return 0;
}

sub status {
    my ($class) = @_;
    my @status;

    my @tools = (
        ['ffmpeg',  'FFmpeg'],
        ['flac',    'FLAC encoder'],
        ['lame',    'LAME encoder'],
        ['sox',     'SoX'],
        ['opusenc', 'opusenc'],
    );

    for my $spec (@tools) {
        my ($name, $label) = @$spec;
        my $probe = $class->probe($name);
        my $detail = '';
        if ($probe->{ok} && $name eq 'ffmpeg') {
            $detail = $probe->{soxr} ? 'soxr available' : 'swr only';
            my $count = $probe->{encoders} ? scalar keys %{ $probe->{encoders} } : 0;
            $detail .= ", $count encoders";
        }
        push @status, {
            name    => $name,
            label   => $label,
            ok      => $probe->{ok} ? 1 : 0,
            path    => $probe->{path} || '',
            version => $probe->{version} || '',
            detail  => $detail,
        };
    }

    my $flock = $class->_which('flock');
    push @status, {
        name    => 'flock',
        label   => 'flock (worker limit)',
        ok      => $flock ? 1 : 0,
        path    => $flock || '',
        version => '',
        detail  => $flock ? '' : 'worker limit unavailable',
    };

    my $gate = $class->gate_bin;
    push @status, {
        name    => 'gate',
        label   => 'Concurrency gate',
        ok      => $gate ? 1 : 0,
        path    => $gate || '',
        version => '',
        detail  => ($gate && $flock && $^O ne 'MSWin32')
            ? 'available'
            : 'worker limit unavailable',
    };

    return \@status;
}

1;
