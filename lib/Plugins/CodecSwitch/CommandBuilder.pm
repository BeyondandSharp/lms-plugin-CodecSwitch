package Plugins::CodecSwitch::CommandBuilder;

use strict;
use warnings;

my %NATIVE_SOURCE = map { $_ => 1 } qw(
    aif flc mp3 ogf ogg ops wav wv wvp
);

sub native_source_ok {
    my ($class, $source) = @_;
    return $NATIVE_SOURCE{$source} ? 1 : 0;
}

sub quote_bin {
    my ($class, $path) = @_;
    return '' unless defined $path && length $path;
    $path =~ s/\\/\\\\/g;
    $path =~ s/"/\\"/g;
    $path =~ s/\$/\\\$/g;
    $path =~ s/`/\\`/g;
    return '"' . $path . '"';
}

sub _resample_filter {
    my ($class, $resampler) = @_;
    $resampler = 'swr' unless defined $resampler && $resampler =~ /^(?:swr|soxr)$/;
    return $resampler eq 'soxr'
        ? 'aresample=resampler=soxr:precision=28:osr=%d'
        : 'aresample=resampler=swr:osr=%d';
}

sub ffmpeg_plan {
    my ($class, $args) = @_;
    my $target = $args->{target} or return undef;
    my $tools  = $args->{tools}  || {};
    my $ffmpeg = $tools->{ffmpeg} or return undef;
    my $remote = $args->{remote} ? 1 : 0;

    my $input = $remote ? '$URL$' : '$FILE$';
    my $filter = $class->_resample_filter($args->{resampler});

    my $caps = {
        ($remote ? (R => 'noArgs') : (F => 'noArgs')),
        T => 'START=-ss %s',
        U => 'END=-t %w',
        D => 'RESAMPLE=-af ' . $filter,
    };

    my $caps_b = $target->{bitrate} ? { B => 'BITRATE=-b:a %Bk' } : {};
    $caps = { %$caps, %$caps_b };

    my $command = $class->quote_bin($ffmpeg)
        . ' -nostdin -hide_banner -loglevel error'
        . ' $START$ -i ' . $input . ' $END$'
        . ' -map 0:a:0 -vn -sn -dn $RESAMPLE$'
        . ' -c:a ' . $target->{ffmpeg_encoder};
    $command .= ' ' . $target->{ffmpeg_args}
        if defined $target->{ffmpeg_args} && length $target->{ffmpeg_args};
    if ($args->{bitrate} && $target->{bitrate}) {
        $command .= ' -b:a ' . int($args->{bitrate}) . 'k';
    }
    elsif ($target->{bitrate}) {
        $command .= ' $BITRATE$';
    }
    $command .= ' -f ' . $target->{ffmpeg_container} . ' -';

    return {
        command      => $command,
        capabilities => $caps,
        backend      => 'ffmpeg',
        lms_format   => $args->{lms_format} || $target->{formats}[0],
        target       => $target->{key},
        source       => $args->{source},
        remote       => $remote,
    };
}

sub native_plan {
    my ($class, $args) = @_;
    my $target = $args->{target} or return undef;
    my $source = $args->{source} or return undef;
    my $tools  = $args->{tools}  || {};
    my $sox    = $tools->{sox}    or return undef;

    return undef if $args->{remote};
    return undef unless $class->native_source_ok($source);
    return undef unless $target->{native};
    return undef unless $args->{lms_format};

    my $caps = {
        F => 'noArgs',
        D => 'RESAMPLE=rate -v %d',
    };
    $caps->{B} = $target->{native_bitrate} if $target->{native_bitrate};

    my $sox_cmd = $class->quote_bin($sox)
        . ' -q $FILE$ -t wav - $RESAMPLE$';

    my $command;
    if ($target->{native} eq 'flc') {
        my $flac = $tools->{flac} or return undef;
        $command = $sox_cmd . ' | '
            . $class->quote_bin($flac) . ' -cs --totally-silent -';
    }
    elsif ($target->{native} eq 'mp3') {
        my $lame = $tools->{lame} or return undef;
        $command = $sox_cmd . ' | '
            . $class->quote_bin($lame) . ' --silent --abr 192 $BITRATE$ - -';
    }
    elsif ($target->{native} eq 'ops') {
        my $opusenc = $tools->{opusenc} or return undef;
        $command = $sox_cmd . ' | '
            . $class->quote_bin($opusenc) . ' --quiet --bitrate 128 $BITRATE$ - -';
    }
    elsif ($target->{native} eq 'wav') {
        $command = $class->quote_bin($sox) . ' -q $FILE$ -t wav - $RESAMPLE$';
    }
    elsif ($target->{native} eq 'aif') {
        # LMS's "aif" stream format is raw big-endian PCM when it comes from
        # a transcoder (core flc->aif does the same), not an AIFF container.
        $command = $class->quote_bin($sox) . ' -q $FILE$ -t raw -e signed -b 16 -B - $RESAMPLE$';
    }
    elsif ($target->{native} eq 'ogg') {
        $command = $class->quote_bin($sox) . ' -q $FILE$ -t ogg -C 5 - $RESAMPLE$';
    }
    else {
        return undef;
    }

    return {
        command      => $command,
        capabilities => $caps,
        backend      => 'native',
        lms_format   => $args->{lms_format},
        target       => $target->{key},
        source       => $source,
        remote       => 0,
    };
}

