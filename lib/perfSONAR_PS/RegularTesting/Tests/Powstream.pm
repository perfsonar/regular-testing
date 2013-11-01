package perfSONAR_PS::RegularTesting::Tests::Powstream;

use strict;
use warnings;

our $VERSION = 3.4;

use IPC::Run qw( start pump );
use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);
use File::Temp qw(tempdir);

use Data::Validate::IP qw(is_ipv4);
use Data::Validate::Domain qw(is_hostname);
use Net::IP;

use perfSONAR_PS::RegularTesting::Utils qw(owptime2datetime);

use perfSONAR_PS::RegularTesting::Parsers::Owamp qw(parse_owamp_raw_file parse_owamp_summary_file);
use perfSONAR_PS::RegularTesting::Results::LatencyTest;
use perfSONAR_PS::RegularTesting::Results::LatencyTestDatum;

use Moose;

extends 'perfSONAR_PS::RegularTesting::Tests::Base';

has 'powstream_cmd'     => (is => 'rw', isa => 'Str', default => '/usr/bin/powstream');
has 'owstats_cmd'       => (is => 'rw', isa => 'Str', default => '/usr/bin/owstats');
has 'force_ipv4'        => (is => 'rw', isa => 'Bool');
has 'force_ipv6'        => (is => 'rw', isa => 'Bool');
has 'resolution'        => (is => 'rw', isa => 'Int', default => 60);
has 'packet_length'     => (is => 'rw', isa => 'Int', default => 0);
has 'inter_packet_time' => (is => 'rw', isa => 'Num', default => 0.1);

has '_results_directory' => (is => 'rw', isa => 'Str');

my $logger = get_logger(__PACKAGE__);

override 'type' => sub { "powstream" };

override 'allows_bidirectional' => sub { 1 };

override 'handles_own_scheduling' => sub { 1; };

override 'valid_schedule' => sub {
    my ($self, @args) = @_;
    my $parameters = validate( @args, {
                                         schedule => 0,
                                      });
    my $schedule = $parameters->{schedule};

    return 1 if ($schedule->type eq "streaming");

    return;
};

override 'init_test' => sub {
    my ($self, @args) = @_;
    my $parameters = validate( @args, {
                                         source => 1,
                                         source_local => 1,
                                         destination => 1,
                                         destination_local => 1,
                                         schedule => 0,
                                         config => 0,
                                      });
    my $source            = $parameters->{source};
    my $source_local      = $parameters->{source_local};
    my $destination       = $parameters->{destination};
    my $destination_local = $parameters->{destination_local};
    my $schedule          = $parameters->{schedule};
    my $config            = $parameters->{config};

    my $results_dir = tempdir($config->test_result_directory."/owamp_XXXXX", CLEANUP => 1);
    unless ($results_dir) {
        die("Couldn't create directory to store results");
    }

    $self->_results_directory($results_dir);

    unless ($source_local or $destination_local) {
        die("powstream does not support third party tests");
    }

    return;
};

override 'run_test' => sub {
    my ($self, @args) = @_;
    my $parameters = validate( @args, {
                                         source => 1,
                                         source_local => 1,
                                         destination => 1,
                                         destination_local => 1,
                                         schedule => 0,
                                         handle_results => 1,
                                      });
    my $source            = $parameters->{source};
    my $source_local      = $parameters->{source_local};
    my $destination       = $parameters->{destination};
    my $destination_local = $parameters->{destination_local};
    my $schedule          = $parameters->{schedule};
    my $handle_results    = $parameters->{handle_results};

    my $local_address;
    my $reverse_direction;
    my $remote_address;

    if ($source_local) {
        $local_address  = $source;
        $remote_address = $destination;
        $reverse_direction = 1;
    }
    elsif ($destination_local) {
        $local_address  = $destination;
        $remote_address = $source;
    }

    # Calculate the total number of packets from the resolution
    my $packets = $self->resolution / $self->inter_packet_time;

    my @cmd = ();
    push @cmd, $self->powstream_cmd;
    push @cmd, '-4' if $self->force_ipv4;
    push @cmd, '-6' if $self->force_ipv6;
    push @cmd, ( '-p', '-d', $self->_results_directory );
    push @cmd, ( '-c', $packets );
    push @cmd, ( '-s', $self->packet_length ) if $self->packet_length;
    push @cmd, ( '-i', $self->inter_packet_time ) if $self->inter_packet_time;
    push @cmd, ( '-S', $local_address ) if $local_address;
    push @cmd, '-t' if $reverse_direction;
    push @cmd, $remote_address;

    $logger->debug("Executing ".join(" ", @cmd));

    my $powstream_process;
    my %handled = ();
    eval {
        my ($out, $err);

        $powstream_process = start \@cmd, \undef, \$out, \$err;
        unless ($powstream_process) {
            die("Problem running command: $?");
        }

        my %tests = ();
        while (1) {
            pump $powstream_process;

            my @files = split('\n', $out);
            foreach my $file (@files) {
                next if $handled{$file};

                my ($test_id, $file_type);
                if ($file =~ /(.*).(owp)$/) {
                    $test_id = $1;
                    $file_type = $2;
                }
                elsif ($file =~ /(.*).(sum)$/) {
                    $test_id = $1;
                    $file_type = $2;
                }
                else {
                    next;
                }

                $tests{$test_id} = {} unless $tests{$test_id};
                $tests{$test_id}->{$file_type} = $file;

                $handled{$file} = 1;
            }

            foreach my $test_id (sort keys %tests) {
                unless ($tests{$test_id}->{sum} and 
                        $tests{$test_id}->{owp}) {
                    next;
                }

                my $results = $self->build_results({
                                                     source => $source,
                                                     destination => $destination,
                                                     schedule => $schedule,
                                                     raw_file => $tests{$test_id}->{owp},
                                                     summary_file => $tests{$test_id}->{sum},
                                                  });
                unless ($results) {
                    $logger->error("Problem parsing test results");
                    next;
                }

                eval {
                    $handle_results->(results => $results);
                };
                if ($@) {
                    $logger->error("Problem saving results: $results");
                    next;
                }

                unlink($tests{$test_id}->{owp});
                unlink($tests{$test_id}->{sum});
                delete($tests{$test_id});
            }
        }
    };
    if ($@) {
        $logger->error("Problem running tests: $@");
        if ($powstream_process) {
            $powstream_process->kill_kill();
            finish $powstream_process;
        }
    }

    return;
};

