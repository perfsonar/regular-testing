package perfSONAR_PS::RegularTesting::Tests::Bwctl;

use strict;
use warnings;

our $VERSION = 3.4;

use IPC::Run qw( run );
use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);

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

#use perfSONAR_PS::RegularTesting::Utils qw(parse_target);

use perfSONAR_PS::RegularTesting::Parsers::Bwctl qw(parse_bwctl_output);

my $logger = get_logger(__PACKAGE__);

override 'type' => sub { "bwctl" };

override 'allows_bidirectional' => sub { 1 };

override 'valid_target' => sub {
    my ($self, @args) = @_;
    my $parameters = validate( @args, {
                                         target => 0,
                                      });
    my $target = $parameters->{target};

    return 1;
};

override 'run_once' => sub {
    my ($self, @args) = @_;
    my $parameters = validate( @args, {
                                         source => 1,
                                         destination => 1,
                                      });
    my $source = $parameters->{source};
    my $destination = $parameters->{destination};

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

    $logger->debug("Executing ".join(" ", @cmd));

    my ($out, $err);

    unless (run \@cmd, \undef, \$out, \$err) {
        my $error = "Problem running command: $?";
        $logger->error($error);
    }

    my $results = $self->build_results({ stdout => $out, stderr => $err });

    use Data::Dumper;

    print "Results: ".Dumper($results->unparse)."\n";

    return $results;
};

sub build_results {
    my ($self, @args) = @_;
    my $parameters = validate( @args, { 
                                         stdout => 1,
                                         stderr => 1,
                                      });
    my $stdout = $parameters->{stdout};
    my $stderr = $parameters->{stderr};

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

    parse_bwctl_output({ stdout => $stdout, stderr => $stderr, results => $results });

    return $results;
}

1;
