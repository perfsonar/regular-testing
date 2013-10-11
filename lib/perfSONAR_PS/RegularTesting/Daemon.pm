package perfSONAR_PS::RegularTesting::Daemon;

use strict;
use warnings;

our $VERSION = 3.4;

use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);
use Time::HiRes;

use Moose;

has 'config'       => (is => 'rw', isa => 'HashRef');
has 'exiting'      => (is => 'rw', isa => 'Bool');
has 'tests'        => (is => 'rw', isa => 'ArrayRef[HashRef]');
has 'test_by_pid'  => (is => 'rw', isa => 'HashRef[TestBase]');

my $logger = get_logger(__PACKAGE__);

sub init {
    my ($self, @args) = @_;
    my $parameters = validate( @args, { 
                                         config => 1,
                                      });
    my $config = $parameters->{config};
    $self->config($config);

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

    foreach my $test (@{ $self->tests }) {
        $self->run_test($test);
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
            $test->run();
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
        $logger->info("Child $pid hasn't exited. Sending SIGKILL");
        kill('KILL', $pid);
    }

    return;
}

1;
