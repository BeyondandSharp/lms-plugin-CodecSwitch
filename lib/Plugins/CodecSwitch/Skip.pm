package Plugins::CodecSwitch::Skip;

use strict;
use warnings;

use Time::HiRes ();

use Slim::Utils::Log;
use Slim::Utils::Prefs;

use Plugins::CodecSwitch::Config;

my $log = logger('plugin.codecswitch');
my $prefs = preferences('plugin.codecswitch');

my $installed = 0;
my %LAST_DELETE;
my $LOOKAHEAD = 5;

sub install {
    my ($class) = @_;
    return 1 if $installed;

    return 0 unless eval { require Slim::Control::Request; 1 };
    Slim::Control::Request::subscribe(
        \&on_newsong,
        [ ['playlist'], ['newsong'] ],
    );
    $installed = 1;
    return 1;
}

sub uninstall {
    my ($class) = @_;
    return 1 unless $installed;
    if (eval { require Slim::Control::Request; 1 }) {
        eval { Slim::Control::Request::unsubscribe(\&on_newsong) };
    }
    $installed = 0;
    return 1;
}

sub _client_id {
    my ($client) = @_;
    return eval { $client->id } || eval { $client->macaddress } || "$client";
}

sub _delete_track {
    my ($class, $client, $track, $source) = @_;
    my $url = eval { $track->url } || return 0;
    my $key = _client_id($client) . '|' . $url;

    my $now = Time::HiRes::time();
    if ($LAST_DELETE{$key} && $now - $LAST_DELETE{$key} < 5) {
        return 0;
    }
    $LAST_DELETE{$key} = $now;

    my $ok = eval {
        $client->execute([ 'playlist', 'deleteitem', $url ]);
        1;
    };
    if ($ok) {
        $log->info("skipped $source track: $url");
        return 1;
    }

    $log->warn("failed to skip $source track: $url: $@");
    return 0;
}

sub on_newsong {
    my ($request) = @_;
    return unless $request;

    my $client = eval { $request->client } || return;
    my $master = eval { $client->masterOrSelf } || eval { $client->master } || $client;
    return unless $master;

    return 0 unless eval { require Slim::Player::Playlist; 1 };

    my $track = eval { Slim::Player::Playlist::track($master) } || return;
    my $decision = Plugins::CodecSwitch::Config->decision($track, $master);

    if ($decision->{action} eq 'skip') {
        return __PACKAGE__->delete_track($master, $track, $decision->{source});
    }

    # Remove upcoming skipped tracks so LMS does not preload them.  Collect
    # URLs first because deleting changes playlist indexes.
    my $base = 0;
    if (eval { require Slim::Player::Source; 1 }) {
        $base = eval { Slim::Player::Source::playingSongIndex($master) };
        $base = 0 unless defined $base && $base >= 0;
    }

    my @urls;
    for my $offset (1 .. $LOOKAHEAD) {
        my $next = eval { Slim::Player::Playlist::track($master, $base + $offset) } || last;
        my $next_decision = Plugins::CodecSwitch::Config->decision($next, $master);
        next unless $next_decision->{action} eq 'skip';
        my $url = eval { $next->url } || next;
        push @urls, [ $url, $next_decision->{source} ];
    }

    my $count = 0;
    for my $item (@urls) {
        my ($url, $source) = @$item;
        my $key = _client_id($master) . '|' . $url;
        my $now = Time::HiRes::time();
        next if $LAST_DELETE{$key} && $now - $LAST_DELETE{$key} < 5;
        $LAST_DELETE{$key} = $now;
        my $ok = eval {
            $master->execute([ 'playlist', 'deleteitem', $url ]);
            1;
        };
        if ($ok) {
            $log->info("removed upcoming $source track: $url");
            $count++;
        }
        else {
            $log->warn("failed to remove upcoming $source track: $url: $@");
        }
    }

    return $count;
}

# Kept as a class method so tests can call it without a live LMS request.
sub delete_track {
    my ($class, $client, $track, $source) = @_;
    $source = Plugins::CodecSwitch::Config->source_for_track($track) unless defined $source;
    $source = 'unknown' unless defined $source && length $source;
    return _delete_track($class, $client, $track, $source);
}

1;
