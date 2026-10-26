package Plugins::CodecSwitch::Config;

use strict;
use warnings;

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.codecswitch');

our $DIRECT = 'direct';
our $SKIP   = 'skip';

# Source formats shown in the player settings page.  Keys are LMS content
# types, not file extensions.
our @SOURCES = (
    { key => 'aac',  label => 'AAC' },
    { key => 'aif',  label => 'AIFF' },
    { key => 'alc',  label => 'ALAC' },
    { key => 'ape',  label => 'APE' },
    { key => 'dff',  label => 'DFF (DSD)' },
    { key => 'dsf',  label => 'DSF (DSD)' },
    { key => 'flc',  label => 'FLAC' },
    { key => 'mp3',  label => 'MP3' },
    { key => 'mp4',  label => 'M4A' },
    { key => 'mpc',  label => 'Musepack' },
    { key => 'ogg',  label => 'Ogg Vorbis' },
    { key => 'ogf',  label => 'Ogg FLAC' },
    { key => 'ops',  label => 'Opus' },
    { key => 'shn',  label => 'Shorten' },
    { key => 'sls',  label => 'SLS' },
    { key => 'wav',  label => 'WAV' },
    { key => 'wma',  label => 'WMA' },
    { key => 'wmal', label => 'WMA Lossless' },
    { key => 'wmap', label => 'WMA Pro' },
    { key => 'wvp',  label => 'WavPack' },
    { key => 'wvpx', label => 'WavPack DSD' },
);

# Target formats.  A target is only offered when the player reports one of
# its "formats" and a usable encoder is available.
our @TARGETS = (
    {
        key              => 'flc',
        label            => 'FLAC',
        formats          => ['flc'],
        ffmpeg_encoder   => 'flac',
        ffmpeg_args      => '-compression_level 5',
        ffmpeg_container => 'flac',
        native           => 'flc',
    },
    {
        key              => 'wav',
        label            => 'WAV',
        formats          => ['wav'],
        ffmpeg_encoder   => 'pcm_s16le',
        ffmpeg_args      => '',
        ffmpeg_container => 'wav',
        native           => 'wav',
    },
    {
        key              => 'aif',
        label            => 'AIFF',
        formats          => ['aif'],
        ffmpeg_encoder   => 'pcm_s16be',
        ffmpeg_args      => '',
        ffmpeg_container => 's16be',
        native           => 'aif',
    },
    {
        key              => 'mp3',
        label            => 'MP3',
        formats          => ['mp3'],
        ffmpeg_encoder   => 'libmp3lame',
        ffmpeg_args      => '-q:a 2',
        ffmpeg_container => 'mp3',
        native           => 'mp3',
    },
    {
        key              => 'aac',
        label            => 'AAC',
        formats          => ['aac'],
        ffmpeg_encoder   => 'aac',
        ffmpeg_args      => '-b:a 256k',
        ffmpeg_container => 'adts',
        native           => undef,
    },
    {
        key              => 'ogg',
        label            => 'Ogg Vorbis',
        formats          => ['ogg'],
        ffmpeg_encoder   => 'libvorbis',
        ffmpeg_args      => '-q:a 5',
        ffmpeg_container => 'ogg',
        native           => 'ogg',
    },
    {
        key              => 'ops',
        label            => 'Opus',
        formats          => ['ops'],
        ffmpeg_encoder   => 'libopus',
        ffmpeg_args      => '-b:a 128k',
        ffmpeg_container => 'ogg',
        native           => 'ops',
    },
    {
        key              => 'alc',
        label            => 'ALAC (experimental)',
        formats          => ['alc'],
        ffmpeg_encoder   => 'alac',
        ffmpeg_args      => '-movflags +frag_keyframe+empty_moov',
        ffmpeg_container => 'mp4',
        native           => undef,
        experimental     => 1,
    },
);

my %SOURCE_BY_KEY = map { $_->{key} => $_ } @SOURCES;
my %TARGET_BY_KEY = map { $_->{key} => $_ } @TARGETS;
my %VALID_VALUE   = (
    $DIRECT => 1,
    $SKIP   => 1,
    map({ $_->{key} => 1 } @TARGETS),
);

my %MAPPING_CACHE;

sub sources        { return @SOURCES }
sub targets        { return @TARGETS }
sub source_by_key  { return $SOURCE_BY_KEY{ $_[1] } }
sub target_by_key  { return $TARGET_BY_KEY{ $_[1] } }
sub valid_value    { return $VALID_VALUE{ $_[1] } ? 1 : 0 }

