package perfSONAR_PS::RegularTesting::Tests::BwctlBase;

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

use perfSONAR_PS::RegularTesting::Results::Endpoint;

use Moose;

extends 'perfSONAR_PS::RegularTesting::Tests::Base';

# Common to all bwctl-ish commands
has 'force_ipv4' => (is => 'rw', isa => 'Bool');
has 'force_ipv6' => (is => 'rw', isa => 'Bool');

has '_results_directory' => (is => 'rw', isa => 'Str');

my $logger = get_logger(__PACKAGE__);

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
                                         source_local => 1,
                                         destination => 1,
                                         destination_local => 1,
                                         schedule => 0,
                                         config => 0,
                                      });
    my $source            = $parameters->{source};
    my $source_local      = $parameters->{source};
    my $destination       = $parameters->{destination};
    my $destination_local = $parameters->{destination};
    my $schedule          = $parameters->{schedule};
    my $config            = $parameters->{config};

    my $results_dir = tempdir($config->test_result_directory."/bwctl_XXXXX", CLEANUP => 1);
    unless ($results_dir) {
        die("Couldn't create directory to store results");
    }

    $self->_results_directory($results_dir);

    return;
};

sub build_cmd {
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
    push @cmd, ( '-s', $source ) if $source;
    push @cmd, ( '-c', $destination ) if $destination;
    push @cmd, ( '-T', $self->tool ) if $self->tool;
    push @cmd, '-4' if $self->force_ipv4;
    push @cmd, '-6' if $self->force_ipv6;

    # Add the scheduling information
    push @cmd, ( '-I', $schedule->interval );
    push @cmd, ( '-p', '-d', $self->_results_directory );

    return @cmd;
}

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

    my @cmd = $self->build_cmd({ source => $source, destination => $destination, schedule => $schedule });

    $logger->debug("Executing ".join(" ", @cmd));

    my $bwctl_process;
    my %handled = ();
    eval {
        my ($out, $err);

        $bwctl_process = start \@cmd, \undef, \$out, \$err;
        unless ($bwctl_process) {
            die("Problem running command: $?");
        }

        while (1) {
            pump $bwctl_process;

            $logger->debug("IPC::Run::pump returned: out: ".$out." err: ".$err);

            my @files = split('\n', $out);
            foreach my $file (@files) {
                next if $handled{$file};

                $logger->debug("bwctl output: $file");

                open(FILE, $file) or next;
                my $contents = do { local $/ = <FILE> };
                close(FILE);

                my $results = $self->build_results({
                                                      source => $source,
                                                      destination => $destination,
                                                      schedule => $schedule,
                                                      output => $contents,
                                                  });

                next unless $results;

                eval {
                    $handle_results->(results => $results);
                };
                if ($@) {
                    $logger->error("Problem saving results: $results");
                    next;
                }

                unlink($file);

                $handled{$file} = 1;
            }
        }
    };
    if ($@) {
        $logger->error("Problem running tests: $@");
        if ($bwctl_process) {
            eval {
                $bwctl_process->kill_kill() 
            };
        }
    }

    if ($bwctl_process) {
        eval {
            finish $bwctl_process;
        };
    }

    return;
};

sub build_results {
    my ($self, @args) = @_;
    my $parameters = validate( @args, { 
                                         source => 1,
                                         destination => 1,
                                         schedule => 0,
                                         output => 1,
                                      });

    die("'build_results' should be overridden");
}

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
