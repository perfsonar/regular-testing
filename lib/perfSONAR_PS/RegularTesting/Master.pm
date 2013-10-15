package perfSONAR_PS::RegularTesting::Master;

use strict;
use warnings;

our $VERSION = 3.4;

use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);
use Time::HiRes;
use POSIX;

use perfSONAR_PS::RegularTesting::Config;

use Moose;

has 'config'       => (is => 'rw', isa => 'perfSONAR_PS::RegularTesting::Config');
has 'exiting'      => (is => 'rw', isa => 'Bool');
has 'test_by_pid'  => (is => 'rw', isa => 'HashRef[TestBase]', default => sub { {} } );

my $logger = get_logger(__PACKAGE__);

sub init {
    my ($self, @args) = @_;
    my $parameters = validate( @args, { 
                                         config => 1,
                                      });
    my $config = $parameters->{config};

    my $parsed_config = perfSONAR_PS::RegularTesting::Config->new();
    $parsed_config->init({ config => $config });

    $self->config($parsed_config);

    $self->exiting(0);

    return;
}

sub run {
    my ($self) = @_;

    $SIG{CHLD} = sub {
        $self->handle_child_exit();
    };

    $SIG{TERM} = $SIG{INT} = sub {
        $self->handle_exit();
    };

    foreach my $test (@{ $self->config->tests }) {
        $self->run_test($test);
    }

    while (1) {
       sleep(-1); # infinite sleep
    }

    return;
}

sub run_test {
    my ($self, $test) = @_;

    eval {
        my $pid = fork();
        if ($pid < 0) {
            die("Couldn't create testing process for ".$test->description);
        }

        unless ($pid) {
            # Child process
            $self->handle_test($test);
            exit 0;
        }

        $self->test_by_pid->{$pid} = $test;
    };
    if ($@) {
        $logger->error("Problem with test ".$test->description.": ".$@);
    }
}

sub handle_child_exit {
    my ($self) = @_;

    while( ( my $child = waitpid( -1, &WNOHANG ) ) > 0 ) {
        my $test = $self->test_by_pid->{$child};
        if (not $test) {
            $logger->debug("Received SIGCHLD for unknown PID: ".$child);
            next;
        }

        delete($self->test_by_pid->{$child});

        unless ($self->exiting) {
            $logger->debug("Test ".$test->description." exited. Restarting...");
            $self->run_test($test);
        }
    }

    return;
}

sub handle_exit {
    my ($self) = @_;

    $self->exiting(1);

    foreach my $pid (keys %{ $self->test_by_pid }) {
        kill('TERM', $pid);
    }

    # Wait for processes to exit
    my $waketime = time + 1;
    while ((my $sleep_time = $waketime - time) > 0) {
        sleep($sleep_time);
    }

    foreach my $pid (keys %{ $self->test_by_pid }) {
        $logger->debug("Child $pid hasn't exited. Sending SIGKILL");
        kill('KILL', $pid);
    }

    exit(0);
}

sub handle_test {
    my ($self, $test) = @_;

    while (1) {
        my $next_runtime = $test->calculate_next_run_time();

        while ((my $sleep_time = $next_runtime - time) > 0) {
            $logger->debug("Waiting for ".$sleep_time." seconds for next runtime of test ".$test->description);
            sleep($sleep_time);

            if ($self->exiting) {
                exit(0);
            }
        }

        if ($self->exiting) {
            exit(0);
        }

        $logger->debug("Running test: ".$test->description);
        my $results;
        eval {
            $results = $test->run_once();
        };
        if ($@) {
            my $error = $@;
            $logger->error("Problem running test: ".$test->description.": ".$error);
            #$self->error($@);
        };

        if ($self->exiting) {
            exit(0);
        }

        #$self->store_results($results);
    }

    return;
};

1;