sub is_remote {
    my ($class, $track) = @_;
    my $url = eval { $track->url } || '';
    return 0 unless $url;
    if (eval { require Slim::Music::Info; 1 }) {
        return Slim::Music::Info::isRemoteURL($url) ? 1 : 0;
    }
    return $url =~ m{^(?:https?|ftp|mms)://}i ? 1 : 0;
}

sub source_for_track {
    my ($class, $track) = @_;
    return undef unless $track;

    my $type = eval { $track->content_type };
    if (!defined $type || !length $type) {
        $type = eval { Slim::Music::Info::contentType($track) };
    }
    if (defined $type) {
        $type = lc $type;
        $type =~ s/\s+//g;
        return $SOURCE_BY_KEY{$type} ? $type : undef;
    }

    my $url = eval { $track->url } || '';
    if ($url =~ /\.([a-z0-9]+)(?:[?#].*)?$/i) {
        my $ext = lc $1;
        my %alias = (
            aiff => 'aif',
            flac => 'flc',
            m4a  => 'mp4',
            opus => 'ops',
            wv   => 'wvp',
        );
        my $candidate = $alias{$ext} || $ext;
        return $candidate if $SOURCE_BY_KEY{$candidate};
    }

    return undef;
}

sub player_formats {
    my ($class, $client) = @_;
    return () unless $client;

    my @formats;
    if (eval { require Slim::Player::CapabilitiesHelper; 1 }) {
        @formats = eval { Slim::Player::CapabilitiesHelper::supportedFormats($client) };
    }
    if (!@formats && $client->can('formats')) {
        @formats = eval { $client->formats };
    }

    my %seen;
    return grep { defined $_ && length $_ && !$seen{$_}++ } @formats;
}

sub resolve_target {
    my ($class, $client, $target_key) = @_;
    my $target = $TARGET_BY_KEY{$target_key} or return undef;

    my %formats = map { $_ => 1 } $class->player_formats($client);
    for my $format (@{ $target->{formats} }) {
        next unless $formats{$format};
        return {
            %$target,
            lms_format => $format,
        };
    }

    return undef;
}

sub mapping_for {
    my ($class, $client) = @_;
    return {} unless $client;
    my $id = eval { $client->id } || eval { $client->macaddress } || "$client";
    return $MAPPING_CACHE{$id} if $MAPPING_CACHE{$id};

    my $raw = eval { $prefs->client($client)->get('mapping') };
    my %mapping;
    if (ref $raw eq 'HASH') {
        for my $source (keys %$raw) {
            next unless $SOURCE_BY_KEY{$source};
            my $value = $raw->{$source};
            next unless defined $value && $VALID_VALUE{$value};
            $mapping{$source} = $value;
        }
    }

    $MAPPING_CACHE{$id} = \%mapping;
    return \%mapping;
}

sub mapping_value {
    my ($class, $client, $source) = @_;
    my $mapping = $class->mapping_for($client);
    return $mapping->{$source} || $DIRECT;
}

sub decision {
    my ($class, $track, $client) = @_;
    my $source = $class->source_for_track($track);

    return { action => $DIRECT, source => $source }
        unless $source && $client;

    my $value = $class->mapping_value($client, $source);
    if ($value eq $SKIP) {
        return { action => $SKIP, source => $source };
    }
    if ($value ne $DIRECT && $TARGET_BY_KEY{$value}) {
        return {
            action => 'target',
            source => $source,
            target => $value,
        };
    }

    return { action => $DIRECT, source => $source };
}

sub normalize_mapping {
    my ($class, $raw, $allowed_targets) = @_;
    $raw = {} unless ref $raw eq 'HASH';
    $allowed_targets ||= {};

    my %mapping;
    for my $source (keys %SOURCE_BY_KEY) {
        my $value = $raw->{$source};
        $value = $DIRECT unless defined $value && $VALID_VALUE{$value};
        if ($value ne $DIRECT && $value ne $SKIP) {
            $value = $DIRECT unless $allowed_targets->{$value};
        }
        $mapping{$source} = $value;
    }
    return \%mapping;
}

sub invalidate {
    my ($class, $client) = @_;
    return unless $client;
    my $id = eval { $client->id } || eval { $client->macaddress } || "$client";
    delete $MAPPING_CACHE{$id};
    return 1;
}

sub clear_cache {
    %MAPPING_CACHE = ();
    return 1;
}

1;
