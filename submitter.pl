#!/usr/bin/env perl -w
use strict;
use warnings;
use DateTime;
use Digest::SHA 'sha256';
use Fcntl ':flock';
use File::Copy 'cp';
use Getopt::Long;
use POSIX;
use feature 'say';

# The inbox and todo directory handling requires that
# only one copy of the submitter is running at a time.
INIT {
    open *{0}
        or die "$0: failed: $!";
    flock *{0}, LOCK_EX|LOCK_NB
        or die "$0 is already running\n";
}

# Pick up configuration.
my $root = 0;
my $destination = 0;
my $log = 0;

GetOptions(
    'root=s'        => \$root,
    'destination=s' => \$destination,
    'log=s'         => \$log)
    or die "$0: can't load options: $!";

if (!$root || !$destination) {
    if ($log) {
        debug("no configuration available, exiting");
    }
    die "$0: no configuration available, exiting";
}

my $inbox   = "$root/inbox";
my $todo    = "$root/todo";
my $outbox  = "$root/outbox";
my $success = "$root/success";
my $failure = "$root/failure";

debug("queueing data files for processing");
my $dh;
opendir ($dh, $inbox)
    or die "$0: can't open directory $inbox: $!";
foreach my $file (readdir $dh) {
    next if $file =~ /^\./;
    if (-f "$inbox/$file") {
        rename "$inbox/$file", "$todo/$file";
    }
}

debug("Processing data files");

my $source_digest = '';
my $target_digest = '';
opendir ($dh, $todo)
    or die "$0: can't open directory $todo: $!";
foreach my $file (readdir $dh) {
    next if $file =~ /^\./;
    if (-f "$todo/$file") {
        debug("Preparing to transfer $file");
        open (my $source_fh, '<', "$todo/$file")
            or die "$0: can't open file $todo/$file for input: $!";
            binmode $source_fh, ":encoding(UTF-8)";
        my $state = Digest::SHA->new(256);
        for (<$source_fh>) {
            $state->add($_);
        }
        $source_digest = $state->hexdigest;
        debug("Pre-transfer SHA256 checksum for $file: $source_digest");

        cp("$todo/$file", "$destination/$file");

        open (my $target_fg, '<', "$destination/$file")
            or die "$0: can't open file $destination/$file for input: $!";
            binmode $target_fg, ":encoding(UTF-8)";
        $state = Digest::SHA->new(256);
        for (<$target_fg>) {
            $state->add($_);
        }
        $target_digest = $state->hexdigest;
        debug("Post-transfer SHA256 checksum for $file: $target_digest");

        if ($target_digest eq $source_digest) {
            debug("Good, pre- and post-transfer SHA256 checksums match.  Creating control file");
            my $control = $file;
            $control =~ s/^d_/c_/;
            create_control_file("$destination/$control");
            if (-f "$destination/$control") {
                debug("Control file created");
                rename("$todo/$file", "$success/$file");
            }
            else {
                debug("Error, control file $destination/$control could not be created");
                rename("$todo/$file", "$failure/$file");
            }
        }
        else {
            debug("Error, pre- and post-transfer SHA256 checksums do not match");
            rename("$todo/$file", "$failure/$file");
        }
    }
}

sub debug {
    my (
        $message,
    ) = @_;

    open(my $log_fh, '>>', $log)
        or die "$0: can't open $log for appending: $!";

    my $datestring = strftime('[%Y-%m-%d %H:%M:%S %z]:', localtime());

    my @log_pieces = (
        'Submitter',
        $datestring,
        $message,
    );

    say $log_fh join(' ', @log_pieces);
}

sub create_control_file {
    my (
        $target,
    ) = @_;

    open (my $fh, '>', $target)
        or die "$0: can't open $target for truncation: $!";
    close($fh);
}