sub build_results {
    my ($self, @args) = @_;
    my $parameters = validate( @args, { 
                                         source => 1,
                                         destination => 1,
                                         schedule => 0,
                                         raw_file => 1,
                                         summary_file => 1,
                                      });
    my $source         = $parameters->{source};
    my $destination    = $parameters->{destination};
    my $schedule       = $parameters->{schedule};
    my $raw_file       = $parameters->{raw_file};
    my $summary_file   = $parameters->{summary_file};

    my $raw             = parse_owamp_raw_file({ owstats => $self->owstats_cmd, raw_file => $raw_file });
    my $summary         = parse_owamp_summary_file({ summary_file => $summary_file });

    unless ($raw and $summary) {
        $logger->error("Problem parsing test results");
        return;
    }

    use Data::Dumper;
    $logger->debug("Raw output: ".Dumper($raw));
    $logger->debug("Summary output: ".Dumper($summary));

    my $results = perfSONAR_PS::RegularTesting::Results::LatencyTest->new();

    # Fill in the information we know about the test
    $results->source($self->build_endpoint(address => $source, protocol => "udp" ));
    $results->destination($self->build_endpoint(address => $destination, protocol => "udp" ));

    $results->packet_count($self->resolution/$self->inter_packet_time);
    $results->packet_size($self->packet_length);
    $results->inter_packet_time($self->inter_packet_time);

    my $from_addr = $summary->{FROM_ADDR};
    my $to_addr = $summary->{TO_ADDR};

    $from_addr =~ s/%.*//;
    $to_addr =~ s/%.*//;

    $results->source->address($from_addr) if $from_addr;
    $results->destination->address($to_addr) if $to_addr;
    $results->start_time(owptime2datetime($summary->{START_TIME}));
    $results->end_time(owptime2datetime($summary->{END_TIME}));

    my @pings = ();

    if ($raw->{packets}) {
        foreach my $ping (@{ $raw->{packets} }) {
            my $datum = perfSONAR_PS::RegularTesting::Results::LatencyTestDatum->new();
            $datum->sequence_number($ping->{sequence_number}) if defined $ping->{sequence_number};
            $datum->ttl($ping->{ttl}) if defined $ping->{ttl};
            # Convert delays to 'ms'
            $datum->delay($ping->{delay} * 1000) if defined $ping->{delay};
            push @pings, $datum;
        }
    }

    $results->pings(\@pings);

    # XXX: look into error conditions

    # XXX: I'm guessing the raw results should be the owp? I'm dunno
    $results->raw_results("");

    use Data::Dumper;
    $logger->debug("Results: ".Dumper($results->unparse));

    return $results;
};

sub build_endpoint {
    my ($self, @args) = @_;
    my $parameters = validate( @args, { 
                                         address  => 1,
                                         port     => 0,
                                         protocol => 0,
                                      });
    my $address        = $parameters->{address};
    my $port           = $parameters->{port};
    my $protocol       = $parameters->{protocol};

    my $endpoint = perfSONAR_PS::RegularTesting::Results::Endpoint->new();

    if ( is_ipv4( $address ) or 
         &Net::IP::ip_is_ipv6( $address ) ) {
        $endpoint->address($address);
    }
    else {
        $endpoint->hostname($address);
    }

    $endpoint->port($port) if $port;
    $endpoint->protocol($protocol) if $protocol;

    return $endpoint;
}

1;