sub ffmpeg_pipe_plan {
    my ($class, $args) = @_;
    my $target = $args->{target} or return undef;
    my $tools  = $args->{tools}  || {};
    my $ffmpeg = $tools->{ffmpeg} or return undef;
    my $input  = $args->{input_format} || '';

    my %input_spec = (
        flc => '-f flac -i -',
        wav => '-f wav -i -',
        dff => '-f iff -i -',
        pcm => '-f ' . ($args->{input_sample_fmt} || 's16le') . ' -ar ' . ($args->{input_rate} || 44100) . ' -ac ' . ($args->{input_channels} || 2) . ' -i -',
    );
    my $input_spec = $input_spec{$input} or return undef;

    my $command = $class->quote_bin($ffmpeg)
        . ' -hide_banner -loglevel error '
        . $input_spec
        . ' -map 0:a:0 -vn -sn -dn'
        . ' -c:a ' . $target->{ffmpeg_encoder};
    $command .= ' ' . $target->{ffmpeg_args}
        if defined $target->{ffmpeg_args} && length $target->{ffmpeg_args};
    $command .= ' -b:a ' . int($args->{bitrate}) . 'k'
        if $args->{bitrate} && $target->{bitrate};
    $command .= ' -f ' . $target->{ffmpeg_container} . ' -';

    return {
        command      => $command,
        capabilities => {},
        backend      => 'ffmpeg',
        lms_format   => $args->{lms_format} || $target->{formats}[0],
        target       => $target->{key},
        input_format => $input,
        post         => 1,
    };
}

sub native_pipe_plan {
    my ($class, $args) = @_;
    my $target = $args->{target} or return undef;
    my $tools  = $args->{tools}  || {};
    my $sox    = $tools->{sox}    or return undef;
    my $input  = $args->{input_format} || '';

    my %input_spec = (
        flc => '-t flac -',
        wav => '-t wav -',
        pcm => '-t raw -e signed -b ' . (($args->{input_sample_fmt} || '') =~ /^s24/ ? 24 : 16) . ' -r ' . ($args->{input_rate} || 44100) . ' -c ' . ($args->{input_channels} || 2) . ' -',
    );
    my $input_spec = $input_spec{$input} or return undef;

    my $sox_cmd = $class->quote_bin($sox) . ' -q ' . $input_spec;

    my $command;
    if ($target->{native} eq 'flc') {
        my $flac = $tools->{flac} or return undef;
        $command = $sox_cmd . ' -t wav - | '
            . $class->quote_bin($flac) . ' -cs --totally-silent -';
    }
    elsif ($target->{native} eq 'mp3') {
        my $lame = $tools->{lame} or return undef;
        $command = $sox_cmd . ' -t wav - | '
            . $class->quote_bin($lame) . ' --silent --abr ' . ($args->{bitrate} || 192) . ' - -';
    }
    elsif ($target->{native} eq 'ops') {
        my $opusenc = $tools->{opusenc} or return undef;
        $command = $sox_cmd . ' -t wav - | '
            . $class->quote_bin($opusenc) . ' --quiet --bitrate ' . ($args->{bitrate} || 128) . ' - -';
    }
    elsif ($target->{native} eq 'wav') {
        $command = $class->quote_bin($sox) . ' -q ' . $input_spec . ' -t wav -';
    }
    elsif ($target->{native} eq 'aif') {
        $command = $class->quote_bin($sox) . ' -q ' . $input_spec
            . ' -t raw -e signed -b 16 -B -';
    }
    elsif ($target->{native} eq 'ogg') {
        $command = $class->quote_bin($sox) . ' -q ' . $input_spec . ' -t ogg -C 5 -';
    }
    else {
        return undef;
    }

    return {
        command      => $command,
        capabilities => {},
        backend      => 'native',
        lms_format   => $args->{lms_format} || $target->{formats}[0],
        target       => $target->{key},
        input_format => $input,
        post         => 1,
    };
}

sub direct_plan {
    my ($class, $args) = @_;
    return {
        command      => '-',
        capabilities => { I => 'noArgs', F => 'noArgs', R => 'noArgs' },
        backend      => 'direct',
        lms_format   => $args->{lms_format},
        target       => $args->{target},
        source       => $args->{source},
        remote       => $args->{remote} ? 1 : 0,
        direct       => 1,
    };
}

1;
