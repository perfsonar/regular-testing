package perfSONAR_PS::RegularTesting::Tests::Bwtraceroute;

use strict;
use warnings;

our $VERSION = 3.4;

use IPC::Run qw( start pump );
use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);
use File::Temp qw(tempdir);

use Moose;

extends 'perfSONAR_PS::RegularTesting::Tests::BwctlBase';

has 'bwtraceroute_cmd' => (is => 'rw', isa => 'Str', default => '/usr/bin/bwtraceroute');
has 'packet_length' => (is => 'rw', isa => 'Int');
has 'packet_first_ttl' => (is => 'rw', isa => 'Int', );
has 'packet_max_ttl' => (is => 'rw', isa => 'Int', );

my $logger = get_logger(__PACKAGE__);

override 'type' => sub { "bwtraceroute" };

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
    push @cmd, $self->bwtraceroute_cmd;

    # Add the parameters from the parent class
    push @cmd, super();

    # XXX: need to set interpacket time

    push @cmd, ( '-F', $self->packet_first_ttl ) if $self->packet_first_ttl;
    push @cmd, ( '-M', $self->packet_max_ttl ) if $self->packet_max_ttl;
    push @cmd, ( '-l', $self->packet_length ) if $self->packet_length;

    return @cmd;
};

override 'build_results' => sub {
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

#    my $protocol;
#    if ($self->use_udp) {
#        $protocol = "udp";
#    }
#    else {
#        $protocol = "tcp";
#    }
#
#    $results->source->protocol($protocol);
#    $results->destination->protocol($protocol);
#
#    $results->streams($self->streams);
#    $results->time_duration($self->duration);
#    $results->bandwidth_limit($self->udp_bandwidth) if $self->udp_bandwidth;
#    $results->buffer_length($self->buffer_length) if $self->buffer_length;
#
#    parse_bwctl_output({ stdout => $contents, results => $results });

    $results->raw_results($contents);

    return $results;
};

1;
