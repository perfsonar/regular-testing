package perfSONAR_PS::RegularTesting::Tests::Bwctl;

use strict;
use warnings;

our $VERSION = 3.4;

use IPC::Run qw( start pump );
use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);
use File::Temp qw(tempdir);

use perfSONAR_PS::RegularTesting::Parsers::Bwctl qw(parse_bwctl_output);

use Moose;

extends 'perfSONAR_PS::RegularTesting::Tests::Base';

has 'bwctl_cmd' => (is => 'rw', isa => 'Str', default => '/usr/bin/bwctl');
has 'tool' => (is => 'rw', isa => 'Str');
has 'force_ipv4' => (is => 'rw', isa => 'Bool');
has 'force_ipv6' => (is => 'rw', isa => 'Bool');
has 'use_udp' => (is => 'rw', isa => 'Bool');
has 'streams' => (is => 'rw', isa => 'Int');
has 'duration' => (is => 'rw', isa => 'Int');
has 'udp_bandwidth' => (is => 'rw', isa => 'Int');
has 'buffer_length' => (is => 'rw', isa => 'Int');

has '_results_directory' => (is => 'rw', isa => 'Str');

my $logger = get_logger(__PACKAGE__);

override 'type' => sub { "bwctl" };

override 'allows_bidirectional' => sub { 1 };

override 'handles_own_scheduling' => sub { 1; };

override 'valid_schedule' => sub {
    my ($self, @args) = @_;
    my $parameters = validate( @args, {
                                         schedule => 0,
                                      });
    my $schedule = $parameters->{schedule};

    return 1 if ($schedule->type eq "regular_intervals");

    return;
};

override 'init_test' => sub {
    my ($self, @args) = @_;
    my $parameters = validate( @args, {
                                         source => 1,
                                         destination => 1,
                                         schedule => 0,
                                         config => 0,
                                      });
    my $source         = $parameters->{source};
    my $destination    = $parameters->{destination};
    my $schedule       = $parameters->{schedule};
    my $config         = $parameters->{config};

    my $results_dir = tempdir($config->test_result_directory."/bwctl_XXXXX", CLEANUP => 1);
    unless ($results_dir) {
        die("Couldn't create directory to store results");
    }

    $self->_results_directory($results_dir);

    return;
};

override 'run_test' => sub {
    my ($self, @args) = @_;
    my $parameters = validate( @args, {
                                         source => 1,
                                         destination => 1,
                                         schedule => 0,
                                         handle_results => 1,
                                      });
    my $source         = $parameters->{source};
    my $destination    = $parameters->{destination};
    my $schedule       = $parameters->{schedule};
    my $handle_results = $parameters->{handle_results};

    my @cmd = ();
    push @cmd, $self->bwctl_cmd;
    push @cmd, ( '-s', $source ) if $source;
    push @cmd, ( '-c', $destination ) if $destination;
    push @cmd, ( '-T', $self->tool ) if $self->tool;
    push @cmd, '-4' if $self->force_ipv4;
    push @cmd, '-6' if $self->force_ipv6;
    push @cmd, '-u' if $self->use_udp;
    push @cmd, ( '-P', $self->streams ) if $self->streams;
    push @cmd, ( '-t', $self->duration ) if $self->duration;
    push @cmd, ( '-b', $self->udp_bandwidth ) if $self->udp_bandwidth;
    push @cmd, ( '-l', $self->buffer_length ) if $self->buffer_length;

    # Add the scheduling information
    push @cmd, ( '-I', $schedule->interval );
    push @cmd, ( '-p', '-d', $self->_results_directory );

    $logger->debug("Executing ".join(" ", @cmd));

    my %handled = ();
    eval {
        my ($out, $err);

        my $bwctl_process = start \@cmd, \undef, \$out, \$err;
        unless ($bwctl_process) {
            die("Problem running command: $?");
        }

        while (1) {
            pump $bwctl_process;

            my @files = split('\n', $out);
            foreach my $file (@files) {
                next if $handled{$file};

                my $results = $self->build_results({ file => $file });

                next unless $results;

                $handle_results->(results => $results);

                $handled{$file} = 1;
            }
        }
    };
    if ($@) {
        $logger->error("Problem running tests: $@");
    }
};

sub build_results {
    my ($self, @args) = @_;
    my $parameters = validate( @args, { 
                                         file => 1,
                                      });
    my $file = $parameters->{file};

    open(FILE, $file) or return;
    my $contents = do { local $/ = <FILE> };
    close(FILE);
    unlink($file);

    my $results = perfSONAR_PS::RegularTesting::Results::ThroughputTest->new();

    my $protocol;
    if ($self->use_udp) {
        $protocol = "udp";
    }
    else {
        $protocol = "tcp";
    }

    $results->source->protocol($protocol);
    $results->destination->protocol($protocol);

    $results->streams($self->streams);
    $results->time_duration($self->duration);
    $results->bandwidth_limit($self->udp_bandwidth) if $self->udp_bandwidth;
    $results->buffer_length($self->buffer_length) if $self->buffer_length;

    parse_bwctl_output({ stdout => $contents, results => $results });

    return $results;
}

1;
