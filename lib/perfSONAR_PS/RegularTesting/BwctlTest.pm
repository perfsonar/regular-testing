package perfSONAR_PS::RegularTesting::BwctlTest;

use strict;
use warnings;

our $VERSION = 3.4;

use IPC::Run qw( run );
use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);

use Moose;

extends 'perfSONAR_PS::RegularTesting::IntervalTestBase';

has 'bwctl_cmd' => (is => 'rw', isa => 'Str', default => '/usr/bin/bwctl');
has 'source_address' => (is => 'rw', isa => 'Str');
has 'destination_address' => (is => 'rw', isa => 'Str');
has 'tool' => (is => 'rw', isa => 'Str');
has 'force_ipv4' => (is => 'rw', isa => 'Bool');
has 'force_ipv6' => (is => 'rw', isa => 'Bool');
has 'use_udp' => (is => 'rw', isa => 'Bool');
has 'streams' => (is => 'rw', isa => 'Int');
has 'duration' => (is => 'rw', isa => 'Int');
has 'udp_bandwidth' => (is => 'rw', isa => 'Int');

use perfSONAR_PS::RegularTesting::Parsers::Iperf qw(parse_iperf_output);

my $logger = get_logger(__PACKAGE__);

after 'init' => sub {
    my ($self) = @_;

    unless ($self->source_address or $self->destination_address) {
        die("Either 'source_address' or 'destination_address' need to be specified");
    }
};

override 'run_once' => sub {
    my ($self) = @_;

    my @cmd = ();
    push @cmd, $self->bwctl_cmd;
    push @cmd, ( '-s', $self->source_address ) if $self->source_address;
    push @cmd, ( '-c', $self->destination_address ) if $self->destination_address;
    push @cmd, ( '-T', $self->tool ) if $self->tool;
    push @cmd, '-4' if $self->force_ipv4;
    push @cmd, '-6' if $self->force_ipv6;
    push @cmd, '-u' if $self->use_udp;
    push @cmd, ( '-P', $self->streams ) if $self->streams;
    push @cmd, ( '-t', $self->duration ) if $self->duration;
    push @cmd, ( '-b', $self->udp_bandwidth ) if $self->udp_bandwidth;

    $logger->debug("Executing ".join(" ", @cmd));

    my ($out, $err);

    unless (run \@cmd, \undef, \$out, \$err) {
        my $error = "Problem running command: $?";
        $logger->error($error);
    }

    my $results = parse_iperf_output({ stdout => $out, stderr => $err });

    use Data::Dumper;

    print "Results: ".Dumper($results->unparse)."\n";

    return $results;
};

1;
