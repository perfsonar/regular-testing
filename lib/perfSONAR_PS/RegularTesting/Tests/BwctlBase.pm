package perfSONAR_PS::RegularTesting::Tests::BwctlBase;

use strict;
use warnings;

our $VERSION = 3.4;

use IPC::Run qw( start pump );
use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);
use File::Temp qw(tempdir);

use Moose;

extends 'perfSONAR_PS::RegularTesting::Tests::Base';

# Common to all bwctl-ish commands
has 'tool' => (is => 'rw', isa => 'Str');
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
                                         destination => 1,
                                         schedule => 0,
                                         handle_results => 1,
                                      });
    my $source         = $parameters->{source};
    my $destination    = $parameters->{destination};
    my $schedule       = $parameters->{schedule};
    my $handle_results = $parameters->{handle_results};

    my @cmd = $self->build_cmd({ source => $source, destination => $destination, schedule => $schedule });

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

    die("'build_results' should be overridden");
}

1;
