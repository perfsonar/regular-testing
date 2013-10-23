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

extends 'perfSONAR_PS::RegularTesting::Tests::BwctlBase';

has 'bwctl_cmd' => (is => 'rw', isa => 'Str', default => '/usr/bin/bwctl');
has 'tool' => (is => 'rw', isa => 'Str', default => 'iperf');
has 'use_udp' => (is => 'rw', isa => 'Bool');
has 'streams' => (is => 'rw', isa => 'Int');
has 'duration' => (is => 'rw', isa => 'Int');
has 'udp_bandwidth' => (is => 'rw', isa => 'Int');
has 'buffer_length' => (is => 'rw', isa => 'Int');

my $logger = get_logger(__PACKAGE__);

override 'type' => sub { "bwctl" };

override 'build_cmd' => sub {
    my ($self, @args) = @_;
    my $parameters = validate( @args, {
                                         source => 1,
                                         destination => 1,
                                         schedule => 0,
                                      });
    my $source         = $parameters->{source};
    my $destination    = $parameters->{destination};
    my $schedule       = $parameters->{schedule};

    my @cmd = ();
    push @cmd, $self->bwctl_cmd;

    # Add the parameters from the parent class
    push @cmd, super();

    push @cmd, '-u' if $self->use_udp;
    push @cmd, ( '-P', $self->streams ) if $self->streams;
    push @cmd, ( '-t', $self->duration ) if $self->duration;
    push @cmd, ( '-b', $self->udp_bandwidth ) if $self->udp_bandwidth;
    push @cmd, ( '-l', $self->buffer_length ) if $self->buffer_length;

    return @cmd;
};

override 'build_results' => sub {
    my ($self, @args) = @_;
    my $parameters = validate( @args, { 
                                         source => 1,
                                         destination => 1,
                                         schedule => 0,
                                         output => 1,
                                      });
    my $source         = $parameters->{source};
    my $destination    = $parameters->{destination};
    my $schedule       = $parameters->{schedule};
    my $output         = $parameters->{output};

    my $results = perfSONAR_PS::RegularTesting::Results::ThroughputTest->new();

    my $protocol;
    if ($self->use_udp) {
        $protocol = "udp";
    }
    else {
        $protocol = "tcp";
    }

    # Fill in the information we know about the test
    $results->source($self->build_endpoint(address => $source, protocol => $protocol));
    $results->destination($self->build_endpoint(address => $destination, protocol => $protocol));

    $results->streams($self->streams);
    $results->time_duration($self->duration);
    $results->bandwidth_limit($self->udp_bandwidth) if $self->udp_bandwidth;
    $results->buffer_length($self->buffer_length) if $self->buffer_length;

    # Add in the raw output
    $results->raw_results($output);

    # Parse the bwctl output, and add it in
    my $bwctl_results = parse_bwctl_output({ stdout => $output, tool_type => $self->tool });

    $results->test_time($bwctl_results->{start_time});

    $results->source->address($bwctl_results->{results}->{source}) if $bwctl_results->{results}->{source};
    $results->destination->address($bwctl_results->{results}->{destination}) if $bwctl_results->{results}->{destination};

    if ($bwctl_results->{error}) {
        $results->error($bwctl_results->{error});
    }
    elsif ($bwctl_results->{results}->{error}) {
        $results->error($bwctl_results->{results}->{error});
    }

    $results->test_time($bwctl_results->{start_time});

    $results->throughput($bwctl_results->{results}->{throughput}) if $bwctl_results->{results}->{throughput};
    $results->jitter($bwctl_results->{results}->{jitter}) if $bwctl_results->{results}->{jitter};
    $results->packets_sent($bwctl_results->{results}->{packets_sent}) if defined $bwctl_results->{results}->{packets_sent};
    $results->packets_lost($bwctl_results->{results}->{packets_lost}) if defined $bwctl_results->{results}->{packets_lost};

    return $results;
};

1;
